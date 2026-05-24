// Full Recently Played list — opened from the Library tab. No hero (it's
// a transient list, not a curated playlist), just a header + scroll.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';

import '../api/dto.dart';
import '../overlays/track_menu_sheet.dart';
import '../providers/app_state_provider.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/ui.dart';

class RecentlyPlayedScreen extends ConsumerWidget {
  const RecentlyPlayedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final history = s.playedHistory;
    final topInset = MediaQuery.of(context).padding.top;

    return ColoredBox(
      color: c.bg,
      child: ListView(
        padding: EdgeInsets.fromLTRB(0, topInset + 8, 0, 140),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 20, 0),
            child: Row(
              children: [
                IconBtn(
                    icon: SolarIconsOutline.altArrowLeft,
                    color: c.fg,
                    size: 22,
                    onTap: () => context.pop()),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Recently Played',
                      style: SunohType.heading(
                          fontSize: 22, color: c.fg, letterSpacing: -0.3)),
                ),
                if (history.isNotEmpty)
                  GestureDetector(
                    onTap: () => _confirmClear(context, s),
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                      child: Text('Clear',
                          style: SunohType.sans(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: c.fgMute)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (history.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 40, 20, 40),
              child: Center(
                child: Column(
                  children: [
                    Text('Nothing here yet.',
                        style:
                            SunohType.heading(fontSize: 18, color: c.fgDim)),
                    const SizedBox(height: 8),
                    Text(
                        'Songs you play will show up here so you can jump back in.',
                        textAlign: TextAlign.center,
                        style:
                            SunohType.sans(fontSize: 12.5, color: c.fgMute)),
                  ],
                ),
              ),
            )
          else
            for (var i = 0; i < history.length; i++)
              _HistoryRow(
                song: history[i],
                colors: c,
                onTap: () => s.playApiQueue(history, i,
                    sourceLabel: 'RECENTLY PLAYED'),
              ),
        ],
      ),
    );
  }

  void _confirmClear(BuildContext context, dynamic s) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF15151A),
        title: const Text('Clear history?'),
        content: const Text(
            'This removes everything from Recently Played. Liked songs are not affected.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              s.clearPlayedHistory();
              Navigator.of(ctx).pop();
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends ConsumerWidget {
  const _HistoryRow({
    required this.song,
    required this.colors,
    required this.onTap,
  });
  final FeedItem song;
  final SunohColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    final s = ref.watch(appStateProvider);
    final liked = s.isLikedId(song.id);
    final accent = s.resolvedAccent;
    final artistsLabel = (song.artists ?? const <ApiArtistRef>[])
        .map((a) => a.name.trim())
        .where((sa) => sa.isNotEmpty)
        .take(2)
        .join(', ');
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            SunohArt(
                id: song.id, imageUrl: song.artwork, size: 44, radius: 6),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SunohType.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: c.fg)),
                  if (artistsLabel.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(artistsLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            SunohType.sans(fontSize: 11.5, color: c.fgMute)),
                  ],
                ],
              ),
            ),
            IconBtn(
                icon: liked
                    ? SolarIconsBold.heart
                    : SolarIconsOutline.heart,
                color: liked ? accent : c.fgMute,
                size: 16,
                width: 32,
                height: 32,
                onTap: () => s.toggleLikedSong(song)),
            IconBtn(
                icon: SolarIconsBold.menuDots,
                color: c.fgMute,
                size: 16,
                width: 32,
                height: 32,
                onTap: () => showTrackMenuSheet(context,
                    song: song, sourceLabel: 'RECENTLY PLAYED')),
          ],
        ),
      ),
    );
  }
}
