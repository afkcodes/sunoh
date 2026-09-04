// WCAG contrast checks for the design tokens.
//
// Colour choices drift: an accent gets nudged for looks, an alpha gets dropped
// a notch to make something recede, and nobody notices that a subtitle stopped
// being readable — least of all on the device it was tuned on. These assert
// the ratios rather than the values, so the palette can keep changing as long
// as it stays legible.
//
// Thresholds are WCAG 2.1 AA: 4.5:1 for normal text, 3:1 for large text and
// non-text UI. Hairlines and surface fills are decorative and exempt, so they
// are not asserted here.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunoh/theme/tokens.dart';

/// Relative luminance, per WCAG 2.1.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

/// Flatten a translucent colour onto an opaque background.
///
/// Every muted token in this palette is an alpha over the page, so comparing
/// the raw colour would measure something that is never actually on screen.
Color _flatten(Color fg, Color bg) => Color.from(
  alpha: 1,
  red: fg.r * fg.a + bg.r * (1 - fg.a),
  green: fg.g * fg.a + bg.g * (1 - fg.a),
  blue: fg.b * fg.a + bg.b * (1 - fg.a),
);

double contrast(Color fg, Color bg) {
  final a = _luminance(_flatten(fg, bg));
  final b = _luminance(bg);
  final hi = math.max(a, b);
  final lo = math.min(a, b);
  return (hi + 0.05) / (lo + 0.05);
}

const _aaText = 4.5;
const _aaLarge = 3.0;

void main() {
  for (final brightness in [Brightness.dark, Brightness.light]) {
    final name = brightness == Brightness.dark ? 'dark' : 'light';

    group('$name palette', () {
      final c = SunohColors.resolve(
        accent: kAccentOptions.first,
        brightness: brightness,
      );

      test('body text clears AA', () {
        expect(contrast(c.fg, c.bg), greaterThanOrEqualTo(_aaText));
      });

      test('dimmed text clears AA', () {
        expect(contrast(c.fgDim, c.bg), greaterThanOrEqualTo(_aaText));
      });

      // The one that was actually failing: 0.45 alpha measured 4.40 on dark.
      // fgMute carries subtitles, timestamps and eyebrows — all normal text.
      test('muted text clears AA for normal text', () {
        expect(contrast(c.fgMute, c.bg), greaterThanOrEqualTo(_aaText));
      });

      test('muted text also clears AA against the soft background', () {
        // Sheets and cards sit on bgSoft, and it is not the same colour.
        expect(contrast(c.fgMute, c.bgSoft), greaterThanOrEqualTo(_aaText));
      });

      test('text on a surface fill stays readable', () {
        final surface = _flatten(c.surface, c.bg);
        expect(contrast(c.fg, surface), greaterThanOrEqualTo(_aaText));
        expect(contrast(c.fgMute, surface), greaterThanOrEqualTo(_aaLarge));
      });
    });

    group('$name accents', () {
      final options = brightness == Brightness.dark
          ? kAccentOptions
          : kAccentOptionsLight;

      for (var i = 0; i < options.length; i++) {
        final accent = options[i];

        test('accent $i is usable as a UI colour', () {
          // Accents underline the active tab, tint the scrubber and colour
          // icons — non-text UI, so 3:1.
          final c = SunohColors.resolve(accent: accent, brightness: brightness);
          expect(contrast(c.accent, c.bg), greaterThanOrEqualTo(_aaLarge));
        });

        test('accent $i carries its own label', () {
          // The filled play button draws onAccent on top of accent. Getting
          // this pair wrong is the commonest way an accent goes unreadable.
          final c = SunohColors.resolve(accent: accent, brightness: brightness);
          expect(contrast(c.onAccent, c.accent), greaterThanOrEqualTo(_aaText));
        });
      }
    });
  }

  test('every dark accent has a light counterpart', () {
    // They are matched by index so a user's choice survives a theme switch.
    expect(kAccentOptionsLight, hasLength(kAccentOptions.length));
    for (final accent in kAccentOptions) {
      expect(lightAccentFor(accent), isNot(accent));
    }
  });

  group('artwork-derived accents', () {
    // Not in the lookup table, and most of the time when "tint from artwork"
    // is on. An earlier version passed them through untouched, which left the
    // play button a washed-out pastel on white — artwork accents are picked
    // for vibrancy against a near-black page.
    const samples = [
      Color(0xFFFFE082), // pale yellow, the worst case on white
      Color(0xFF80DEEA), // pale cyan
      Color(0xFFFFFFFF), // white, from a bright cover
      Color(0xFFFF4081), // saturated pink
      Color(0xFF123456), // already dark — must be left alone
    ];

    for (final sample in samples) {
      test('${sample.toARGB32().toRadixString(16)} is legible on light', () {
        final c = SunohColors.resolve(
          accent: sample,
          brightness: Brightness.light,
        );
        expect(contrast(c.accent, c.bg), greaterThanOrEqualTo(_aaLarge));
        expect(contrast(c.onAccent, c.accent), greaterThanOrEqualTo(_aaText));
      });
    }

    test('an already-dark accent is not darkened further', () {
      const dark = Color(0xFF123456);
      expect(darkenForLight(dark), dark);
    });
  });
}
