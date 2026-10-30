// User-playlist presentation for the Library tab: rows that carry on the
// Library list in list mode, and a cover shelf in grid mode.
//
// Extracted from `library_screen.dart` so that file could take the on-device
// entry point without growing. These are private to the Library tab in spirit
// but public here because Dart has no narrower scope.

import 'package:flutter/material.dart';
import 'package:remixicon/remixicon.dart';

import '../data/user_playlist.dart';
import '../router/router.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';
import 'cover_tile.dart';
import 'library_rows.dart';

/// Grid mode: the playlists as their own shelf, under a header.
class UserPlaylistsStrip extends StatelessWidget {
  const UserPlaylistsStrip({
    super.key,
    required this.playlists,
    required this.colors,
    required this.accent,
  });
  final List<UserPlaylist> playlists;
  final SunohColors colors;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 30),
        SectionHeader(title: 'My playlists', colors: c),
        CoverShelf(
          itemCount: playlists.length,
          itemBuilder: (context, i) {
            final p = playlists[i];
            final n = p.songs.length;
            return CoverTile(
              cover: _PlaylistCover(
                playlist: p,
                size: kCoverTileWidth,
                radius: SunohRadius.tile,
                glyph: 38,
                accent: accent,
              ),
              title: p.name,
              subtitle: '$n ${n == 1 ? 'song' : 'songs'}',
              colors: c,
              onTap: () => context.openUserPlaylist(p.id),
            );
          },
        ),
      ],
    );
  }
}

/// List mode: one row per playlist and no header of their own, so they read
/// as the next rows after Liked songs — the prototype's Library is one list
/// of playlists, not a playlists section.
class UserPlaylistsList extends StatelessWidget {
  const UserPlaylistsList({
    super.key,
    required this.playlists,
    required this.colors,
    required this.accent,
  });
  final List<UserPlaylist> playlists;
  final SunohColors colors;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final p in playlists)
          UserPlaylistRow(playlist: p, colors: colors, accent: accent),
      ],
    );
  }
}

/// Single user-playlist row. The Library's big row, but takes a
/// `UserPlaylist` directly because the FeedItem mapper for user playlists
/// doesn't exist (and routing the tap is a single line, so not worth
/// synthesizing one).
class UserPlaylistRow extends StatelessWidget {
  const UserPlaylistRow({
    super.key,
    required this.playlist,
    required this.colors,
    required this.accent,
  });
  final UserPlaylist playlist;
  final SunohColors colors;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final n = playlist.songs.length;
    return LibraryRow(
      art: _PlaylistCover(
        playlist: playlist,
        size: 56,
        radius: SunohRadius.row,
        glyph: 24,
        accent: accent,
      ),
      title: playlist.name,
      subtitle: 'Playlist · $n ${n == 1 ? 'song' : 'songs'}',
      colors: colors,
      onTap: () => context.openUserPlaylist(playlist.id),
    );
  }
}

/// The first song's artwork, or null while the playlist has none.
String? _firstArtwork(UserPlaylist p) {
  for (final s in p.songs) {
    final a = s.artwork;
    if (a != null && a.isNotEmpty) return a;
  }
  return null;
}

/// A playlist's cover: its first song's artwork, or an accent tile with a
/// library glyph while it has none (or the artwork fails). The glyph's ink is
/// picked from the fill, because the accent may be tinted from artwork and
/// its lightness is not known in advance.
class _PlaylistCover extends StatelessWidget {
  const _PlaylistCover({
    required this.playlist,
    required this.size,
    required this.radius,
    required this.glyph,
    required this.accent,
  });
  final UserPlaylist playlist;
  final double size;
  final double radius;
  final double glyph;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final cover = _firstArtwork(playlist);
    final fallback = ColoredBox(
      color: accent,
      child: Icon(RemixIcons.album_fill, size: glyph, color: inkOn(accent)),
    );
    return squircleClip(
      radius: radius,
      child: SizedBox(
        width: size,
        height: size,
        child: cover == null
            ? fallback
            : Image.network(
                cover,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}
