// The Library tab's window onto the on-device music library.
//
// A preview rather than a link: a strip of album covers with "See all", the
// same shape the home feed uses for its shelves. The point is that the phone's
// own music reads as part of the library rather than as a settings row —
// covers you recognise are what make it feel like yours, and a plain text row
// gives you nothing to recognise.
//
// Covers open their album directly, so the common case (play a specific album
// I already know is on my phone) is two taps rather than four.

import 'package:flutter/material.dart';
import 'package:solar_icons/solar_icons.dart';

import '../api/local_media_channel.dart';
import '../audio/local_library.dart';
import '../router/router.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/ui.dart';

/// How many covers the strip shows before "See all" takes over. Enough to fill
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
    // having plenty to play — fall back to tracks so the strip is never empty
    // when there is music.
    final albums = library.albums;
    final useAlbums = albums.isNotEmpty;
    final count = library.songs.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'On this device',
          colors: c,
          eyebrowText: _eyebrow(count),
          onSeeAll: library.hasMusic ? () => context.openLocalLibrary() : null,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        ),
        if (!library.hasMusic)
          _Prompt(library: library, colors: c)
        else if (useAlbums)
          _AlbumStrip(
            albums: albums.take(_kPreviewCount).toList(),
            total: albums.length,
            colors: c,
          )
        else
          _TrackStrip(
            songs: library.songs.take(_kPreviewCount).toList(),
            colors: c,
          ),
        const SizedBox(height: 22),
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

class _AlbumStrip extends StatelessWidget {
  const _AlbumStrip({
    required this.albums,
    required this.total,
    required this.colors,
  });
  final List<LocalCollection> albums;
  final int total;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    const width = 116.0;
    return SizedBox(
      height: width + 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        // One past the covers when there are more, for the trailing tile.
        itemCount: albums.length + (total > albums.length ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          if (i >= albums.length) {
            return _MoreTile(
              remaining: total - albums.length,
              width: width,
              colors: colors,
            );
          }
          final album = albums[i];
          return GestureDetector(
            onTap: () => context.openLocalCollection(album.id, album: true),
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SunohArt(
                    id: album.id,
                    size: width,
                    radius: 10,
                    imageUrl: album.artwork,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    album.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SunohType.sans(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: colors.fg,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    album.subtitle ?? '${album.songs.length} songs',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SunohType.sans(
                      fontSize: 11.5,
                      color: colors.fgDim,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Fallback strip for libraries of loose files with no album tags.
class _TrackStrip extends StatelessWidget {
  const _TrackStrip({required this.songs, required this.colors});
  final List songs;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    const width = 116.0;
    return SizedBox(
      height: width + 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: songs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final song = songs[i];
          return GestureDetector(
            onTap: () => context.openLocalLibrary(),
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SunohArt(
                    id: song.id,
                    size: width,
                    radius: 10,
                    imageUrl: song.artwork,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SunohType.sans(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: colors.fg,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Trailing tile that says how much the strip is not showing.
class _MoreTile extends StatelessWidget {
  const _MoreTile({
    required this.remaining,
    required this.width,
    required this.colors,
  });
  final int remaining;
  final double width;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.openLocalLibrary(),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: width,
              height: width,
              alignment: Alignment.center,
              decoration: squircleDecoration(
                radius: 10,
                color: colors.surface,
                borderColor: colors.line,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    SolarIconsOutline.altArrowRight,
                    size: 20,
                    color: colors.fgDim,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '+$remaining',
                    style: SunohType.mono(fontSize: 12, color: colors.fgDim),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'See all',
              style: SunohType.sans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: colors.fgDim,
              ),
            ),
          ],
        ),
      ),
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
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: () => context.openLocalLibrary(),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: squircleDecoration(
            radius: 14,
            color: colors.surface,
            borderColor: colors.line,
          ),
          child: Row(
            children: [
              Icon(SolarIconsOutline.smartphone, size: 19, color: colors.fgDim),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  library.isScanning
                      ? 'Looking for music on this phone…'
                      : needsAccess
                      ? 'Let sunoh play music stored on this phone'
                      : 'No music found on this phone',
                  style: SunohType.sans(fontSize: 13, color: colors.fgDim),
                ),
              ),
              if (!library.isScanning)
                Icon(
                  SolarIconsOutline.altArrowRight,
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
