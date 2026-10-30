// The Library tab's window onto the on-device music library.
//
// A preview rather than a link: a shelf of album covers with "See all", the
// same shape the home feed uses for its shelves. The point is that the phone's
// own music reads as part of the library rather than as a settings row —
// covers you recognise are what make it feel like yours, and a plain text row
// gives you nothing to recognise.
//
// Covers open their album directly, so the common case (play a specific album
// I already know is on my phone) is two taps rather than four.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:remixicon/remixicon.dart';

import '../api/dto.dart';
import '../api/local_media_channel.dart';
import '../audio/local_library.dart';
import '../router/router.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/motion.dart';
import '../widgets/ui.dart';
import 'cover_tile.dart';

/// How many covers the shelf shows before "See all" takes over. Enough to fill
/// the row and hint at more; not so many that a large library builds dozens of
/// off-screen cards on every Library render.
const int _kPreviewCount = 10;

class LibraryDeviceSection extends StatelessWidget {
  const LibraryDeviceSection({
    super.key,
    required this.library,
    required this.colors,
  });

  final LocalLibrary library;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    // Albums lead, but a library of loose files may have none while still
    // having plenty to play — fall back to tracks so the shelf is never empty
    // when there is music. The count reads the scan-order list: `songs` sorts
    // on every read, and a length does not need an order.
    final albums = library.albums;
    final count = library.songsByDateAdded.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 30),
        SectionHeader(
          title: 'On this device',
          colors: c,
          eyebrowText: _eyebrow(count),
          onSeeAll: library.hasMusic ? () => context.openLocalLibrary() : null,
        ),
        if (!library.hasMusic)
          _Prompt(library: library, colors: c)
        else if (albums.isNotEmpty)
          _AlbumShelf(albums: albums, colors: c)
        else
          _TrackShelf(songs: library.songs, colors: c),
      ],
    );
  }

  String _eyebrow(int songs) => switch (library.status) {
    LocalLibraryStatus.scanning => 'SCANNING',
    LocalLibraryStatus.denied ||
    LocalLibraryStatus.permanentlyDenied => 'NEEDS ACCESS',
    _ when songs > 0 => '$songs ${songs == 1 ? 'SONG' : 'SONGS'}',
    _ => 'YOUR PHONE',
  };
}

class _AlbumShelf extends StatelessWidget {
  const _AlbumShelf({required this.albums, required this.colors});
  final List<LocalCollection> albums;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    // Indexes into the full list rather than copying a preview out of it, so
    // a rebuild allocates nothing.
    final shown = math.min(albums.length, _kPreviewCount);
    final more = albums.length - shown;
    return CoverShelf(
      // One past the covers when there are more, for the trailing tile.
      itemCount: shown + (more > 0 ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= shown) return _MoreTile(remaining: more, colors: colors);
        final album = albums[i];
        return CoverTile(
          cover: SunohArt(
            id: album.id,
            size: kCoverTileWidth,
            radius: SunohRadius.tile,
            imageUrl: album.artwork,
            shadow: false,
          ),
          title: album.name,
          subtitle: album.subtitle ?? '${album.songs.length} songs',
          colors: colors,
          onTap: () => context.openLocalCollection(album.id, album: true),
        );
      },
    );
  }
}

/// Fallback shelf for libraries of loose files with no album tags.
class _TrackShelf extends StatelessWidget {
  const _TrackShelf({required this.songs, required this.colors});
  final List<FeedItem> songs;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    return CoverShelf(
      itemCount: math.min(songs.length, _kPreviewCount),
      itemBuilder: (context, i) {
        final song = songs[i];
        return CoverTile(
          cover: SunohArt(
            id: song.id,
            size: kCoverTileWidth,
            radius: SunohRadius.tile,
            imageUrl: song.artwork,
            shadow: false,
          ),
          title: song.title,
          colors: colors,
          onTap: () => context.openLocalLibrary(),
        );
      },
    );
  }
}

/// Trailing tile that says how much the shelf is not showing.
class _MoreTile extends StatelessWidget {
  const _MoreTile({required this.remaining, required this.colors});
  final int remaining;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    return CoverTile(
      cover: Container(
        width: kCoverTileWidth,
        height: kCoverTileWidth,
        alignment: Alignment.center,
        decoration: squircleDecoration(
          radius: SunohRadius.tile,
          color: colors.surface2,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(RemixIcons.arrow_right_s_line, size: 20, color: colors.fgDim),
            const SizedBox(height: 6),
            Text(
              '+$remaining',
              style: SunohType.mono(fontSize: 12, color: colors.fgDim),
            ),
          ],
        ),
      ),
      title: 'See all',
      colors: colors,
      onTap: () => context.openLocalLibrary(),
    );
  }
}

/// Shown when there is nothing to preview: no access yet, or no music.
class _Prompt extends StatelessWidget {
  const _Prompt({required this.library, required this.colors});
  final LocalLibrary library;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    final needsAccess =
        library.status == LocalLibraryStatus.denied ||
        library.status == LocalLibraryStatus.permanentlyDenied ||
        library.status == LocalLibraryStatus.idle;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Pressable(
        onTap: () => context.openLocalLibrary(),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: squircleDecoration(
            radius: SunohRadius.card,
            color: colors.surface,
          ),
          child: Row(
            children: [
              Icon(RemixIcons.smartphone_line, size: 20, color: colors.fgDim),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  library.isScanning
                      ? 'Looking for music on this phone…'
                      : needsAccess
                      ? 'Let sunoh play music stored on this phone'
                      : 'No music found on this phone',
                  style: SunohType.sans(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: colors.fg,
                  ),
                ),
              ),
              if (!library.isScanning)
                Icon(
                  RemixIcons.arrow_right_s_line,
                  size: 16,
                  color: colors.fgMute,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
