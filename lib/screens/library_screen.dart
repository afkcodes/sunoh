// Library tab — the user's saved + recently-played state.
//
// What it ISN'T (yet): saved albums / followed artists / playlists you've
// created / downloads. Those would each need their own backend or store
// surface; the pinned-tile + history layout is what makes sense with
// today's persistence (just the liked-songs set + the played-history list).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../api/dto.dart';
import '../overlays/track_menu_sheet.dart';
import '../providers/app_state_provider.dart';
import '../router/router.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/ui.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final liked = s.likedSongs;
    final history = s.playedHistory;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Library',
                  style: SunohType.heading(
                      fontSize: 28, color: c.fg, letterSpacing: -0.4)),
              IconBtn(
                  icon: SolarIconsOutline.magnifier,
                  color: c.fgDim,
                  size: 18,
                  width: 32,
                  height: 32,
                  onTap: () {}),
            ],
          ),
        ),
        const SizedBox(height: 18),
        // Pinned tiles. Real counts pulled from AppState.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
          child: Row(
            children: [
              Expanded(
                child: _PinnedTile(
                  title: 'Liked Songs',
                  sub: '${liked.length} ${liked.length == 1 ? 'song' : 'songs'}',
                  icon: SolarIconsBold.heart,
                  gradient: [
                    s.resolvedAccent.withValues(alpha: 0.85),
                    s.resolvedAccent.withValues(alpha: 0.18),
                  ],
                  onTap: () => context.openLikedSongs(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PinnedTile(
                  title: 'Downloaded',
                  sub: '— offline',
                  icon: SolarIconsOutline.downloadMinimalistic,
                  gradient: const [Color(0xFF1D3A3A), Color(0xFF0E1818)],
                  onTap: () => s.flashToast('Downloads coming soon'),
                ),
              ),
            ],
          ),
        ),
        // Recently played — header + inline rows + "See all".
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text('Recently Played',
                    style: SunohType.heading(
                        fontSize: 19,
                        color: c.fg,
                        letterSpacing: -0.2,
                        height: 1)),
              ),
              if (history.length > 5)
                GestureDetector(
                  onTap: () => context.openRecentlyPlayed(),
                  child: Text('See all →',
                      style: SunohType.sans(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: c.fgMute)),
                ),
            ],
          ),
        ),
        if (history.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Text(
                'Songs you play will show up here so you can jump back in.',
                style: SunohType.sans(fontSize: 12.5, color: c.fgMute)),
          )
        else
          for (var i = 0; i < history.length && i < 8; i++)
            _LibRow(
              song: history[i],
              colors: c,
              onTap: () => s.playApiQueue(history, i,
                  sourceLabel: 'RECENTLY PLAYED'),
            ),
        const SizedBox(height: 20),
      ],
    );
  }
}

/// A tappable rectangular tile with a gradient backdrop + icon + title + sub.
/// Pinned to the top of the library — visually distinct from the row list
/// below so the user reads "shortcuts" vs "items" immediately.
class _PinnedTile extends StatelessWidget {
  const _PinnedTile({
    required this.title,
    required this.sub,
    required this.icon,
    required this.gradient,
    required this.onTap,
  });
  final String title;
  final String sub;
  final IconData icon;
  final List<Color> gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 84,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: squircleDecoration(
          radius: 14,
          gradient: LinearGradient(
              colors: gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: Colors.white.withValues(alpha: 0.95)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SunohType.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          letterSpacing: -0.1)),
                  const SizedBox(height: 4),
                  eyebrow(sub, Colors.white.withValues(alpha: 0.6),
                      size: 9, letterSpacing: 1.2, maxLines: 1),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LibRow extends ConsumerWidget {
  const _LibRow({
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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
