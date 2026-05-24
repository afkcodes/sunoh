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
  });
  final Color dominant;
  final Color accent;
  final bool isDark;
}

final artPaletteProvider =
    FutureProvider.autoDispose.family<ArtPalette?, String>((ref, url) async {
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
  final accent = pg.vibrantColor?.color ??
      pg.lightVibrantColor?.color ??
      pg.mutedColor?.color ??
      dominant;

  // Cheap luminance-ish check (avoid going through HSL for speed).
  final luma = (0.299 * dominant.r + 0.587 * dominant.g + 0.114 * dominant.b);
  final isDark = luma < 0.5;

  // Keep warm for 30 min so re-opening the same screen is instant.
  final link = ref.keepAlive();
  Future.delayed(const Duration(minutes: 30), link.close);

  return ArtPalette(
    dominant: dominant,
    accent: accent,
    isDark: isDark,
  );
});
