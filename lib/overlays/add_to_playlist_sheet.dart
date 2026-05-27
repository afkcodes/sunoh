// "Add to playlist" picker — opened from the track menu sheet. Visually
// patterned on the cast picker:
//   - playlist medallion (52×52) + eyebrow + heading rhythm
//   - a "New playlist" squircle pill at the top (accent medallion + plus)
//   - each existing playlist is a squircle pill with its cover thumbnail
//     (or accent gradient fallback) on the left + name + song count, plus
//     a check when the current song is already in it

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../api/dto.dart';
import '../data/user_playlist.dart';
import '../providers/app_state_provider.dart';
import '../screens/user_playlist_screen.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';

Future<void> showAddToPlaylistSheet(
  BuildContext context, {
  required FeedItem song,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useRootNavigator: true,
    builder: (_) => _AddToPlaylistSheet(song: song),
  );
}

class _AddToPlaylistSheet extends ConsumerWidget {
  const _AddToPlaylistSheet({required this.song});
  final FeedItem song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final accent = s.resolvedAccent;
    final topInset = MediaQuery.of(context).padding.bottom;
    final playlists = s.userPlaylists;
    final maxH = MediaQuery.of(context).size.height * 0.7;

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        constraints: BoxConstraints(maxHeight: maxH),
        decoration: squircleDecoration(
          radius: 20,
          color: const Color(0xFF15151A),
          borderColor: c.line,
        ),
        padding: EdgeInsets.fromLTRB(0, 8, 0, 8 + topInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle.
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Medallion + eyebrow + heading.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.22),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(SolarIconsBold.playlist,
                        color: accent, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        eyebrow('ADD TO PLAYLIST', c.fgMute,
                            size: 9, letterSpacing: 1.6),
                        const SizedBox(height: 4),
                        Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SunohType.heading(
                              fontSize: 18,
                              color: c.fg,
                              letterSpacing: -0.3),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              height: 0.5,
              color: c.line,
              margin: const EdgeInsets.symmetric(horizontal: 12),
            ),
            // "New playlist" — flat row at the top, accent-tinted glyph
            // signals it's the primary CTA without wrapping it in a card.
            _NewPlaylistRow(
              accent: accent,
              colors: c,
              onTap: () async {
                final name = await promptForPlaylistName(context);
                if (name == null || name.isEmpty) return;
                if (!context.mounted) return;
                final p = await s.createUserPlaylist(name);
                await s.addSongToUserPlaylist(p.id, song);
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
            if (playlists.isNotEmpty)
              Container(
                height: 0.5,
                color: c.line.withValues(alpha: 0.5),
                margin: const EdgeInsets.symmetric(horizontal: 22),
              ),
            Flexible(
              child: playlists.isEmpty
                  ? Padding(
                      padding:
                          const EdgeInsets.fromLTRB(22, 18, 22, 16),
                      child: Text(
                          'No playlists yet. Tap "New playlist" above to start one.',
                          style: SunohType.sans(
                              fontSize: 12.5,
                              color: c.fgMute,
                              height: 1.4)),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: playlists.length,
                      separatorBuilder: (_, _) => Container(
                        height: 0.5,
                        color: c.line.withValues(alpha: 0.5),
                        margin:
                            const EdgeInsets.symmetric(horizontal: 22),
                      ),
                      itemBuilder: (context, i) {
                        final p = playlists[i];
                        final already =
                            p.songs.any((x) => x.id == song.id);
                        return _PlaylistRow(
                          playlist: p,
                          accent: accent,
                          colors: c,
                          already: already,
                          onTap: () async {
                            await s.addSongToUserPlaylist(p.id, song);
                            if (context.mounted) {
                              Navigator.of(context).pop();
                            }
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Flat "New playlist" row — same `InkWell + Padding(22, 14)` shape as the
/// track-menu sheet's `_MenuRow`. Accent-tinted leading icon signals it's
/// the primary CTA without wrapping the row in a card.
class _NewPlaylistRow extends StatelessWidget {
  const _NewPlaylistRow({
    required this.accent,
    required this.colors,
    required this.onTap,
  });
  final Color accent;
  final SunohColors colors;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        child: Row(
          children: [
            Icon(SolarIconsBold.addCircle, color: accent, size: 20),
            const SizedBox(width: 16),
            Expanded(
              child: Text('New playlist',
                  style: SunohType.sans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: accent)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Flat playlist row — small cover thumbnail + name + song count, with
/// an "already added" check on the right when the song is in the
/// playlist. Matches the sheet's flat-row convention.
class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow({
    required this.playlist,
    required this.accent,
    required this.colors,
    required this.already,
    required this.onTap,
  });
  final UserPlaylist playlist;
  final Color accent;
  final SunohColors colors;
  final bool already;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = colors;
    final cover = _firstArtwork(playlist);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
        child: Row(
          children: [
            squircleClip(
              radius: 7,
              child: SizedBox(
                width: 38,
                height: 38,
                child: cover != null
                    ? Image.network(cover,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _PlaylistArtFallback(
                            accent: accent))
                    : _PlaylistArtFallback(accent: accent),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(playlist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SunohType.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: c.fg)),
                  const SizedBox(height: 1),
                  Text(
                      '${playlist.songs.length} '
                      '${playlist.songs.length == 1 ? 'song' : 'songs'}',
                      style: SunohType.sans(
                          fontSize: 11.5, color: c.fgMute)),
                ],
              ),
            ),
            if (already)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(SolarIconsBold.checkCircle,
                    size: 18, color: accent),
              ),
          ],
        ),
      ),
    );
  }

  static String? _firstArtwork(UserPlaylist p) {
    for (final s in p.songs) {
      final a = s.artwork;
      if (a != null && a.isNotEmpty) return a;
    }
    return null;
  }
}

class _PlaylistArtFallback extends StatelessWidget {
  const _PlaylistArtFallback({required this.accent});
  final Color accent;
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.85),
            accent.withValues(alpha: 0.35),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Icon(SolarIconsBold.musicLibrary2,
          size: 18, color: Colors.white.withValues(alpha: 0.92)),
    );
  }
}
