// Palette extracted from artwork — used to tint the immersive detail hero
// (backdrop + accent). Each result is keyed by image URL and kept warm via
// keepAlive so repeat opens of the same detail are instant. Falls back
// gracefully: callers should treat the AsyncValue as best-effort and use
// artAccent(id) as the placeholder accent while loading.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';

class ArtPalette {
  const ArtPalette({
    required this.dominant,
    required this.accent,
    required this.isDark,
    required this.brightness,
  });
  final Color dominant;
  final Color accent;
  final bool isDark;

  /// Roughly how bright the whole cover is, 0 (black) to 1 (white).
  ///
  /// Population-weighted across every swatch the generator found, not taken
  /// from [dominant]. A poster can have a dark dominant and still be mostly
  /// white — the swatch that wins on frequency is not the one that decides how
  /// much light comes off the screen — and the full-bleed player needs the
  /// second question answered, not the first.
  ///
  /// Continuous rather than a second [isDark] flag, because the thing reading
  /// it dims proportionally. A boolean would put a step in the middle of the
  /// range where covers cluster.
  final double brightness;
}

final artPaletteProvider = FutureProvider.autoDispose
    .family<ArtPalette?, String>((ref, url) async {
      if (url.isEmpty) return null;

      // Extract from a small variant — the source can be 500×500+, but palette
      // accuracy doesn't need that. Smaller = faster + lighter on memory.
      final image = ResizeImage(
        CachedNetworkImageProvider(url),
        width: 160,
        height: 160,
        allowUpscaling: false,
      );

      final pg = await PaletteGenerator.fromImageProvider(
        image,
        size: const Size(160, 160),
        maximumColorCount: 12,
      );

      final dominant = pg.dominantColor?.color;
      if (dominant == null) return null;

      // Prefer a more saturated accent if available; fall back to dominant.
      final accent =
          pg.vibrantColor?.color ??
          pg.lightVibrantColor?.color ??
          pg.mutedColor?.color ??
          dominant;

      // Cheap luminance-ish check (avoid going through HSL for speed).
      final luma = 0.299 * dominant.r + 0.587 * dominant.g + 0.114 * dominant.b;
      final isDark = luma < 0.5;

      // Rec. 709 coefficients here, not the 601 ones above: this feeds a
      // decision about perceived light rather than the existing dark/light
      // classification, and changing the older line would move a threshold
      // other screens are already tuned against.
      var weighted = 0.0;
      var population = 0;
      for (final swatch in pg.paletteColors) {
        final c = swatch.color;
        weighted +=
            (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) * swatch.population;
        population += swatch.population;
      }
      final brightness = population == 0 ? luma : weighted / population;

      // Keep warm for 30 min so re-opening the same screen is instant.
      final link = ref.keepAlive();
      Future.delayed(const Duration(minutes: 30), link.close);

      return ArtPalette(
        dominant: dominant,
        accent: accent,
        isDark: isDark,
        brightness: brightness,
      );
    });
