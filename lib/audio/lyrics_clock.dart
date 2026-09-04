// A millisecond playback clock, for the karaoke sweep only.
//
// `AppState.position` is a whole number of seconds and ticks once a second.
// That is deliberate and it stays that way — it is what keeps a 1 Hz tick from
// rebuilding every screen watching playback. It is also useless for word
// timing: a syllable lasts about 150 ms, so a clock that moves once a second
// would step the highlight through six words at once and then sit still.
//
// mpv's own position is exact but arrives when it arrives. So this runs off
// the wall clock between reports and re-syncs whenever one lands, which is the
// same trick `audio_service` plays with `updatePosition`/`updateTime`.
//
// It is a [ValueNotifier], so the lyrics painter repaints from it directly
// without a widget rebuild — the same pattern as `AppState.positionTick`.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// How far the wall clock is allowed to run past the last report.
///
/// Reports stop arriving when playback stalls, and a projection with nothing
/// to correct it would sail on through a track that isn't playing. Comfortably
/// longer than the gap between two reports, short enough that a stall doesn't
/// carry the sweep to the end of the verse.
const int _kMaxProjectionMs = 2000;

/// How far back a report has to be before it is believed.
///
/// mpv states where playback *was* when it sent the report, so a value a few
/// hundred milliseconds behind the running estimate is normal and means
/// nothing has happened. Taking those literally walked the clock backwards
/// several times a second: a line the sweep had finished would fall back
/// inside its own last word, flash white, and fill again from grey. Anything
/// further back than this is a real move — a seek, or a stall that has just
/// let go — and only those are worth breaking the clock's monotonicity for.
///
/// Comfortably longer than the gap between two reports, so an ordinary late
/// one is never mistaken for a seek.
const int _kSeekToleranceMs = 1200;

class LyricsClock extends ValueNotifier<int> {
  LyricsClock({
    required TickerProvider vsync,
    required Stream<Duration> positions,
    required Duration Function() positionNow,
    required bool Function() isPlaying,
  }) : _positionNow = positionNow,
       _isPlaying = isPlaying,
       super(positionNow().inMilliseconds) {
    _reported = positionNow().inMilliseconds;
    _reportedAt = DateTime.now();
    _sub = positions.listen(_onReport);
    _ticker = vsync.createTicker(_onFrame)..start();
  }

  final Duration Function() _positionNow;
  final bool Function() _isPlaying;

  late final StreamSubscription<Duration> _sub;
  late final Ticker _ticker;

  /// The last position mpv actually stated, and when we heard it.
  int _reported = 0;
  DateTime _reportedAt = DateTime.now();

  /// Takes a report, unless believing it would run the clock backwards.
  ///
  /// A report is still the only way a seek, a stall or a track change reaches
  /// us, so a large step in either direction is always accepted. A small step
  /// back is not: see [_kSeekToleranceMs]. In that case the estimate is
  /// re-anchored to itself, which keeps the sweep moving forwards while still
  /// resetting the time base — so the projection is never more than one report
  /// old and cannot drift away on its own.
  void _onReport(Duration position) {
    final reported = position.inMilliseconds;
    final projected = _projected();
    final stepsBack = projected - reported;
    _reported = (stepsBack > 0 && stepsBack < _kSeekToleranceMs)
        ? projected
        : reported;
    _reportedAt = DateTime.now();
  }

  /// The running estimate: the last anchor plus the wall time since it.
  int _projected() {
    final elapsed = DateTime.now().difference(_reportedAt).inMilliseconds;
    return _reported +
        (elapsed > _kMaxProjectionMs ? _kMaxProjectionMs : elapsed);
  }

  void _onFrame(Duration _) {
    final estimate = _estimate();
    // A frame that lands on the same millisecond changes nothing, and
    // ValueNotifier already suppresses an identical value — but the sweep runs
    // at 60 Hz for the length of a song, so the comparison is worth stating.
    if (estimate != value) value = estimate;
  }

  int _estimate() {
    if (!_isPlaying()) {
      // Paused: nothing is moving, so the last stated position is exactly
      // right — and a scrub while paused tracks the sweep precisely.
      final now = _positionNow().inMilliseconds;
      _reported = now;
      _reportedAt = DateTime.now();
      return now;
    }
    // Pure projection from the last report. Deliberately *not* corrected
    // against mpv's live position: that value is fed from this same stream, so
    // between two reports it is exactly [_reported] — comparing the two would
    // find a "drift" equal to the time since the last report and drag the
    // sweep back to where it started, several times a second.
    return _projected();
  }

  @override
  void dispose() {
    _ticker.dispose();
    unawaited(_sub.cancel());
    super.dispose();
  }
}
