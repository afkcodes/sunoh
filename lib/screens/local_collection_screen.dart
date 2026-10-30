// One on-device album or artist, laid out as an album page: hero, shuffle
// and play, then its tracks — numbered for an album, with covers for an
// artist.
//
// Reached by id from the device library. The id is the grouping key
// (`album|artist`, lowercased), not a MediaStore id, because that is what
// survives the same album arriving under two ALBUM_IDs — see
// `LocalMediaChannel` for why grouping works that way.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:remixicon/remixicon.dart';

import '../audio/local_library.dart';
import '../providers/app_state_provider.dart';
import '../providers/local_library_provider.dart';
import '../theme/tokens.dart';
import '../widgets/motion.dart';
import 'detail_chrome.dart';
import 'detail_hero.dart';
import 'detail_track_row.dart';

class LocalCollectionScreen extends ConsumerWidget {
  const LocalCollectionScreen({
    super.key,
    required this.id,
    required this.album,
  });

  final String id;

  /// True for an album, false for an artist. Decides the lookup, whether the
  /// cover renders square or round, and whether tracks are numbered.
  final bool album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final lib = ref.watch(localLibraryProvider);
    final songs = lib.songsIn(id, album: album);

    // The library is scanned per session, so a deep link or a back-navigation
    // after a rescan can land here with nothing. Say so rather than render an
    // empty page that looks broken.
    if (songs.isEmpty) {
      return _Missing(colors: c, scanning: lib.isScanning);
    }

    final title = _titleFor(lib, songs);
    final artwork = songs
        .map((s) => s.artwork)
        .firstWhere((a) => a != null && a.isNotEmpty, orElse: () => null);
    final label = '${album ? 'ALBUM' : 'ARTIST'} · $title';
    final labels = TrackLabels.of(songs);
    final accent = c.accent;
    // The queue is this collection when it was started from here.
    final here = s.apiSourceRef == null && s.apiSourceLabel == label;

    return DetailPage(
      colors: c,
      colour: accent,
      title: title,
      builder: (scroll) => [
        SliverToBoxAdapter(
          child: DetailHero(
            colors: c,
            colour: accent,
            scroll: scroll,
            cover: DetailCover(id: id, imageUrl: artwork, round: !album),
            title: title,
            meta: joinMeta([
              album ? 'Album' : 'Artist',
              labels.countLine('song'),
              'On this device',
            ]),
          ),
        ),
        SliverToBoxAdapter(
          child: FadeSlideIn(
            index: 3,
            child: DetailActions(
              colors: c,
              colour: accent,
              playing: here && s.isPlaying,
              onShuffle: () => s.playShuffled(songs, sourceLabel: label),
              onPlay: () => here
                  ? s.playPause()
                  : s.playApiQueue(songs, 0, sourceLabel: label),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.only(top: 8),
          sliver: SliverList.builder(
            itemCount: songs.length,
            itemBuilder: (context, i) {
              // An album numbers its tracks; an artist's span albums, so
              // they show their own covers instead.
              final row = DetailTrackRow(
                n: album ? i + 1 : null,
                song: songs[i],
                subtitle: labels.subtitles[i],
                duration: labels.durations[i],
                colors: c,
                accent: accent,
                showArt: !album,
                showLike: false,
                showMenu: false,
                onTap: () => s.playApiQueue(songs, i, sourceLabel: label),
              );
              return i < 6 ? Entrance(index: 4 + i, child: row) : row;
            },
          ),
        ),
      ],
    );
  }

  /// An album's title is the album name; an artist's is the artist name. Both
  /// come off the collection, falling back to the first track when a rescan
  /// has dropped the grouping.
  String _titleFor(LocalLibrary lib, List songs) {
    for (final col in album ? lib.albums : lib.artists) {
      if (col.id == id) return col.name;
    }
    return id;
  }
}

class _Missing extends StatelessWidget {
  const _Missing({required this.colors, required this.scanning});
  final SunohColors colors;
  final bool scanning;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: colors.bg,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(RemixIcons.smartphone_line, size: 30, color: colors.fgMute),
              const SizedBox(height: 14),
              Text(
                scanning ? 'Still scanning…' : 'Not on this device any more',
                textAlign: TextAlign.center,
                style: SunohType.sans(fontSize: 14, color: colors.fgDim),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => context.pop(),
                child: Text(
                  'Go back',
                  style: SunohType.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.accent,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
