// User-playlist presentation for the Library tab: the horizontal strip in
// grid mode, and the rows in list mode.
//
// Extracted from `library_screen.dart` so that file could take the on-device
// entry point without growing. These are private to the Library tab in spirit
// but public here because Dart has no narrower scope.

import 'package:flutter/material.dart';
import 'package:solar_icons/solar_icons.dart';

import '../data/user_playlist.dart';
import '../router/router.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/ui.dart';

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
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: eyebrow(
            'MY PLAYLISTS',
            c.fgMute,
            size: 10,
            letterSpacing: 1.4,
          ),
        ),
        SizedBox(
          height: 158,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: playlists.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final p = playlists[i];
              final cover = _firstArtwork(p);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => context.openUserPlaylist(p.id),
                child: SizedBox(
                  width: 116,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      squircleClip(
                        radius: 10,
                        child: Container(
                          width: 116,
                          height: 116,
                          decoration: BoxDecoration(
                            gradient: cover == null
                                ? LinearGradient(
                                    colors: [
                                      accent.withValues(alpha: 0.85),
                                      accent.withValues(alpha: 0.35),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  )
                                : null,
                          ),
                          child: cover == null
                              ? Icon(
                                  SolarIconsBold.musicLibrary2,
                                  size: 38,
                                  color: Colors.white.withValues(alpha: 0.9),
                                )
                              : Image.network(
                                  cover,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Icon(
                                    SolarIconsBold.musicLibrary2,
                                    size: 38,
                                    color: Colors.white.withValues(alpha: 0.9),
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SunohType.sans(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: c.fg,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '${p.songs.length} '
                        '${p.songs.length == 1 ? 'song' : 'songs'}',
                        style: SunohType.sans(fontSize: 11, color: c.fgMute),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
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

/// List-mode counterpart of [_UserPlaylistsStrip] — eyebrow header
/// plus one [_UserPlaylistRow] per playlist. Same vertical rhythm as
/// the saved-items `_ListRow`s rendered below so the Library reads as
/// a single uniform list when grid mode is off.
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
    final c = colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: eyebrow(
            'MY PLAYLISTS',
            c.fgMute,
            size: 10,
            letterSpacing: 1.4,
          ),
        ),
        for (final p in playlists)
          UserPlaylistRow(playlist: p, colors: c, accent: accent),
      ],
    );
  }
}

/// Single user-playlist row in list mode. Mirrors the visual shape of
/// `_ListRow` (50-px cover + title + subtitle) but takes a
/// `UserPlaylist` directly because the FeedItem mapper for user
/// playlists doesn't exist (and routing the tap is a single line, so
/// not worth synthesizing one).
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
    final c = colors;
    final cover = UserPlaylistsStrip._firstArtwork(playlist);
    final n = playlist.songs.length;
    return GestureDetector(
      onTap: () => context.openUserPlaylist(playlist.id),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            // Same artwork treatment as the strip — accent gradient
            // fallback with a music-library glyph when the playlist
            // has no songs yet, real cover from the first song
            // otherwise. 50-px to match _ListRow.
            squircleClip(
              radius: 8,
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  gradient: cover == null
                      ? LinearGradient(
                          colors: [
                            accent.withValues(alpha: 0.85),
                            accent.withValues(alpha: 0.35),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                ),
                child: cover == null
                    ? Icon(
                        SolarIconsBold.musicLibrary2,
                        size: 22,
                        color: Colors.white.withValues(alpha: 0.9),
                      )
                    : Image.network(
                        cover,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Icon(
                          SolarIconsBold.musicLibrary2,
                          size: 22,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playlist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SunohType.sans(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                      color: c.fg,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$n ${n == 1 ? 'song' : 'songs'}',
                    style: SunohType.sans(fontSize: 11.5, color: c.fgMute),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal scroller of subscribed podcasts. Renders only when the
/// user has any (the Library tab hides the section otherwise).
