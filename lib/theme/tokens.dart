// Design tokens for sunoh. — colors, accents, typography.

import 'package:flutter/material.dart';

enum Density { compact, regular, comfy }

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

/// Resolved palette — dark only (the app is dark by design; no light mode).
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

  /// Build the dark palette from the accent, optionally tinting the background
  /// toward an artwork accent (the "Tint from artwork" tweak).
  factory SunohColors.resolve({
    required Color accent,
    Color? tintAccent,
  }) {
    const base = Color(0xFF0B0B0D);
    var bg = base;
    var bgSoft = const Color(0xFF101013);
    if (tintAccent != null) {
      bg = Color.lerp(base, tintAccent, 0.06)!;
      bgSoft = Color.lerp(base, tintAccent, 0.08)!;
    }
    return SunohColors(
      bg: bg,
      bgSoft: bgSoft,
      surface: Colors.white.withValues(alpha: 0.045),
      surface2: Colors.white.withValues(alpha: 0.07),
      line: Colors.white.withValues(alpha: 0.07),
      fg: const Color(0xFFFAFAFA),
      fgDim: const Color(0xFFFAFAFA).withValues(alpha: 0.72),
      fgMute: const Color(0xFFFAFAFA).withValues(alpha: 0.45),
      accent: accent,
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
  }) =>
      TextStyle(
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
  }) =>
      TextStyle(
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
  }) =>
      TextStyle(
        fontFamily: SunohFonts.mono,
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
      );
}
