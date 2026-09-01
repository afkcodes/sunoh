// Design tokens for sunoh. — colors, accents, typography.

import 'dart:math' as math;

import 'package:flutter/material.dart';

enum Density { compact, regular, comfy }

/// Which palette to paint. `system` follows the OS setting.
enum SunohTheme { system, light, dark }

extension SunohThemeLabel on SunohTheme {
  String get label => switch (this) {
    SunohTheme.system => 'System',
    SunohTheme.light => 'Light',
    SunohTheme.dark => 'Dark',
  };
}

/// Multiplier applied to vertical paddings + inter-row gaps when rendering
/// density-aware widgets (track rows, home section gaps, settings rows).
/// Cap stays gentle so layout stability is preserved across modes — no text
/// resizing, no card-size changes, just breathing room.
extension DensityScale on Density {
  double get scale => switch (this) {
    Density.compact => 0.85,
    Density.regular => 1.0,
    Density.comfy => 1.18,
  };
}

/// Accent palette. First six are the muted "editorial" set from the original
/// design; the next six are vibrant/warm options for users who want more
/// saturated personality.
const List<Color> kAccentOptions = [
  // Muted set
  Color(0xFFD97757), // warm orange (default)
  Color(0xFFCAA66B), // brass / tan
  Color(0xFF7FB3D5), // steel blue
  Color(0xFFA78BD1), // soft violet
  Color(0xFF82B07B), // sage
  Color(0xFFFAFAFA), // ivory
  // Vibrant / saturated set
  Color(0xFFFF4D4D), // signal red
  Color(0xFFFF4F8B), // hot pink
  Color(0xFFFF8A2C), // bright orange
  Color(0xFFFFC23B), // amber / gold
  Color(0xFF8AE534), // lime
  Color(0xFF2FC4C0), // electric teal
];

/// The same twelve accents, darkened for use on a light background.
///
/// Indexes match [kAccentOptions] one-for-one, so a user's choice survives a
/// theme switch. These are not a stylistic variation: every accent in
/// [kAccentOptions] was chosen against near-black and fails WCAG AA on white —
/// eleven of the twelve fail even the relaxed 3:1 threshold for UI elements,
/// and ivory lands at 1.00, which is invisible. Each value here is its
/// counterpart darkened (hue and saturation held) until it clears 4.5:1
/// against [_lightBg], which `test/contrast_test.dart` verifies.
///
/// Ivory necessarily becomes a grey: there is no readable ivory on white.
const List<Color> kAccentOptionsLight = [
  // Muted set
  Color(0xFFBF502B), // warm orange (default)
  Color(0xFF8F6C33), // brass / tan
  Color(0xFF3678A4), // steel blue
  Color(0xFF855EBF), // soft violet
  Color(0xFF527D4B), // sage
  Color(0xFF737373), // ivory, as grey
  // Vibrant / saturated set
  Color(0xFFE80000), // signal red
  Color(0xFFE3004D), // hot pink
  Color(0xFFBC5400), // bright orange
  Color(0xFF9A6A00), // amber / gold
  Color(0xFF467F10), // lime
  Color(0xFF1F7F7D), // electric teal
];

/// The light-mode counterpart of [accent].
///
/// The twelve presets are a lookup, matched by position so a user's choice
/// survives a theme switch. Anything else — an accent extracted from album
/// art, which is most of the time when "tint from artwork" is on — is darkened
/// by the same rule the table was generated with. Passing those through
/// untouched left the play button a washed-out pastel on white, since artwork
/// accents are picked for vibrancy against a near-black page.
Color lightAccentFor(Color accent) {
  final i = kAccentOptions.indexOf(accent);
  if (i >= 0) return kAccentOptionsLight[i];
  return darkenForLight(accent);
}

/// Darken [color] until it clears [target] against [_lightBg], holding hue and
/// saturation so it still reads as the same colour.
///
/// Steps lightness down rather than solving directly: the relationship between
/// HSL lightness and relative luminance is not linear, and a hundred steps is
/// exact enough while staying obvious.
Color darkenForLight(Color color, {double target = 4.5}) {
  final hsl = HSLColor.fromColor(color);
  for (var step = 0; step <= 100; step++) {
    final candidate = hsl
        .withLightness((hsl.lightness * (100 - step) / 100).clamp(0.0, 1.0))
        .toColor();
    if (_contrast(candidate, _lightBg) >= target) return candidate;
  }
  return const Color(0xFF000000);
}

