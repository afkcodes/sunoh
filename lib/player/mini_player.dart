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
                      // Title row — live streams get a pulsing red dot
                      // tucked to the left of the title (instead of a
                      // pill + label). Quieter chrome but still reads
                      // as "this is on-air right now".
                      Row(
                        children: [
                          if (s.isLive) ...[
                            const _PingingDot(),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: Text(
                              // Live: prefer the ICY now-playing track,
                              // fall back to the station name. Non-live:
                              // always the track title.
                              s.isLive
                                  ? (s.icyTitle ?? track.title)
                                  : track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: SunohType.sans(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w500,
                                  color: c.fg),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        // Secondary line: station name when live (so the
                        // user always knows the source even when ICY is
                        // the big slot); otherwise the artist.
                        s.isLive ? track.title : track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SunohType.sans(
                            fontSize: 11.5, color: c.fgMute),
                      ),
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
                    // Live streams don't pause meaningfully (buffer
                    // drains; resume jumps to the live edge). The
                    // user-facing semantic is "stop", so swap the
                    // icon — the underlying action stays s.playPause
                    // which mpv handles either way.
                    s.isPlaying
                        ? (s.isLive
                            ? PhosphorIconsFill.stop
                            : PhosphorIconsFill.pause)
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
          // Scrubber for finite tracks only. Live streams put the LIVE
          // chip + ICY title inline in the row above and drop this
          // strip entirely so the mini player doesn't have a useless
          // 0:00/0:00 progress bar.
          if (!s.isLive)
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

/// Small pulsing red dot — radio "on-air" indicator. Always red
/// regardless of the user's accent so it reads universally as a
/// broadcast signal (same convention as TV "REC" lights). Animates a
/// gentle scale + opacity bounce to suggest a heartbeat without
/// becoming distracting.
class _PingingDot extends StatefulWidget {
  const _PingingDot();
  @override
  State<_PingingDot> createState() => _PingingDotState();
}

class _PingingDotState extends State<_PingingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const dotColor = Color(0xFFE05656);
    return SizedBox(
      width: 10,
      height: 10,
      child: AnimatedBuilder(
        animation: _ctl,
        builder: (_, _) {
          // Halo pulses from 0 → ~2.4× the dot diameter while fading
          // out; the inner dot stays at constant size + opacity so the
          // identity reads even when the halo is at zero alpha.
          final t = _ctl.value;
          final haloScale = 1.0 + t * 1.4;
          final haloAlpha = (1.0 - t) * 0.55;
          return Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: haloScale,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dotColor.withValues(alpha: haloAlpha),
                  ),
                ),
              ),
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: dotColor,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
