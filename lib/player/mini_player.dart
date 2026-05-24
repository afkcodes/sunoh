// Mini player — transparent content for the docked bottom bar (the bar
// itself supplies the frosted background).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../providers/app_state_provider.dart';
import '../providers/palette_provider.dart';
import '../router/router.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import 'scrubber.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final track = s.current;

    // Match the expanded player: pull the live palette directly from
    // artPaletteProvider keyed by the current artwork URL. Without this
    // the mini player only sees the user's accent + AppState's cached
    // `_extractedAccent` and lags behind track changes when AppState's
    // notify lands before the palette extraction completes.
    final url = s.currentApiSong?.artwork ?? '';
    final palette = url.isEmpty
        ? null
        : ref.watch(artPaletteProvider(url)).value;
    final accent = palette?.accent ?? s.resolvedAccent;

    return GestureDetector(
      onTap: () => context.openPlayer(),
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                Hero(
                  tag: 'sunoh-player-art',
                  child: SunohArt(
                      id: track.id,
                      imageUrl: s.currentApiSong?.artwork,
                      size: 44,
                      radius: 9,
                      shadow: false),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SunohType.sans(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                              color: c.fg)),
                      Text(track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SunohType.sans(fontSize: 11.5, color: c.fgMute)),
                    ],
                  ),
                ),
                _miniBtn(
                    s.isPlaying
                        ? PhosphorIconsFill.pause
                        : PhosphorIconsFill.play,
                    c.fg, 24, s.playPause),
                _miniBtn(PhosphorIconsFill.skipForward, c.fg, 22, s.next),
              ],
            ),
          ),
          // Full-width seek line, sitting between the mini player and the nav.
          ValueListenableBuilder<int>(
            valueListenable: s.positionTick,
            builder: (_, pos, _) => Scrubber(
              value: pos,
              max: track.duration,
              accent: accent,
              fg: c.fg,
              compact: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniBtn(IconData icon, Color color, double size, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(width: 36, height: 36, child: Icon(icon, size: size, color: color)),
    );
  }
}
