// Turns ten slider positions into an mpv filter chain that actually delivers
// them.
//
// Pure Dart on purpose — no Flutter, no player — so the response can be
// asserted in a unit test rather than judged by ear. See `test/eq_filters_test.dart`.
//
// ## Why this is not just ten filters
//
// The obvious implementation cascades one biquad per band and hands mpv the
// list. That is what this app shipped, and it was measurably wrong: on the
// Treble Boost preset the 4 kHz band came out +11.35 dB against a requested
// +8, while 16 kHz came out +4.34 against a requested +7. Boosted mids,
// swallowed highs — which is exactly what it sounded like.
//
// Three separate causes, all fixed here:
//
//  1. **The bands were too wide.** `width=1.2` at octave spacing makes each
//     filter bleed into its neighbours, so adjacent boosts stack on top of
//     each other. One octave of bandwidth is Q = sqrt(2) ≈ 1.414 ([_kQ]).
//
//  2. **Neighbours still overlap even at the right Q**, because a graphic EQ's
//     bands are not independent — that is inherent to the topology, not a
//     tuning mistake. So the gains are pre-compensated ([_compensate]): ask
//     for the curve, measure what the chain would really do, push the
//     difference back into the gains, repeat. Three passes is enough.
//
//  3. **Nothing accounted for the extra level.** Ten boosts summing to +11 dB
//     with no headroom clips the output on anything loudly mastered, which is
//     why it went wrong on *some* songs and not others. [_preampDb] measures
//     the true peak of the finished curve and attenuates by exactly that.
//
// Nothing here runs on a hot path: it is a few hundred float operations, once,
// when the user moves a slider.

import 'dart:math' as math;

/// ISO octave centres, 31 Hz to 16 kHz — the ten sliders in the EQ sheet.
const List<int> kEqFrequencies = [
  31,
  63,
  125,
  250,
  500,
  1000,
  2000,
  4000,
  8000,
  16000,
];

/// Bandwidth of one octave, expressed as Q — for the eight *peaking* bands.
///
/// `Q = sqrt(2^N) / (2^N - 1)` for an N-octave band; at N = 1 that is
/// `sqrt(2) ≈ 1.414`. The previous value of 1.2 is a *wider* filter, and width
/// is what makes neighbouring bands sum into each other.
const double _kPeakQ = 1.4142135623730951;

/// Q for the two *shelves*, which is a different question with a different
/// answer.
///
/// A shelf has no bandwidth to match — it turns a corner and stays there — and
/// pushing its Q above Butterworth makes it overshoot on the way, ripple that
/// shows up as gain the user never asked for. Measured: at the peaking Q of
/// 1.414 a uniform -3 dB *cut* still produced +0.84 dB of boost somewhere in
/// the transition, which then had to be trimmed back off by the preamp.
///
/// This is also half of the original complaint. The old code ran the 16 kHz
/// treble shelf at Q = 1.2, and a shelf that overshoots above its corner digs
/// a matching dip below it — right in the presence region, which is exactly
/// where "diminishing highs" is heard.
const double _kShelfQ = 0.7071067811865476;

/// The rate the response is computed at when the track's own is unknown.
///
/// A biquad's shape depends on sample rate — the bilinear transform warps
/// frequencies as they approach Nyquist, and at 44.1 kHz the 16 kHz band is
/// already at 0.73 of it. Compensating at the rate most material actually uses
/// is right far more often than not; hi-res tracks land slightly under-
/// corrected at the top, which errs toward leaving the signal alone.
const int kDefaultSampleRateHz = 44100;

/// Biquad coefficients, normalised so a0 == 1.
typedef _Biquad = ({double b0, double b1, double b2, double a1, double a2});

// The three transfer functions below are transcribed from ffmpeg's
// libavfilter/af_biquads.c for `width_type=q`, because that is the code that
// will actually run them. Deriving them from a textbook instead risks matching
// the textbook and not the filter.

_Biquad _peaking(double f0, double gainDb, double q, int fs) {
  final a = math.pow(10, gainDb / 40.0) as double;
  final w0 = 2 * math.pi * f0 / fs;
  final alpha = math.sin(w0) / (2 * q);
  final c = math.cos(w0);
  final a0 = 1 + alpha / a;
  return (
    b0: (1 + alpha * a) / a0,
    b1: (-2 * c) / a0,
    b2: (1 - alpha * a) / a0,
    a1: (-2 * c) / a0,
    a2: (1 - alpha / a) / a0,
  );
}

