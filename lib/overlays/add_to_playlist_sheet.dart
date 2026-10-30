// "Add to playlist" picker — opened from the track menu sheet.
//
//   - the sheet title names the song being added, so the picker cannot be
//     mistaken for a different song's
//   - "New playlist" is the first row, drawn like a playlist row whose cover
//     is a plus, the way Library leads with its own shortcut rows
//   - each existing playlist is a list row: its cover (or an accent fallback)
//     + name + song count, with a check when the song is already in it

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remixicon/remixicon.dart';

import '../api/dto.dart';
import '../data/user_playlist.dart';
import '../providers/app_state_provider.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/ui.dart';
import 'playlist_name_sheet.dart';
import 'sheet.dart';
import 'sheet_row.dart';

Future<void> showAddToPlaylistSheet(
  BuildContext context, {
  required FeedItem song,
}) => showSunohSheet<void>(
  context,
  builder: (_) => _AddToPlaylistSheet(song: song),
);

/// A list row's height with 48 art — see SheetRow.
const double _kRowHeight = 64;

class _AddToPlaylistSheet extends ConsumerWidget {
  const _AddToPlaylistSheet({required this.song});
  final FeedItem song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final playlists = s.userPlaylists;
    // A fixed-height lazy list inside the sheet's scroll view: someone with a
    // hundred playlists should not have a hundred rows built to open this.
    // Half the screen keeps "New playlist" and the title in view above it.
    final listHeight = math.min(
      playlists.length * _kRowHeight,
      MediaQuery.sizeOf(context).height * 0.5,
    );

    return SunohSheet(
      title: 'Add to playlist',
      subtitle: song.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SheetRow(
            leading: _Tile(
              color: c.surface2,
              child: Icon(RemixIcons.add_circle_line, size: 22, color: c.fg),
            ),
            label: 'New playlist',
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
          if (playlists.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Text(
                'No playlists yet. Tap "New playlist" above to start one.',
                style: SunohType.sans(
                  fontSize: 12.5,
                  color: c.fgMute,
                  height: 1.4,
                ),
              ),
            )
          else
            SizedBox(
              height: listHeight,
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemExtent: _kRowHeight,
                itemCount: playlists.length,
                itemBuilder: (context, i) {
                  final p = playlists[i];
                  return SheetRow(
                    leading: _PlaylistArt(playlist: p, accent: c.accent),
                    label: p.name,
                    subtitle:
                        '${p.songs.length} '
                        '${p.songs.length == 1 ? 'song' : 'songs'}',
                    selected: p.songs.any((x) => x.id == song.id),
                    colors: c,
                    onTap: () async {
                      await s.addSongToUserPlaylist(p.id, song);
                      if (context.mounted) Navigator.of(context).pop();
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// The 48 square a list row leads with.
class _Tile extends StatelessWidget {
  const _Tile({required this.child, this.color, this.gradient});
  final Widget child;
  final Color? color;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) => Container(
    width: 48,
    height: 48,
    alignment: Alignment.center,
    decoration: squircleDecoration(
      radius: SunohRadius.row,
      color: color,
      gradient: gradient,
    ),
    child: child,
  );
}

/// The playlist's first cover, or an accent square when none of its songs
/// has one.
class _PlaylistArt extends StatelessWidget {
  const _PlaylistArt({required this.playlist, required this.accent});
  final UserPlaylist playlist;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final cover = _firstArtwork(playlist);
    if (cover != null) {
      return SunohArt(
        id: playlist.id,
        imageUrl: cover,
        size: 48,
        radius: SunohRadius.row,
      );
    }
    return _Tile(
      gradient: LinearGradient(
        colors: [
          accent.withValues(alpha: 0.85),
          accent.withValues(alpha: 0.35),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      // Ink by the accent's own luminance: white vanished on an ivory one.
      child: Icon(RemixIcons.album_fill, size: 20, color: inkOn(accent)),
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
