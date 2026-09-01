// One on-device track, as a row.
//
// Shared by the device library and its album/artist screens rather than being
// private to either, so the two never drift apart visually.

import 'package:flutter/material.dart';

import '../api/dto.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';

class LocalTrackRow extends StatelessWidget {
  const LocalTrackRow({
    super.key,
    required this.song,
    required this.colors,
    required this.onTap,
    this.trailing,
  });

  final FeedItem song;
  final SunohColors colors;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final subtitle = song.displaySubtitle;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
        child: Row(
          children: [
            // `imageUrl` is a cached JPEG path for local tracks; SunohArt
            // renders a path with Image.file and falls back to its generated
            // cover when the album had no art.
            SunohArt(
              id: song.id,
              size: 44,
              radius: 6,
              imageUrl: song.artwork,
              shadow: false,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SunohType.sans(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: colors.fg,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SunohType.sans(fontSize: 12, color: colors.fgMute),
                    ),
                  ],
                ],
              ),
            ),
            ?trailing,
            if (trailing == null && song.duration != null)
              Text(
                _mmss(song.duration!),
                style: SunohType.mono(fontSize: 11, color: colors.fgMute),
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
