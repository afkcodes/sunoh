// Mid-track URL refresh for signed streaming URLs.
//
// Gaana and Saavn return signed URLs (the playlist + segment URLs are token-
// stamped with an expiry). If a track is mid-playback when the URL goes
// stale, mpv stalls — segment fetches start failing and the playback either
// freezes or reports an EOF (per mpv's docs, network drops mid-stream are
// reported as `MpvEndFileReason.eof`, not `error`).
//
// Strategy (two layers, defense-in-depth):
//
//   1. **Pre-emptive timer.** When the on_load hook resolves a URL, we parse
//      the expiry from the query string and schedule a refresh ~5 min
//      before it. When the timer fires we atomically swap the playlist
//      entry via `Player.replace(currentIndex, …)` — that re-triggers the
//      on_load hook for a fresh resolution, preserving the queue and
//      restoring the playback position via `file-local-options/start`.
//
//   2. **Reactive fallback.** Caller subscribes to `Player.stream.endFile`
//      and treats `eof` with `position < duration - 3s` as a premature
//      drop. Same refresh action — caller forwards it to us so the same
//      retry/throttle logic applies.
//
// Why this is better than the RN port's `URLRefreshLogic.ts`:
//   - Per-track schedule keyed by song id; cancellation on track change
//     prevents a stale refresh from firing into a different playing track.
//   - Defers when paused. RN refreshed unconditionally which caused
//     surprise audio when the user had stepped away.
//   - Combines pre-emptive timing with reactive EOF detection. RN had only
//     pre-emptive on TRACK_CHANGED, which missed mid-track expiries on
//     long sessions with auto-advance.
//   - Throttle window prevents tight loops if the API keeps issuing
//     short-lived URLs that expire before our safety margin.

import 'dart:async';
import 'package:flutter/foundation.dart';

class UrlRefreshScheduler {
  UrlRefreshScheduler({required this.refresh});

  /// Asynchronously performs the refresh — typically re-resolve URL via
  /// the API and swap the current playlist entry. Caller owns the actual
  /// mpv plumbing; this class only schedules.
  final Future<void> Function() refresh;

  Timer? _timer;
  String? _scheduledForSongId;
  DateTime? _scheduledFor;
  DateTime? _lastRefreshAt;

  /// Minimum gap between two refresh fires. Prevents tight loops if the
  /// API issues URLs that are already past safety margin.
  static const _throttle = Duration(minutes: 2);

  /// Returns true if a refresh fires *now* would be throttled.
  bool get throttled {
    final last = _lastRefreshAt;
    if (last == null) return false;
    return DateTime.now().difference(last) < _throttle;
  }

  /// What we last scheduled for — exposed for diagnostics.
  String? get scheduledForSongId => _scheduledForSongId;
  DateTime? get scheduledFor => _scheduledFor;

  /// Schedule a pre-emptive refresh for the given track. Call from the
  /// `on_load` hook after resolving a real URL.
  ///
  /// - [safetyMargin] is how long before parsed expiry we fire. Default 5 min.
  /// - [fallbackTtl] is used when the URL's expiry can't be parsed.
  ///   Default 45 min — most signed URLs live 1 hour, this leaves headroom.
  void schedule({
    required String songId,
    required String resolvedUrl,
    Duration safetyMargin = const Duration(minutes: 5),
    Duration fallbackTtl = const Duration(minutes: 45),
  }) {
    _timer?.cancel();
    _timer = null;

    final expiry = parseExpiry(resolvedUrl);
    final now = DateTime.now();
    final refreshAt = expiry != null
        ? expiry.subtract(safetyMargin)
        : now.add(fallbackTtl);
    final delay = refreshAt.difference(now);

    if (delay.inSeconds < 30) {
      // URL was issued past the safety margin (or there's no expiry param
      // and our fallback is somehow tiny). Defer 30s so we don't tight-loop;
      // the reactive fallback on premature EOF will still catch a stall.
      _scheduledForSongId = songId;
      _scheduledFor = now.add(const Duration(seconds: 30));
      _timer = Timer(const Duration(seconds: 30), _fire);
      debugPrint('[url-refresh] $songId past safety; deferred 30s');
      return;
    }

    _scheduledForSongId = songId;
    _scheduledFor = refreshAt;
    _timer = Timer(delay, _fire);
    debugPrint('[url-refresh] $songId scheduled in ${delay.inMinutes} min '
        '(expiry=${expiry?.toIso8601String() ?? 'unparsed'})');
  }

  /// Cancel any pending refresh. Call when the playing track changes so
  /// the previous track's timer doesn't fire into a different now-playing
  /// track. Also call on dispose.
  void cancel() {
    if (_timer != null) {
      debugPrint('[url-refresh] cancel ${_scheduledForSongId ?? '?'}');
    }
    _timer?.cancel();
    _timer = null;
    _scheduledForSongId = null;
    _scheduledFor = null;
  }

  void dispose() => cancel();

  /// Manually fire a refresh — used by the reactive EOF fallback path.
  /// Honors the throttle window so a flapping stream doesn't spam.
  Future<void> triggerRefresh({required String reason}) async {
    if (throttled) {
      debugPrint('[url-refresh] throttled ($reason); skip');
      return;
    }
    _lastRefreshAt = DateTime.now();
    debugPrint('[url-refresh] firing ($reason)');
    try {
      await refresh();
    } catch (e) {
      debugPrint('[url-refresh] refresh failed: $e');
    }
  }

  void _fire() {
    _timer = null;
    _scheduledFor = null;
    _scheduledForSongId = null;
    unawaited(triggerRefresh(reason: 'pre-emptive timer'));
  }

  /// Best-effort parser for signed-URL expiry. Tries the common query-string
  /// conventions used by Gaana/Saavn/S3/CDNs. Returns null if no expiry
  /// parameter is present or parseable.
  @visibleForTesting
  static DateTime? parseExpiry(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    // Walk every query param — gaana sometimes nests the token in the path
    // segments but the readable expiry is consistently in the query.
    for (final key in const ['expires', 'expire', 'e', 'oe', 'exp', 'ttl']) {
      final raw = uri.queryParameters[key];
      if (raw == null || raw.isEmpty) continue;
      final n = int.tryParse(raw);
      if (n == null) continue;
      // Heuristic: epoch millis (>= 1e12), epoch secs (>= 1e9), or a
      // delta in seconds. Anything else we don't trust.
      if (n >= 1000000000000) {
        return DateTime.fromMillisecondsSinceEpoch(n);
      }
      if (n >= 1000000000) {
        return DateTime.fromMillisecondsSinceEpoch(n * 1000);
      }
      if (n > 0 && n < 86400 * 7) {
        // Looks like a TTL in seconds (within a week).
        return DateTime.now().add(Duration(seconds: n));
      }
    }
    return null;
  }
}
