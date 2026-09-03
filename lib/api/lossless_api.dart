// Hi-res lossless stream lookup.
//
// sunoh-api can tell us whether a Saavn/Gaana track also exists in a lossless
// catalog and, if so, hand back a signed CDN URL. Two things about that URL
// shape the design here:
//
//   - It is served by the catalog's own CDN, not by sunoh-api, and it carries
//     its own signature so it needs no auth header. The phone streams it
//     directly; no audio passes through our server. It also answers Range
//     requests, so mpv seeks in it natively.
//   - It expires in about an hour, so it is never persisted — only held in
//     memory alongside its expiry, the same way the YouTube tier treats its
//     signed URLs.
//
// The lookup is best-effort by construction. Playback must never wait on it and
// must never fail because of it: every path returns null instead of throwing,
// and the request is bounded by a short timeout.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../audio/url_refresh.dart';
import 'dto.dart';

/// Where a track's hi-res lookup has got to.
enum LosslessLookup {
  /// Asking the catalog. Worth showing: a cold lookup can take a moment, and
  /// silence while it happens reads as the feature doing nothing.
  searching,

  /// The catalog had it, and the stream is hi-res.
  found,

  /// The catalog does not carry this recording, so playback fell back to the
  /// track's own source. Not an error — most catalogues are far smaller than
  /// the streaming ones — and the UI says so in those terms.
  unavailable,
}

/// A lookup's state, tagged with the song it belongs to.
///
/// Tagged because the resolver also runs ahead of playback for the *next*
/// track, and an untagged status would let that quietly relabel the song on
/// screen.
class LosslessStatus {
  const LosslessStatus(this.songId, this.state);
  final String songId;
  final LosslessLookup state;
}

/// A resolved lossless stream. [url] is playable directly by mpv.
class LosslessStream {
  const LosslessStream({
    required this.url,
    required this.expiresAt,
    this.bitDepth,
    this.sampleRate,
    this.sizeBytes,
  });

  final String url;
  final DateTime expiresAt;
  final int? bitDepth;
  final int? sampleRate;
  final int? sizeBytes;

  /// Human-readable badge for the player UI, e.g. "24-bit / 96 kHz".
  String? get label {
    if (bitDepth == null || sampleRate == null) return null;
    final khz = (sampleRate! / 1000).toStringAsFixed(1).replaceAll('.0', '');
    return '$bitDepth-bit / $khz kHz';
  }
}

class LosslessApi {
  LosslessApi(this._dio);

  final Dio _dio;

  /// Tracks we have already asked about and been told "no".
  ///
  /// Without this, every play of a track the catalog does not carry would spend
  /// the full timeout below before falling through to the lossy tier. The
  /// server caches misses too, but this saves the round-trip entirely. Cleared
  /// on app restart, which is the right cadence: catalog additions are rare and
  /// a restart is a cheap way to pick them up.
  final Set<String> _unavailable = <String>{};

  /// Answers we already have, so a hit costs a round trip once per track
  /// rather than once per play.
  ///
  /// The negative set above spared the misses and left the hits paying full
  /// price — and a hit is the case that matters, since it is the one the user
  /// chose the setting for. Replaying a track, skipping back to it, the
  /// pre-resolve tick and the url-refresh path all reach this instead of the
  /// network.
  ///
  /// Held in memory only. The URLs are signed and expire within the hour, so
  /// persisting them would mean writing something guaranteed to be rubbish by
  /// the next session — the same reason the resolver does not persist its own.
  final Map<String, LosslessStream> _resolved = <String, LosslessStream>{};

  /// The most recent lookup, for the UI to reflect.
  ///
  /// A ValueNotifier rather than a stream: there is exactly one current value,
  /// every listener wants only the latest, and a widget can watch it without
  /// this file knowing anything about the widget.
  final ValueNotifier<LosslessStatus?> status = ValueNotifier<LosslessStatus?>(
    null,
  );

  void _publish(String songId, LosslessLookup state) =>
      status.value = LosslessStatus(songId, state);

  /// Dropped a little before the stated expiry, so a URL handed to mpv has
  /// time to be opened before the CDN stops honouring it.
  static const Duration _expiryMargin = Duration(minutes: 2);

  bool _usable(LosslessStream s) =>
      DateTime.now().isBefore(s.expiresAt.subtract(_expiryMargin));

  /// How long playback is willing to *wait* for a lossless answer.
  ///
  /// Three seconds: long enough for a cold match to land, chosen knowing the
  /// cost. A track the catalog has to search for now starts hi-res on the
  /// first play rather than the second, and the price is that a tap on play
  /// can sit for up to three seconds before any sound.
  ///
  /// That price is only ever paid once per track per session, because this is
  /// a waiting limit rather than a deadline for the request — see [_inFlight].
  /// Giving up on the wait while letting the request finish is what makes
  /// "cold now, hi-res next time" true; the budget decides how often "next
  /// time" is needed at all.
  static const Duration _budget = Duration(seconds: 3);

  /// Lookups still running, keyed by song id.
  ///
  /// An earlier version awaited the request with `.timeout()` and nothing
  /// else. That throws in the caller and abandons the response, so the answer
  /// was discarded — every play of the same track started another lookup,
  /// waited, timed out and threw the result away again. Measured on a device:
  /// every single track timing out, forever, while the comment above claimed
  /// they would be warm next time.
  ///
  /// Now the request owns itself: it populates the caches when it completes,
  /// whether or not anyone is still waiting. The second play is instant, and
  /// two plays at once share one request instead of racing.
  final Map<String, Future<LosslessStream?>> _inFlight =
      <String, Future<LosslessStream?>>{};

