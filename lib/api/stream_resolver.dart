// Resolves a playable stream URL for an [ApiSong] (FeedItem with type='song').
//
// Strategy (in order — first one that returns a usable URL wins):
//   0. If a [LocalSourceProvider] is attached and reports the song is
//      available offline, use that local URL. The downloads layer plugs
//      in here without the handler needing to know about offline storage.
//   1. If the song already carries `mediaUrls`, pick a variant from that
//      list per the current `quality` preference. Zero network round-trips.
//   2a. Podcasts (`source == 'podcastindex'`) re-fetch through
//       `/podcasts/episode/:id` — `/music/song/` 400s for podcast ids,
//       so it's a dead end. We bail here for podcasts after that one
//       attempt rather than falling through to the music tiers.
//   2b. Hit `/music/song/:id?provider=…` — full saavn/gaana song endpoint,
//      response contains `mediaUrls`. Used when restoring from persisted
//      state where we don't keep URLs (signed gaana URLs expire).
//   3. For gaana specifically, fall back to `/music/song/:id/stream?provider=gaana`
//      — that's the dedicated refresh endpoint that re-signs URLs.
//
// Quality preference (Settings → Stream quality, persisted via Hive):
//   - 'auto' / 'high' → highest available bitrate (320 → 160 → 96 → first)
//   - 'data'          → lowest available bitrate (cell-data saver)

import 'package:dio/dio.dart';

import '../audio/url_refresh.dart';
import 'dto.dart';
import 'local_media_channel.dart';
import 'lossless_api.dart';
import 'ytmusic_channel.dart';

/// User stream-quality preference. `auto` and `high` both prefer the highest
/// available variant; the distinction is reserved for the future (e.g. `auto`
/// could become network-adaptive). `data` caps the pick at the lowest
/// available so cellular sessions don't burn through bandwidth. `lossless`
/// adds a hi-res tier ahead of everything else and otherwise behaves like
/// `high`, so a track the lossless catalog lacks still plays at best quality
/// rather than failing.
enum StreamQuality { auto, high, data, lossless }

/// Extension point for offline / downloaded sources. Implementations live
/// in the downloads layer (not built yet); when wired, the resolver asks
/// here BEFORE going to the network. Returns `null` when the song isn't
/// available locally.
///
/// The returned URL should be something mpv can `open()` — typically
/// `file:///path/to/song.m4a` or a raw absolute path.
abstract interface class LocalSourceProvider {
  Future<String?> localUrlFor(String songId);
}

class StreamResolver {
  StreamResolver(this._dio);
  final Dio _dio;

  /// Drives variant selection in `_pick`. Mutated by AppState whenever the
  /// user changes Settings → Stream quality (and at startup when the saved
  /// value is restored from Hive).
  StreamQuality quality = StreamQuality.auto;

  /// Optional offline-source plugin. When set, [resolve] consults it
  /// before any network tier. Defaults to null (network-only). The
  /// downloads feature will set this once it lands.
  LocalSourceProvider? localSource;

  /// Hi-res lossless lookup. Set by AppState from Settings; null means the
  /// feature is compiled in but the user has not opted in, and the tier is
  /// skipped entirely at zero cost.
  LosslessApi? lossless;

  /// In-memory resolve cache keyed by song id. Populated on every successful
  /// resolve; consulted at the top of [resolve] for non-`forceRefresh` calls.
  ///
  /// Entries store the URL's parsed expiry (when present) so we can refuse
  /// to return a URL that's about to die. The handler's next-track pre-
  /// resolve fires 15 s before EOF and warms this cache; the cached URL
  /// is then consumed by `_advanceTo`'s on_load hook — so the cached URL
  /// is at most ~15 s old at consumption time, well inside its lifetime.
  /// The TTL check guards against longer gaps (paused queue, dragged-out
  /// scrubbing, etc.).
  final Map<String, _CacheEntry> _cache = <String, _CacheEntry>{};

  /// How close to expiry an entry must be before we treat it as stale and
  /// re-resolve. 60 s buffer covers the typical resolve+open round-trip.
  static const _kExpirySafetyBuffer = Duration(seconds: 60);

  /// Drop a cached entry — called from [resolve] on `forceRefresh: true`
  /// paths so the URL-refresh flow can't return a stale cached URL.
  void invalidate(String songId) => _cache.remove(songId);

