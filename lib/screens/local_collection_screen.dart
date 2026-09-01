// One on-device album or artist: its tracks, with play and shuffle.
//
// Reached by id from the device library. The id is the grouping key
// (`album|artist`, lowercased), not a MediaStore id, because that is what
// survives the same album arriving under two ALBUM_IDs — see
// `LocalMediaChannel` for why grouping works that way.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:solar_icons/solar_icons.dart';

import '../audio/local_library.dart';
import '../providers/app_state_provider.dart';
import '../providers/local_library_provider.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/ui.dart';
import 'local_track_row.dart';

class LocalCollectionScreen extends ConsumerWidget {
  const LocalCollectionScreen({
    super.key,
    required this.id,
    required this.album,
  });

  final String id;

  /// True for an album, false for an artist. Decides both the lookup and
  /// whether the cover renders square or round.
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

    return ColoredBox(
      color: c.bg,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                MediaQuery.of(context).padding.top + 20,
                20,
                8,
              ),
              child: Row(
                children: [
                  IconBtn(
                    icon: SolarIconsOutline.altArrowLeft,
                    color: c.fgDim,
                    size: 18,
                    onTap: () => context.pop(),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SunohArt(
                    id: id,
                    size: 104,
                    radius: album ? 10 : 999,
                    imageUrl: artwork,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        eyebrow(album ? 'ALBUM' : 'ARTIST', c.fgMute),
                        const SizedBox(height: 6),
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: SunohType.heading(
                            fontSize: 20,
                            color: c.fg,
                            height: 1.1,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${songs.length} '
                          '${songs.length == 1 ? 'song' : 'songs'} · on this device',
                          style: SunohType.sans(fontSize: 12, color: c.fgMute),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: Row(
                children: [
                  _Action(
                    icon: PhosphorIconsFill.play,
                    label: 'Play',
                    filled: true,
                    colors: c,
                    accent: s.resolvedAccent,
                    onTap: () =>
                        s.playApiQueue(songs, 0, sourceLabel: label),
                  ),
                  const SizedBox(width: 10),
                  _Action(
                    icon: PhosphorIconsBold.shuffle,
                    label: 'Shuffle',
                    filled: false,
                    colors: c,
                    accent: s.resolvedAccent,
                    onTap: () => s.playShuffled(songs, sourceLabel: label),
                  ),
                ],
              ),
            ),
          ),
          SliverList.builder(
            itemCount: songs.length,
            itemBuilder: (context, i) => LocalTrackRow(
              song: songs[i],
              colors: c,
              onTap: () => s.playApiQueue(songs, i, sourceLabel: label),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 140)),
        ],
      ),
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

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.filled,
    required this.colors,
    required this.accent,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool filled;
  final SunohColors colors;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: squircleDecoration(
          radius: 999,
          color: filled ? accent : colors.surface,
          borderColor: filled ? null : colors.line,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: filled ? Colors.black : colors.fg,
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: SunohType.sans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: filled ? Colors.black : colors.fg,
              ),
            ),
          ],
        ),
      ),
    );
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
              Icon(
                SolarIconsOutline.smartphone,
                size: 30,
                color: colors.fgMute,
              ),
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