double _relativeLuminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double _contrast(Color a, Color b) {
  final la = _relativeLuminance(a);
  final lb = _relativeLuminance(b);
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

const Color _darkBg = Color(0xFF0B0B0D);
// Warm off-white rather than near-white. #FAFAF9 read as a bright screen
// rather than paper, which is the opposite of the editorial feel the dark
// palette has; this carries a little more warmth and drops the luminance
// enough to stop it glaring.
const Color _lightBg = Color(0xFFF6F4EF);
const Color _lightInk = Color(0xFF17171A);

/// Resolved palette. Dark was the only mode until light was added; both are
/// built here so a screen never has to ask which one it is in.
class SunohColors {
  const SunohColors({
    required this.bg,
    required this.bgSoft,
    required this.surface,
    required this.surface2,
    required this.line,
    required this.fg,
    required this.fgDim,
    required this.fgMute,
    required this.accent,
    required this.onAccent,
  });

  final Color bg;
  final Color bgSoft;
  final Color surface;
  final Color surface2;
  final Color line;
  final Color fg;
  final Color fgDim;
  final Color fgMute;
  final Color accent;

  /// Text and icons drawn ON [accent] — a filled play button, a primary pill.
  /// Black on the dark palette, white on the light one; picking the wrong one
  /// is the commonest way an accent becomes unreadable.
  final Color onAccent;

  /// Build the dark palette from the accent, optionally tinting the background
  /// toward an artwork accent (the "Tint from artwork" tweak).
  factory SunohColors.resolve({
    required Color accent,
    Color? tintAccent,
    Brightness brightness = Brightness.dark,
  }) => brightness == Brightness.light
      ? SunohColors._light(accent: accent, tintAccent: tintAccent)
      : SunohColors._dark(accent: accent, tintAccent: tintAccent);

  factory SunohColors._dark({required Color accent, Color? tintAccent}) {
    var bg = _darkBg;
    var bgSoft = const Color(0xFF101013);
    if (tintAccent != null) {
      bg = Color.lerp(_darkBg, tintAccent, 0.06)!;
      bgSoft = Color.lerp(_darkBg, tintAccent, 0.08)!;
    }
    return SunohColors(
      bg: bg,
      bgSoft: bgSoft,
      surface: Colors.white.withValues(alpha: 0.045),
      surface2: Colors.white.withValues(alpha: 0.07),
      line: Colors.white.withValues(alpha: 0.07),
      fg: const Color(0xFFFAFAFA),
      fgDim: const Color(0xFFFAFAFA).withValues(alpha: 0.72),
      // 0.45 measured 4.40:1 against the background — just under AA for normal
      // text, and this token carries subtitles, timestamps and eyebrows.
      // 0.46 clears it, at 4.52:1.
      fgMute: const Color(0xFFFAFAFA).withValues(alpha: 0.46),
      accent: accent,
      onAccent: Colors.black,
    );
  }

  factory SunohColors._light({required Color accent, Color? tintAccent}) {
    var bg = _lightBg;
    var bgSoft = const Color(0xFFEDEAE3);
    if (tintAccent != null) {
      // Half the dark tint. The same lerp reads far stronger against white,
      // and a tinted page behind dark text loses contrast quickly.
      bg = Color.lerp(_lightBg, tintAccent, 0.03)!;
      bgSoft = Color.lerp(_lightBg, tintAccent, 0.05)!;
    }
    return SunohColors(
      bg: bg,
      bgSoft: bgSoft,
      surface: _lightInk.withValues(alpha: 0.04),
      surface2: _lightInk.withValues(alpha: 0.07),
      // Heavier than dark's 0.07: an equally faint line simply disappears
      // against white.
      line: _lightInk.withValues(alpha: 0.12),
      fg: _lightInk,
      fgDim: _lightInk.withValues(alpha: 0.72),
      // 0.60 clears 4.5:1 against `bg` but only reaches 4.49 against
      // `bgSoft`, which is where sheets and cards sit — so it is tuned to the
      // darker of the two surfaces it actually lands on, not the lighter.
      fgMute: _lightInk.withValues(alpha: 0.63),
      accent: lightAccentFor(accent),
      // The light accents are dark enough that white sits on them at 4.5:1;
      // black would not.
      onAccent: Colors.white,
    );
  }
}

/// The font families, centralized so the choice is a one-line swap while type
/// isn't finalized. Shipped as bundled assets (see pubspec.yaml) — no runtime
/// fetch. A modern music-app voice: one clean grotesque + a mono data accent
/// (no editorial serif).
///   - [heading]: titles / large display text (heavier weights, no italic)
///   - [sans]:    UI / body text
///   - [mono]:    small data labels, eyebrows, timestamps
class SunohFonts {
  static const String heading = 'Gilroy';
  static const String sans = 'Gilroy';
  // Small tracked/uppercase data labels — also Gilroy now (no separate mono).
  static const String mono = 'Gilroy';
}

/// Typography helpers — Gilroy throughout. `mono` keeps its name for small
/// tracked label styles (eyebrows, timestamps) but renders in Gilroy too.
class SunohType {
  const SunohType._();

  /// Display / heading text — clean grotesque, semibold by default.
  static TextStyle heading({
    double? fontSize,
    FontWeight fontWeight = FontWeight.w600,
    Color? color,
    double? height,
    double? letterSpacing,
  }) => TextStyle(
    fontFamily: SunohFonts.heading,
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    height: height,
    letterSpacing: letterSpacing,
  );

  static TextStyle sans({
    double? fontSize,
    FontWeight fontWeight = FontWeight.w400,
    Color? color,
    double? height,
    double? letterSpacing,
  }) => TextStyle(
    fontFamily: SunohFonts.sans,
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    height: height,
    letterSpacing: letterSpacing,
  );

  static TextStyle mono({
    double? fontSize,
    FontWeight fontWeight = FontWeight.w400,
    Color? color,
    double? height,
    double? letterSpacing,
  }) => TextStyle(
    fontFamily: SunohFonts.mono,
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    height: height,
    letterSpacing: letterSpacing,
  );
}