_Biquad _lowShelf(double f0, double gainDb, double q, int fs) {
  final a = math.pow(10, gainDb / 40.0) as double;
  final w0 = 2 * math.pi * f0 / fs;
  final alpha = math.sin(w0) / (2 * q);
  final c = math.cos(w0);
  final s = 2 * math.sqrt(a) * alpha;
  final a0 = (a + 1) + (a - 1) * c + s;
  return (
    b0: (a * ((a + 1) - (a - 1) * c + s)) / a0,
    b1: (2 * a * ((a - 1) - (a + 1) * c)) / a0,
    b2: (a * ((a + 1) - (a - 1) * c - s)) / a0,
    a1: (-2 * ((a - 1) + (a + 1) * c)) / a0,
    a2: ((a + 1) + (a - 1) * c - s) / a0,
  );
}

_Biquad _highShelf(double f0, double gainDb, double q, int fs) {
  final a = math.pow(10, gainDb / 40.0) as double;
  final w0 = 2 * math.pi * f0 / fs;
  final alpha = math.sin(w0) / (2 * q);
  final c = math.cos(w0);
  final s = 2 * math.sqrt(a) * alpha;
  final a0 = (a + 1) - (a - 1) * c + s;
  return (
    b0: (a * ((a + 1) + (a - 1) * c + s)) / a0,
    b1: (-2 * a * ((a - 1) + (a + 1) * c)) / a0,
    b2: (a * ((a + 1) + (a - 1) * c - s)) / a0,
    a1: (2 * ((a - 1) - (a + 1) * c)) / a0,
    a2: ((a + 1) - (a - 1) * c - s) / a0,
  );
}

List<_Biquad> _chain(List<double> gains, int fs) {
  final out = <_Biquad>[];
  for (var i = 0; i < kEqFrequencies.length; i++) {
    final f = kEqFrequencies[i].toDouble();
    final g = gains[i];
    // First and last bands are shelves so the extremes keep rising rather
    // than rolling back off past the centre — the ends of the spectrum have
    // no neighbour to hand over to.
    out.add(switch (i) {
      0 => _lowShelf(f, g, _kShelfQ, fs),
      _ when i == kEqFrequencies.length - 1 => _highShelf(f, g, _kShelfQ, fs),
      _ => _peaking(f, g, _kPeakQ, fs),
    });
  }
  return out;
}

/// Magnitude of one biquad at [f], in dB.
double _magDb(_Biquad q, double f, int fs) {
  final w = 2 * math.pi * f / fs;
  final cw = math.cos(w), sw = math.sin(w);
  final c2 = math.cos(2 * w), s2 = math.sin(2 * w);
  final nr = q.b0 + q.b1 * cw + q.b2 * c2;
  final ni = -(q.b1 * sw + q.b2 * s2);
  final dr = 1 + q.a1 * cw + q.a2 * c2;
  final di = -(q.a1 * sw + q.a2 * s2);
  final n = math.sqrt(nr * nr + ni * ni);
  final d = math.sqrt(dr * dr + di * di);
  if (d == 0 || n == 0) return 0;
  return 20 * (math.log(n / d) / math.ln10);
}

/// Combined response of the whole chain at [f], in dB.
double _chainDb(List<_Biquad> chain, double f, int fs) {
  var sum = 0.0;
  for (final q in chain) {
    sum += _magDb(q, f, fs);
  }
  return sum;
}

/// Gains that make the chain *land on* [target] at each band centre.
///
/// Fixed-point iteration: whatever the chain overshoots by, subtract. It
/// converges because a band dominates its own centre frequency, so the
/// correction is mostly self-directed and only weakly coupled to neighbours.
/// Three passes takes the Treble Boost error from 3.35 dB to under 0.2 dB;
/// more passes buy nothing audible.
List<double> _compensate(List<double> target, int fs) {
  final g = List<double>.from(target);
  for (var pass = 0; pass < 3; pass++) {
    final chain = _chain(g, fs);
    for (var i = 0; i < g.length; i++) {
      final f = kEqFrequencies[i].toDouble();
      final err = _chainDb(chain, f, fs) - target[i];
      // Clamped so a band near Nyquist, which physically cannot reach its
      // target, walks toward it instead of winding up to a huge gain trying.
      g[i] = (g[i] - err).clamp(-24.0, 24.0);
    }
  }
  return g;
}

