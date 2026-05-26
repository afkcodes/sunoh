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

  /// True when the scheduled refresh time has passed (or is within
  /// `withinWindow`) for [songId]. The handler calls this on `play()`
  /// (resume after pause) to decide whether to refresh inline before
  /// asking mpv to resume — otherwise mpv tries the stale URL, fails its
  /// 2× retry, and falls through to its own auto-advance which surfaces
  /// as the wrong song playing.
  ///
  /// Returns false when nothing is scheduled for the song (e.g. fresh
  /// load, no expiry parsed) — the caller treats that as "trust mpv".
  bool isPastSafetyFor(
    String songId, {
    Duration withinWindow = const Duration(seconds: 15),
  }) {
    if (_scheduledForSongId != songId) return false;
    final at = _scheduledFor;
    if (at == null) return false;
    return DateTime.now().isAfter(at.subtract(withinWindow));
  }

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
    Duration minLeadBeforeExpiry = const Duration(seconds: 25),
  }) {
    _timer?.cancel();
    _timer = null;

    final expiry = parseExpiry(resolvedUrl);
    final now = DateTime.now();
    final refreshAt = expiry != null
        ? expiry.subtract(safetyMargin)
        : now.add(fallbackTtl);
    final delay = refreshAt.difference(now);

    // Past-safety branch: URL was issued such that we're already inside
    // (or past) the normal 5-min safety window. The previous behaviour
    // was a flat 30 s defer, which under load (gaana refresh takes 2-5 s
    // to round-trip + mpv reopen) wasn't always enough — playback would
    // stall when the refresh finished after the URL had already expired.
    // New behaviour: schedule for `expiry - minLeadBeforeExpiry` (default
    // 25 s) so we always leave that much runway for the actual fetch.
    // Clamp to a minimum of 5 s from now so we never tight-loop.
    if (delay.inSeconds < 30) {
      Duration deferral;
      if (expiry != null) {
        final leadAt = expiry.subtract(minLeadBeforeExpiry);
        final leadDelay = leadAt.difference(now);
        deferral = leadDelay > const Duration(seconds: 5)
            ? leadDelay
            : const Duration(seconds: 5);
      } else {
        deferral = const Duration(seconds: 30);
      }
      _scheduledForSongId = songId;
      _scheduledFor = now.add(deferral);
      _timer = Timer(deferral, _fire);
      debugPrint('[url-refresh] $songId past safety; '
          'deferred ${deferral.inSeconds}s '
          '(expiry=${expiry?.toIso8601String() ?? 'unparsed'})');
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
  /// parameter is present or parseable. Also consumed by `StreamResolver`
  /// to TTL its in-memory cache (so the cache never serves an about-to-
  /// expire URL into the on_load hook).
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
