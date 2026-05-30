// Mini player — transparent content for the docked bottom bar (the bar
// itself supplies the frosted background).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../cast/cast_button.dart';
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
                // Cast button — small enough to share the row with the
                // play/pause cluster but legible. Flips glyph + color
                // when a session is live (watches AppState.isCasting).
                const CastButton(size: 20, width: 36, height: 36),
                const SizedBox(width: 8),
                // Play/pause gets a subtle accent-tinted circular wash so it
                // reads as the primary action. Alpha 0.20 over the frosted
                // bottom bar lands near the surface color but with palette
                // identity — bright enough to spot, soft enough to not
                // dominate.
                _miniBtn(
                    s.isPlaying
                        ? PhosphorIconsFill.pause
                        : PhosphorIconsFill.play,
                    c.fg,
                    22,
                    s.playPause,
                    background: accent.withValues(alpha: 0.20)),
                // Skip-next is meaningless for live streams (single-entry
                // playlist; there's no "next" track). Hide it.
                if (!s.isLive) ...[
                  const SizedBox(width: 4),
                  _miniBtn(
                      PhosphorIconsFill.skipForward, c.fg, 22, s.next),
                ],
              ],
            ),
          ),
          // Full-width seek line for finite tracks. Live streams have
          // no duration/position, so the scrubber would just render
          // 0:00 / 0:00 — replace it with a flat live indicator strip.
          if (s.isLive)
            _LiveIndicator(accent: accent, fg: c.fg)
          else
            ValueListenableBuilder<int>(
              valueListenable: s.positionTick,
              builder: (_, pos, _) => Scrubber(
                value: pos,
                max: s.currentDurationSec,
                accent: accent,
                fg: c.fg,
                compact: true,
              ),
            ),
        ],
      ),
    );
  }

  Widget _miniBtn(
    IconData icon,
    Color color,
    double size,
    VoidCallback onTap, {
    Color? background,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: background == null
            ? null
            : BoxDecoration(color: background, shape: BoxShape.circle),
        child: Icon(icon, size: size, color: color),
      ),
    );
  }
}

/// Thin coloured strip with a "● LIVE" pill, used in place of the
/// position scrubber while a live stream is playing. Same height as
/// the compact Scrubber so the layout doesn't jump on mode transitions.
class _LiveIndicator extends StatelessWidget {
  const _LiveIndicator({required this.accent, required this.fg});
  final Color accent;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            'LIVE',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}