  /// The current quality preference as the string form the native YouTube
  /// resolver expects.
  String _qualityParam() => switch (quality) {
    StreamQuality.high => 'high',
    StreamQuality.data => 'data',
    StreamQuality.auto => 'auto',
    // The lossy tiers have no notion of lossless; asking them for the best
    // they have is the right fallback when the hi-res catalog comes up empty.
    StreamQuality.lossless => 'high',
  };

  /// Ask the lossless catalog about [song] ahead of time.
  ///
  /// No-op unless the user chose lossless. Cheap enough to call on every track
  /// change: the API skips anything it already knows or is already fetching.
  void warmLossless(FeedItem song) {
    if (quality != StreamQuality.lossless) return;
    lossless?.warm(song, quality: _qualityParam());
  }

  /// Convenience setter for the Hive-persisted string form used in the UI.
  /// Unknown values fall back to `auto`.
  void setQualityFromString(String value) {
    final previous = quality;
    quality = switch (value) {
      'high' => StreamQuality.high,
      'data' => StreamQuality.data,
      'lossless' => StreamQuality.lossless,
      _ => StreamQuality.auto,
    };
    // Cached URLs were resolved at the old quality, and the cache is keyed by
    // song id alone. Without this, turning Lossless on and pressing play on
    // anything heard this session serves the lossy URL still sitting in the
    // cache — and the setting looks broken.
    if (quality != previous) _cache.clear();
  }

