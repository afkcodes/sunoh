// Riverpod provider for the AppState ChangeNotifier (player + tweaks).
// We keep AppState as a ChangeNotifier (no behavioural change) and surface it
// through Riverpod so we run a single state-management library.

import 'package:flutter_riverpod/legacy.dart';

import '../audio/audio_repo.dart';
import '../state/app_state.dart';
import 'palette_provider.dart';

final appStateProvider = ChangeNotifierProvider<AppState>((ref) {
  final repo = ref.watch(audioRepoProvider);
  return AppState(
    audioRepo: repo,
    // Pulls the real artwork palette so the tint-from-artwork toggle
    // actually reflects the cover, instead of the deterministic hash of
    // the song id. Cached behind artPaletteProvider's 30-min keepAlive.
    palettize: (url) async {
      if (url.isEmpty) return null;
      try {
        final palette = await ref.read(artPaletteProvider(url).future);
        return palette?.accent;
      } catch (_) {
        return null;
      }
    },
  );
});
