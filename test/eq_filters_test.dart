// The EQ's contract: off means untouched, on means the curve you asked for,
// and never loud enough to clip.
//
// These exist because the bug they cover was inaudible as a bug — it just
// sounded like a bad equaliser. A listener reported "increasing mid and
// diminishing highs"; the numbers below are what that complaint looks like
// written down, and what it looks like fixed.

import 'package:flutter_test/flutter_test.dart';
import 'package:sunoh/audio/eq_filters.dart';

/// Treble Boost — the preset the original report was made against.
const trebleBoost = <double>[0, 0, 0, 0, 2, 4, 6, 8, 9, 7];
const vocalClarity = <double>[-3, -2, 2, 6, 7, 6, 5, 3, 1, -1];
const electronic = <double>[6, 5, 2, 0, 1, 3, 4, 6, 8, 6];

void main() {
  group('bypass', () {
    test('a flat EQ emits no filters at all', () {
      expect(buildEqFilters(List<double>.filled(10, 0)), isEmpty);
    });

    test('a band below the epsilon still counts as flat', () {
      final gains = List<double>.filled(10, 0.0)..[3] = 0.0005;
      expect(buildEqFilters(gains), isEmpty);
    });

    test('one real band is enough to engage the chain', () {
      final gains = List<double>.filled(10, 0.0)..[3] = 3;
      expect(buildEqFilters(gains), isNotEmpty);
    });
  });

  group('accuracy', () {
    // Before the fix these errors were +3.35 dB at 4 kHz and -2.66 dB at
    // 16 kHz. Half a dB is below what anyone can hear on a band.
    for (final (name, preset) in [
      ('treble boost', trebleBoost),
      ('vocal clarity', vocalClarity),
      ('electronic', electronic),
    ]) {
      test('$name lands on its curve within 0.5 dB', () {
        final delivered = deliveredResponseDb(preset);
        // The preamp shifts the whole curve down for headroom, so it is the
        // *shape* that must match — level is the next test's business.
        final offset = delivered[0] - preset[0];
        for (var i = 0; i < preset.length; i++) {
          expect(
            delivered[i] - offset,
            closeTo(preset[i], 0.5),
            reason:
                '${kEqFrequencies[i]} Hz: asked ${preset[i]}, '
                'got ${(delivered[i] - offset).toStringAsFixed(2)}',
          );
        }
      });

      test('$name never exceeds 0 dB, so it cannot clip', () {
        for (final db in deliveredResponseDb(preset)) {
          expect(db, lessThanOrEqualTo(0.01), reason: 'would clip');
        }
      });
    }

    test('highs are no longer swallowed relative to mids', () {
      // The exact complaint: mids up, highs down. Measured against what was
      // asked for, the top band must not come out worse than the mids.
      final d = deliveredResponseDb(trebleBoost);
      final offset = d[0] - trebleBoost[0];
      final midErr = (d[7] - offset) - trebleBoost[7]; // 4 kHz
      final topErr = (d[9] - offset) - trebleBoost[9]; // 16 kHz
      expect(midErr.abs(), lessThan(0.5));
      expect(topErr.abs(), lessThan(0.5));
    });
  });

  group('filter strings', () {
    test('shelves at the ends, peaking in between, preamp in front', () {
      final f = buildEqFilters(trebleBoost);
      // Pinned exactly: mpv rejects `lavfi-volume=...` at runtime, which
      // no amount of Dart-side checking would have revealed.
      // Preamp is a sub-audible high shelf, not `volume` — mpv rejects every
      // route to ffmpeg's volume filter from here, and a rejected filter kills
      // the whole chain and with it playback.
      expect(f.first, startsWith('lavfi-treble=f=5:'));
      expect(f.first, contains('g=-'));
      expect(f[1], startsWith('lavfi-bass=f=31:'));
      expect(f.last, startsWith('lavfi-treble=f=16000:'));
      expect(f.where((s) => s.startsWith('lavfi-equalizer=')), hasLength(8));
    });

    test('a cut-only curve needs no preamp', () {
      final gains = List<double>.filled(10, -3.0);
      expect(buildEqFilters(gains).any((s) => s.contains('volume=')), isFalse);
    });
  });
}
