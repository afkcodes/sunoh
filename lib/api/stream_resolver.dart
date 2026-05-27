// Resolves a playable stream URL for an [ApiSong] (FeedItem with type='song').
//
// Strategy (in order — first one that returns a usable URL wins):
//   0. If a [LocalSourceProvider] is attached and reports the song is
//      available offline, use that local URL. The downloads layer plugs
//      in here without the handler needing to know about offline storage.
//   1. If the song already carries `mediaUrls`, pick a variant from that
//      list per the current `quality` preference. Zero network round-trips.
//   2. Hit `/music/song/:id?provider=…` — this is the full song endpoint,
//      works for BOTH saavn and gaana, and the response contains `mediaUrls`.
//      Used when restoring from persisted state where we don't keep URLs
//      (gaana signed URLs expire and saavn ones may drift).
//   3. For gaana specifically, fall back to `/music/song/:id/stream?provider=gaana`
//      — that's the dedicated refresh endpoint that re-signs URLs.
//
// Quality preference (Settings → Stream quality, persisted via Hive):
//   - 'auto' / 'high' → highest available bitrate (320 → 160 → 96 → first)
//   - 'data'          → lowest available bitrate (cell-data saver)

import 'package:dio/dio.dart';

import '../audio/url_refresh.dart';
import 'dto.dart';

/// User stream-quality preference. `auto` and `high` both prefer the highest
/// available variant; the distinction is reserved for the future (e.g. `auto`
/// could become network-adaptive). `data` caps the pick at the lowest
/// available so cellular sessions don't burn through bandwidth.
enum StreamQuality { auto, high, data }

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

  /// Convenience setter for the Hive-persisted string form used in the UI.
  /// Unknown values fall back to `auto`.
  void setQualityFromString(String value) {
    quality = switch (value) {
      'high' => StreamQuality.high,
      'data' => StreamQuality.data,
      _ => StreamQuality.auto,
    };
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
  Future<ResolvedStream> resolve(FeedItem song,
      {bool forceRefresh = false, bool network = false}) async {
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

    if (forceRefresh) {
      // Stale-URL recovery path — drop any cached entry so the in-flight
      // pre-resolve from a prior tick can't return a known-bad URL.
      _cache.remove(song.id);
    } else {
      // 1a) Resolver cache hit (if still fresh) — populated by an earlier
      //     resolve. Returns synchronously so the on_load hook is fast.
      final cached = _cache[song.id];
      if (cached != null && !_isStale(cached)) {
        return cached.stream;
      }
      if (cached != null) {
        // Cached URL is too close to expiry — drop it and re-resolve.
        _cache.remove(song.id);
      }

      // 1b) Inline mediaUrls (fresh API responses include these).
      final embedded = _pick(song.mediaUrls);
      if (embedded != null) {
        return _store(song.id, ResolvedStream(embedded));
      }
    }

    final provider = song.source;
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
        (raw) => ApiImage.listFrom(raw),
      );
      if (env.isSuccess) {
        final picked = _pick(env.data ?? const []);
        if (picked != null) {
          return _store(song.id, ResolvedStream(picked));
        }
      }
    }

    throw StreamResolveException(
        'No playable stream variants for "${song.title}" (${song.id}).');
  }

  ResolvedStream _store(String songId, ResolvedStream stream) {
    _cache[songId] = _CacheEntry(
      stream: stream,
      expiry: UrlRefreshScheduler.parseExpiry(stream.url),
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
      // Default + 'high': highest available variant.
      StreamQuality.auto || StreamQuality.high => sorted.first.link,
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
  ResolvedStream(this.url, {this.enriched});
  final String url;
  final FeedItem? enriched;
}

/// Cache entry — the resolved stream + the parsed signed-URL expiry (if
/// any). Stored only inside [StreamResolver]; callers see [ResolvedStream].
class _CacheEntry {
  _CacheEntry({required this.stream, required this.expiry});
  final ResolvedStream stream;
  final DateTime? expiry;
}