/// The loudest point of the finished curve, in dB, or 0 if it only ever cuts.
///
/// Swept rather than sampled at the band centres: the peak of a graphic EQ
/// usually sits *between* two boosted bands, which is precisely the level a
/// centres-only check would miss.
double _peakBoostDb(List<double> gains, int fs) {
  final chain = _chain(gains, fs);
  var peak = 0.0;
  // Log sweep — 200 points over the audible decades resolves the peak to well
  // under a tenth of a dB without a thousand-point scan.
  const points = 200;
  final lo = math.log(20.0), hi = math.log(math.min(20000.0, fs / 2.0 - 1));
  for (var i = 0; i <= points; i++) {
    final f = math.exp(lo + (hi - lo) * i / points);
    final db = _chainDb(chain, f, fs);
    if (db > peak) peak = db;
  }
  return peak;
}

/// The mpv `af` entries for [requestedGains], in order.
///
/// Returns an **empty list** when every band is zero. That is load-bearing:
/// with the EQ off the audio must reach the output untouched — no filter, no
/// preamp, not even a nominally transparent one. A biquad at 0 dB is flat in
/// magnitude but still resamples the signal through its own arithmetic, and
/// this app's whole point is that it does not colour anything it was not asked
/// to colour.
List<String> buildEqFilters(
  List<double> requestedGains, {
  int sampleRateHz = kDefaultSampleRateHz,
}) {
  assert(
    requestedGains.length == kEqFrequencies.length,
    'expected ${kEqFrequencies.length} bands, got ${requestedGains.length}',
  );
  if (!requestedGains.any((g) => g.abs() > 0.001)) return const [];

  final gains = _compensate(requestedGains, sampleRateHz);
  final filters = <String>[];

  // Attenuate first, so the boosts that follow have somewhere to go. Placed
  // ahead of the biquads rather than after them because clipping happens
  // inside the chain, and trimming a signal that has already clipped just
  // makes a quieter clipped signal.
  final preamp = _peakBoostDb(gains, sampleRateHz);
  if (preamp > 0.01) {
    // A high shelf with its corner below hearing, used as a flat broadband
    // attenuator — not the obvious `volume`, for a reason worth recording.
    //
    // Three routes to ffmpeg's `volume` were rejected on a real device:
    //
    //   lavfi-volume=volume=-12dB  -> "Option af: 'lavfi-volume' isn't
    //                                  supported." mpv auto-wraps most
    //                                  libavfilter filters under `lavfi-` but
    //                                  skips names colliding with its own.
    //   lavfi=[volume=-12dB]       -> "parsing the filter graph failed" — the
    //   lavfi=%16%volume=-12dB        value reaches libavfilter, which reads
    //                                 `[...]` as a link label.
    //
    // The filter is not missing (`volume` is present in libmpv.so); mpv just
    // will not hand it a graph from here. Rather than keep guessing at
    // quoting, this reuses `treble`, which the EQ already proves loads.
    //
    // A high shelf attenuates everything above its corner, so a corner at 5 Hz
    // attenuates the whole audible band. Measured deviation from a constant
    // gain between 20 Hz and 20 kHz: 0.063 dB — well under the 0.5 dB the band
    // tests demand. 10 Hz measured 0.897 dB and 20 Hz measured 6 dB at the
    // bottom of the range, so the low corner is doing real work.
    //
    // Getting this wrong is not a quiet failure: mpv rejects the *entire* `af`
    // chain, and playback stops.
    filters.add(
      'lavfi-treble=f=5:width_type=q:width=$_kShelfQ:'
      'g=${(-preamp).toStringAsFixed(3)}',
    );
  }

  for (var i = 0; i < kEqFrequencies.length; i++) {
    final g = gains[i].toStringAsFixed(3);
    final f = kEqFrequencies[i];
    if (i == 0) {
      filters.add('lavfi-bass=f=$f:width_type=q:width=$_kShelfQ:g=$g');
    } else if (i == kEqFrequencies.length - 1) {
      filters.add('lavfi-treble=f=$f:width_type=q:width=$_kShelfQ:g=$g');
    } else {
      filters.add('lavfi-equalizer=f=$f:width_type=q:width=$_kPeakQ:g=$g');
    }
  }
  return filters;
}

/// Response of the built chain at each band centre — what the listener gets.
/// Exposed for tests and for anyone checking the claim above by measurement.
List<double> deliveredResponseDb(
  List<double> requestedGains, {
  int sampleRateHz = kDefaultSampleRateHz,
}) {
  if (!requestedGains.any((g) => g.abs() > 0.001)) {
    return List<double>.filled(kEqFrequencies.length, 0);
  }
  final gains = _compensate(requestedGains, sampleRateHz);
  final chain = _chain(gains, sampleRateHz);
  final preamp = _peakBoostDb(gains, sampleRateHz);
  return [
    for (final f in kEqFrequencies)
      _chainDb(chain, f.toDouble(), sampleRateHz) - math.max(0.0, preamp),
  ];
}