  /// Returns a playable URL for [song], or throws [StreamResolveException]
  /// if no usable variant could be obtained. When the lookup goes through
  /// `/music/song/:id` (tier 2), the parsed enriched FeedItem rides along
  /// in [ResolvedStream.enriched] so the caller can backfill metadata
  /// (artists, duration, subtitle) that search responses leave empty.
  ///
  /// Set [forceRefresh] when re-resolving for an *already-played* track
  /// whose signed URL may have expired (mid-track refresh path). With it
  /// set, step 1 (inline mediaUrls embedded in the FeedItem) is skipped
  /// — the embedded URLs are the original signed ones from when the feed
  /// was fetched, which is the exact set of URLs we need to bypass.
  Future<ResolvedStream> resolve(
    FeedItem song, {
    bool forceRefresh = false,
    bool network = false,
  }) async {
    // 0) Offline tier — short-circuits everything. forceRefresh DOESN'T
    //    bypass this because local files don't have expiry; the only
    //    reason to "force refresh" is a stale signed URL, which is a
    //    network concern.
    //
    // `network: true` *does* bypass this — used by the Cast path where
    // the Cast receiver can't reach the phone's `file://` paths and we
    // genuinely need a public-network URL.
    final local = localSource;
    if (local != null && !network) {
      try {
        final url = await local.localUrlFor(song.id);
        if (url != null && url.isNotEmpty) {
          return ResolvedStream(url);
        }
      } catch (_) {
        // Local lookup failed — fall through to the network tiers.
      }
    }

    // 0a) On-device music. The path came straight from MediaStore and is
    //     already what mpv wants, so there is nothing to resolve and nothing
    //     that can expire. Bails after this: no network tier can answer for a
    //     file that only exists on this phone.
    //
    //     `network: true` (the Cast path) is deliberately NOT honoured — a
    //     Cast receiver cannot reach the phone's filesystem, so casting a
    //     local track is a dead end either way, and failing here is clearer
    //     than handing the receiver a URL it will silently refuse.
    if (song.source == kLocalSource) {
      final path = song.url ?? '';
      if (path.isEmpty) {
        throw StreamResolveException(
          'On-device track "${song.title}" has no file path.',
        );
      }
      return ResolvedStream(path);
    }

    // 0b) A cached answer, before any tier that would go to the network.
    //
    //     Hoisted above the lossless and YouTube tiers rather than left at 1a:
    //     both of those return unconditionally, so with the check further down
    //     a track already resolved this session still paid a full round trip
    //     to be told what the cache already held. On the on_load hook, the
    //     pre-resolve tick and the Cast path, that is up to a second of
    //     silence for nothing.
    //
    //     forceRefresh drops the entry instead — that path exists precisely
    //     because the cached URL is suspected dead.
    if (forceRefresh) {
      _cache.remove(song.id);
    } else {
      final cached = _cache[song.id];
      if (cached != null && !_isStale(cached)) return cached.stream;
      if (cached != null) _cache.remove(song.id);
    }

    // 0c) Hi-res lossless, when chosen. Ahead of BOTH the YouTube and
    //     inline-`mediaUrls` tiers because each of those returns
    //     unconditionally — reaching either first would mean a track that
    //     exists in hi-res never plays in hi-res, and the setting is global
    //     so YouTube cannot be the exception. Non-throwing and time-bounded:
    //     a miss falls through and plays from the song's own source.
    //
    //     LosslessApi answers from its own memory for anything looked up this
    //     session, hit or miss, so this is a network call once per track.
    final ll = lossless;
    if (quality == StreamQuality.lossless && ll != null) {
      final hit = await ll.resolve(song, quality: _qualityParam());
      if (hit != null) {
        return _store(song.id, ResolvedStream(hit.url), expiry: hit.expiresAt);
      }
    }

    // 0d) YouTube Music. Resolved natively (see lib/api/ytmusic_channel.dart
    //     for why it can't be done from Dart) and never cached here — the
    //     native side owns client selection and PO-token lifetime, and its
    //     URLs carry their own expiry which we surface to the refresh
    //     scheduler. Bails after one attempt: no other tier can resolve a
    //     `youtube` id.
    if (song.source == 'youtube') {
      final yt = await YtMusicChannel.instance.resolve(
        song.id,
        quality: _qualityParam(),
      );
      if (yt == null) {
        throw StreamResolveException(
          'No playable stream for "${song.title}" (${song.id}).',
        );
      }
      return ResolvedStream(yt.url, httpHeaders: yt.headers);
    }

    // 1) Inline mediaUrls (fresh API responses include these). The cache was
    //    consulted at 0b, above the network tiers.
    if (!forceRefresh) {
      final embedded = _pick(song.mediaUrls);
      if (embedded != null) {
        return _store(song.id, ResolvedStream(embedded));
      }
    }

    final provider = song.source;

    // YouTube Music — resolved DIRECTLY from the device, not via
    // sunoh-api. The VPS IP is a datacenter address that YouTube
    // flags for bot detection (/player returns LOGIN_REQUIRED "Sign
    // in to confirm you're not a bot"). Hitting music.youtube.com
    // from the phone's residential IP avoids the check AND binds
    // the resulting stream URL to the phone's IP — no proxy needed.
    // Same architecture OuterTune uses.
    // Podcasts live in a parallel namespace — the `/music/song/...` path
    // is hardwired to saavn/gaana and 400s on `provider=podcastindex`. Refetch
    // the episode through `/podcasts/episode/:id` instead; that response
    // carries the enclosure URL as `mediaUrls[0].link`.
    if (provider == 'podcastindex') {
      try {
        final res = await _dio.get<Map<String, dynamic>>(
          '/podcasts/episode/${Uri.encodeComponent(song.id)}',
        );
        final dataRaw = res.data?['data'];
        if (dataRaw is Map) {
          final parsed = FeedItem.fromJson(dataRaw.cast<String, dynamic>());
          final url = _pick(parsed.mediaUrls);
          if (url != null) {
            return _store(song.id, ResolvedStream(url, enriched: parsed));
          }
        }
      } on DioException catch (_) {
        // Fall through to the throw — no other tier can recover a podcast.
      }
      throw StreamResolveException(
        'No playable stream variants for "${song.title}" (${song.id}).',
      );
    }

    final query = <String, dynamic>{
      if (provider != null && provider.isNotEmpty) 'provider': provider,
    };

    // 2) Full song endpoint — works for both providers, response contains
    //    `mediaUrls`. Also the source of truth for artists / duration /
    //    subtitle that search responses leave empty.
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/music/song/${song.id}',
        queryParameters: query,
      );
      final parsed = _enrichFromSongResponse(res.data);
      final url = _pick(parsed?.mediaUrls ?? const []);
      if (url != null) {
        return _store(song.id, ResolvedStream(url, enriched: parsed));
      }
    } on DioException catch (_) {
      // Fall through to /stream attempt.
    }

    // 3) Gaana refresh endpoint as last resort. Returns `data: List<{quality,link}>`.
    if (provider == 'gaana') {
      final res = await _dio.get<Map<String, dynamic>>(
        '/music/song/${song.id}/stream',
        queryParameters: query,
      );
      final env = ApiEnvelope.from<List<ApiImage>>(
        res.data ?? const {},
        ApiImage.listFrom,
      );
      if (env.isSuccess) {
        final picked = _pick(env.data ?? const []);
        if (picked != null) {
          return _store(song.id, ResolvedStream(picked));
        }
      }
    }

    throw StreamResolveException(
      'No playable stream variants for "${song.title}" (${song.id}).',
    );
  }

  /// [expiry] wins when the caller already knows it from the API response;
  /// otherwise it is parsed back out of the signed URL.
  ResolvedStream _store(
    String songId,
    ResolvedStream stream, {
    DateTime? expiry,
  }) {
    _cache[songId] = _CacheEntry(
      stream: stream,
      expiry: expiry ?? UrlRefreshScheduler.parseExpiry(stream.url),
    );
    return stream;
  }

  /// True if the cached entry is within [_kExpirySafetyBuffer] of expiry
  /// (or already past). Forces a fresh resolve so the on_load hook never
  /// hands mpv an about-to-die URL. Entries without a parseable expiry
  /// are treated as fresh — those URLs typically have no published TTL
  /// (saavn mediaUrls) and behave fine for long sessions.
  bool _isStale(_CacheEntry e) {
    final expiry = e.expiry;
    if (expiry == null) return false;
    return DateTime.now().isAfter(expiry.subtract(_kExpirySafetyBuffer));
  }

  /// Parse the `/music/song/:id` envelope (flat saavn vs gaana-nested-`song`)
  /// into a FeedItem. Returns null on shape mismatch.
  FeedItem? _enrichFromSongResponse(Map<String, dynamic>? body) {
    if (body == null) return null;
    final dataRaw = body['data'];
    if (dataRaw is! Map) return null;
    final data = dataRaw.cast<String, dynamic>();
    final inner = (data['song'] is Map)
        ? (data['song'] as Map).cast<String, dynamic>()
        : data;
    if (inner.isEmpty) return null;
    return FeedItem.fromJson(inner);
  }

  /// Pick a variant from the list per the current `quality` preference.
  /// Returns null if the list is empty.
  String? _pick(List<ApiImage> variants) {
    if (variants.isEmpty) return null;

    final sorted = [...variants]
      ..sort((a, b) => _score(b.quality).compareTo(_score(a.quality)));

    return switch (quality) {
      // Cell-data saver: lowest available variant.
      StreamQuality.data => sorted.last.link,
      // Default, 'high', and the lossless fallback: highest available.
      StreamQuality.auto ||
      StreamQuality.high ||
      StreamQuality.lossless => sorted.first.link,
    };
  }

  static int _score(String q) {
    final qq = q.toLowerCase();
    switch (qq) {
      case 'high':
        return 320;
      case 'medium':
        return 160;
      case 'low':
        return 96;
    }
    final m = RegExp(r'(\d+)').firstMatch(qq);
    return m == null ? 0 : int.tryParse(m.group(1)!) ?? 0;
  }
}

class StreamResolveException implements Exception {
  StreamResolveException(this.message, [this.cause]);
  final String message;
  final Object? cause;
  @override
  String toString() => 'StreamResolveException: $message';
}

/// Output of [StreamResolver.resolve]: the playable URL plus, when the
/// lookup hit `/music/song/:id`, the enriched FeedItem with artist /
/// duration / subtitle data that search responses leave empty.
class ResolvedStream {
  ResolvedStream(this.url, {this.enriched, this.httpHeaders});
  final String url;
  final FeedItem? enriched;

  /// Headers the media fetch must carry, or null when the URL needs none.
  ///
  /// Only the YouTube tier sets this: googlevideo URLs are signed against
  /// the InnerTube client that minted them, so the User-Agent has to match
  /// or the CDN answers 403. Applied to mpv via `http-header-fields`.
  final Map<String, String>? httpHeaders;
}

/// Cache entry — the resolved stream + the parsed signed-URL expiry (if
/// any). Stored only inside [StreamResolver]; callers see [ResolvedStream].
class _CacheEntry {
  _CacheEntry({required this.stream, required this.expiry});
  final ResolvedStream stream;
  final DateTime? expiry;
}
