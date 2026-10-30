// One on-device track, as a row.
//
// Shared by the device library and its album/artist screens rather than being
// private to either, so the two never drift apart visually. The app's list
// row: 48 art on the row radius, a one-line title and subtitle, the duration
// in tabular figures on the right, and the accent plus bars on the song that
// is playing.

import 'package:flutter/material.dart';

import '../api/dto.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/motion.dart';
import '../widgets/playing_bars.dart';

class LocalTrackRow extends StatelessWidget {
  const LocalTrackRow({
    super.key,
    required this.song,
    required this.colors,
    required this.onTap,
    this.trailing,
    this.playing = false,
    this.animate = false,
  });

  final FeedItem song;
  final SunohColors colors;
  final VoidCallback onTap;
  final Widget? trailing;

  /// This is the song loaded in the player.
  final bool playing;

  /// Whether the bars move — they hold still while playback is paused.
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final subtitle = song.displaySubtitle;
    return Pressable(
      scale: 0.99,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // `imageUrl` is a cached JPEG path for local tracks; SunohArt
            // renders a path with Image.file and falls back to its generated
            // cover when the album had no art.
            SunohArt(
              id: song.id,
              size: 48,
              radius: SunohRadius.row,
              imageUrl: song.artwork,
              shadow: false,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SunohType.sans(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: playing ? c.accent : c.fg,
                            height: 1.3,
                          ),
                        ),
                      ),
                      if (playing) ...[
                        const SizedBox(width: 8),
                        // 13: three 3-wide bars and two 2 gaps.
                        PlayingBars(
                          color: c.accent,
                          size: 13,
                          animate: animate,
                        ),
                      ],
                    ],
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SunohType.sans(fontSize: 13, color: c.fgDim),
                    ),
                  ],
                ],
              ),
            ),
            ?trailing,
            if (trailing == null && song.duration != null)
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(
                  _mmss(song.duration!),
                  style: SunohType.mono(fontSize: 12.5, color: c.fgMute),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _mmss(String seconds) {
    final total = int.tryParse(seconds) ?? 0;
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