  /// The quality badge for a track resolved this session, or null when it was
  /// not resolved from the lossless catalog.
  ///
  /// Reads the cache the lookup already keeps rather than pushing state
  /// upward, so the UI can ask without api/ knowing anything about it.
  String? labelFor(String songId) {
    final s = _resolved[songId];
    return s != null && _usable(s) ? s.label : null;
  }

  /// Forget every remembered answer, e.g. after the user toggles the setting
  /// back on — the catalog may have gained a track since it last said no.
  void reset() {
    _unavailable.clear();
    _resolved.clear();
  }

  /// Start a lookup for a track nobody is playing yet.
  ///
  /// The reason skipping felt slow: mpv's own prefetch only opens the next
  /// track near the end of the current one, so pressing next early always met
  /// a cold catalog and waited out the full budget. Asking as soon as a track
  /// starts gives the lookup a whole song's worth of time to finish, and the
  /// skip then hits [_resolved] instead of the network.
  ///
  /// Fire and forget by design — nothing awaits it, failures are already
  /// swallowed, and a duplicate call joins the in-flight request rather than
  /// starting a second one.
  void warm(FeedItem song, {String quality = 'auto'}) {
    if (_unavailable.contains(song.id)) return;
    final known = _resolved[song.id];
    if (known != null && _usable(known)) return;
    if (_inFlight.containsKey(song.id)) return;
    _inFlight[song.id] = _fetch(song, quality);
  }

  /// True while a lookup for [songId] is still running, so the UI can keep
  /// saying "looking" rather than falling back to silence when the caller
  /// stopped waiting.
  bool isLooking(String songId) => _inFlight.containsKey(songId);

  /// Resolve a lossless stream for [song], or null when there isn't one.
  ///
  /// [quality] is the app's own preference string ('auto' / 'high' / 'data').
  /// The server maps it onto a catalog format: 'data' caps at CD rate, which is
  /// roughly 28 MB a track against roughly 96 MB at 24-bit/96 kHz.
  Future<LosslessStream?> resolve(
    FeedItem song, {
    String quality = 'auto',
  }) async {
    if (_unavailable.contains(song.id)) {
      _publish(song.id, LosslessLookup.unavailable);
      return null;
    }

    final known = _resolved[song.id];
    if (known != null) {
      if (_usable(known)) {
        _publish(song.id, LosslessLookup.found);
        return known;
      }
      // Expired rather than absent: the catalog still has it, the signature
      // has just aged out. Drop it and ask again.
      _resolved.remove(song.id);
    }

    _publish(song.id, LosslessLookup.searching);

    final request = _inFlight[song.id] ??= _fetch(song, quality);
    try {
      return await request.timeout(_budget);
    } on TimeoutException {
      // Not an answer. The request is still running and will fill the cache;
      // saying "no hi-res" here would be a guess, and the wrong one often
      // enough to make the tag worthless.
      debugPrint('[audio] lossless still looking for ${song.id}');
      return null;
    } catch (_) {
      return null;
    }
  }

  /// The request itself, which runs to completion regardless of who waits.
  Future<LosslessStream?> _fetch(FeedItem song, String quality) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/lossless/stream-url',
        data: <String, dynamic>{
          'quality': quality,
          // Only the fields the matcher reads. FeedItem has no toJson and
          // does not need one for this.
          'song': <String, dynamic>{
            'id': song.id,
            'title': song.title,
            'subtitle': song.subtitle,
            'duration': song.duration,
            'source': song.source,
          },
        },
      );

      final data = res.data?['data'];
      final url = data is Map ? data['url'] as String? : null;
      if (url == null || url.isEmpty) {
        _unavailable.add(song.id);
        _publish(song.id, LosslessLookup.unavailable);
        return null;
      }

      final stream = LosslessStream(
        url: url,
        // Same heuristic the signed-URL parser uses, rather than a second rule
        // for one concept: a bare fromMillisecondsSinceEpoch on a value the
        // server happened to send in seconds lands in 1970, which reads as
        // "already expired" and re-resolves on every single play.
        expiresAt:
            UrlRefreshScheduler.expiryFromNumber(data['expiresAt']) ??
            // No expiry stated: assume the short end so the refresh scheduler
            // re-resolves rather than trusting a URL that may already be dead.
            DateTime.now().add(const Duration(minutes: 30)),
        bitDepth: (data['bitDepth'] as num?)?.toInt(),
        sampleRate: (data['sampleRate'] as num?)?.toInt(),
        sizeBytes: (data['sizeBytes'] as num?)?.toInt(),
      );
      _resolved[song.id] = stream;
      _publish(song.id, LosslessLookup.found);
      return stream;
    } on DioException catch (e) {
      // 404 is the catalog saying it does not have this recording, which is a
      // real answer worth remembering. Anything else (503, offline) is
      // transient and must not poison the cache.
      if (e.response?.statusCode == 404) {
        _unavailable.add(song.id);
        _publish(song.id, LosslessLookup.unavailable);
      } else {
        debugPrint(
          '[audio] lossless lookup failed for ${song.id}: ${e.type.name}',
        );
      }
      return null;
    } catch (e) {
      debugPrint('[audio] lossless lookup error for ${song.id}: $e');
      return null;
    } finally {
      _inFlight.remove(song.id);
    }
  }
}
