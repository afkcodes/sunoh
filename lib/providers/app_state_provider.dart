// Riverpod provider for the AppState ChangeNotifier (player + tweaks).
// We keep AppState as a ChangeNotifier (no behavioural change) and surface it
// through Riverpod so we run a single state-management library.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:palette_generator/palette_generator.dart';

import '../audio/audio_repo.dart';
import '../state/app_state.dart';
import 'api_providers.dart';

final appStateProvider = ChangeNotifierProvider<AppState>((ref) {
  final repo = ref.watch(audioRepoProvider);
  final api = ref.watch(sunohApiProvider);
  return AppState(
    audioRepo: repo,
    api: api,
    // Extract the artwork's vibrant accent for the tint-from-artwork
    // feature.
    //
    // Earlier this routed through `artPaletteProvider` via `ref.read(...
    // .future)`, but that family is `autoDispose` and AppState only calls
    // `read` (no watch), so the provider could dispose while the build's
    // await was in flight on fresh URLs the user hadn't already viewed —
    // the future never resolved and `_extractedAccent` stayed null. The
    // toggle worked only because previous visits had cached the palette
    // and `read` got the warmed result instantly.
    //
    // Direct extraction here removes that interaction entirely. The
    // typed Riverpod provider is still used by the detail hero + player
    // (they `ref.watch` it, which establishes a proper listener and
    // never trips the auto-dispose race).
    palettize: _extractAccent,
  );
});

Future<Color?> _extractAccent(String url) async {
  if (url.isEmpty) return null;
  try {
    // 160x160 is plenty for color clustering; saves memory + decode time
    // vs the full-resolution source.
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
    final accent = pg.vibrantColor?.color ??
        pg.lightVibrantColor?.color ??
        pg.mutedColor?.color ??
        pg.dominantColor?.color;
    debugPrint('[palette] direct-extracted '
        '${accent == null ? 'null' : '#${accent.toARGB32().toRadixString(16)}'} '
        'for $url');
    return accent;
  } catch (e) {
    debugPrint('[palette] direct extraction failed for $url: $e');
    return null;
  }
}
