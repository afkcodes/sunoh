// YouTube Music detail surfaces: a playlist/album track list, the moods &
// genres chip index, and one mood/genre category.
//
// These exist because YouTube browse ids can't go through the normal detail
// screens — those resolve against sunoh-api, which knows nothing about a
// `VLRDCLAK5uy_…` id.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';

import '../api/ytmusic_api.dart';
import '../data/models.dart';
import '../providers/app_state_provider.dart';
import 'detail_screens.dart' show AlbumLikeBody;
import '../providers/ytmusic_provider.dart';
import '../router/router.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/ui.dart';

/// Shared chrome: back chip + big title, matching SectionScreen.
class _YtScaffold extends StatelessWidget {
  const _YtScaffold({
    required this.title,
    required this.colors,
    required this.children,
  });
  final String title;
  final SunohColors colors;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final topInset = MediaQuery.of(context).padding.top;
    return ColoredBox(
      color: c.bg,
      child: ListView(
        padding: EdgeInsets.only(top: topInset + 8, bottom: 140),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                IconBtn(
                  icon: SolarIconsOutline.altArrowLeft,
                  color: c.fg,
                  size: 22,
                  background: c.surface,
                  onTap: () => context.pop(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Text(
              title,
              style: SunohType.heading(
                  fontSize: 30,
                  color: c.fg,
                  height: 1.05,
                  letterSpacing: -0.5),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

Widget _loading(SunohColors c) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2, color: c.fgMute),
        ),
      ),
    );

Widget _error(SunohColors c, String message) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 40),
      child: Text(message,
          style: SunohType.sans(fontSize: 13, color: c.fgMute)),
    );

// ── Playlist / album ───────────────────────────────────────────────────────

class YtPlaylistScreen extends ConsumerWidget {
  const YtPlaylistScreen({super.key, required this.browseId, this.name});
  final String browseId;
  final String? name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final async = ref.watch(ytMusicPlaylistProvider(browseId));

    return async.when(
      loading: () => _YtScaffold(
        title: name ?? 'Playlist',
        colors: c,
        children: [_loading(c)],
      ),
      error: (e, _) => _YtScaffold(
        title: name ?? 'Playlist',
        colors: c,
        children: [_error(c, 'Couldn\u2019t load this playlist.')],
      ),
      data: (detail) {
        if (detail == null) {
          return _YtScaffold(
            title: name ?? 'Playlist',
            colors: c,
            children: [_error(c, 'This playlist isn\u2019t available.')],
          );
        }
        // Reuse the album/playlist body the rest of the app uses, rather
        // than a bespoke layout — that's what gives YouTube playlists the
        // same scroll-shrink hero, sticky header, hero actions, track rows
        // and menus as a saavn or gaana playlist.
        return AlbumLikeBody(
          colors: c,
          id: detail.id,
          title: detail.title,
          imageUrl: detail.artwork,
          eyebrowText: 'PLAYLIST',
          sub: detail.subtitle,
          secondary: detail.tracks.isEmpty
              ? null
              : '${detail.tracks.length} track'
                  '${detail.tracks.length == 1 ? '' : 's'}',
          description: detail.description,
          songs: detail.tracks,
          sections: const [],
          // Tracks come from many different albums, so rows show their own
          // art (the album-style numbered list would be misleading here).
          showAlbumArtInRow: true,
          sourceRef: DetailRef('playlist', detail.id, source: 'youtube'),
        );
      },
    );
  }
}

// ── Artist ─────────────────────────────────────────────────────────────────

class YtArtistScreen extends ConsumerWidget {
  const YtArtistScreen({super.key, required this.browseId, this.name});
  final String browseId;
  final String? name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final async = ref.watch(ytMusicArtistProvider(browseId));

    return async.when(
      loading: () => _YtScaffold(
          title: name ?? 'Artist', colors: c, children: [_loading(c)]),
      error: (e, _) => _YtScaffold(
        title: name ?? 'Artist',
        colors: c,
        children: [_error(c, 'Couldn\u2019t load this artist.')],
      ),
      data: (artist) {
        if (artist == null) {
          return _YtScaffold(
            title: name ?? 'Artist',
            colors: c,
            children: [_error(c, 'This artist isn\u2019t available.')],
          );
        }
        // Same body as every other detail screen — the artist's top songs
        // become the track list and the discography carousels become the
        // related sections, so the hero, sticky header and row menus all
        // behave identically to a saavn/gaana artist.
        return AlbumLikeBody(
          colors: c,
          id: artist.id,
          title: artist.name,
          imageUrl: artist.artwork,
          eyebrowText: 'ARTIST',
          sub: artist.subtitle,
          description: artist.description,
          songs: artist.topSongs,
          sections: artist.sections,
          showAlbumArtInRow: true,
          sourceRef: DetailRef('artist', artist.id, source: 'youtube'),
          onRadio: artist.hasRadio
              ? () => _startArtistRadio(ref, artist)
              : null,
        );
      },
    );
  }

  /// Materialise the artist's endless station and hand it to the player.
  /// Radio playlists are server-generated, so the queue comes from /next
  /// rather than a browse.
  Future<void> _startArtistRadio(WidgetRef ref, YtArtistDetail artist) async {
    final s = ref.read(appStateProvider);
    s.flashToast('Starting ${artist.name} radio\u2026');
    try {
      final tracks = await ref.read(ytMusicApiProvider).radioQueue(
            videoId: artist.radioVideoId!,
            playlistId: artist.radioPlaylistId!,
          );
      if (tracks.isEmpty) {
        s.flashToast('No station available for ${artist.name}');
        return;
      }
      await s.playApiQueue(tracks, 0,
          sourceLabel: 'RADIO \u00b7 ${artist.name}');
    } catch (e) {
      s.flashToast('Couldn\u2019t start that station');
    }
  }
}

// ── Moods & genres index ───────────────────────────────────────────────────

class YtMoodsScreen extends ConsumerWidget {
  const YtMoodsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final async = ref.watch(ytMusicMoodsProvider);

    return async.when(
      loading: () =>
          _YtScaffold(title: 'Moods & genres', colors: c, children: [_loading(c)]),
      error: (e, _) => _YtScaffold(
        title: 'Moods & genres',
        colors: c,
        children: [_error(c, 'Couldn’t load moods & genres.')],
      ),
      data: (groups) => _YtScaffold(
        title: 'Moods & genres',
        colors: c,
        children: [
          for (final g in groups) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: eyebrow(g.title.toUpperCase(), c.fgMute),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final chip in g.chips)
                    YtCategoryChipTile(chip: chip, colors: c),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One mood/genre pill. YouTube supplies a stripe colour per chip; using it
/// as a left accent keeps a 38-item genre grid scannable instead of a wall
/// of identical pills.
class YtCategoryChipTile extends StatelessWidget {
  const YtCategoryChipTile({
    super.key,
    required this.chip,
    required this.colors,
    this.width,
  });
  final YtCategoryChip chip;
  final SunohColors colors;

  /// Fixed width, used by the home grid so columns line up. Null lets the
  /// tile size to its label (the wrapped index screen).
  final double? width;

  /// Chip height. Shared with [kYtChipRowGap] so the home grid can compute
  /// its own height without guessing.
  static const double height = 44;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final stripe = chip.color == null ? c.accent : Color(chip.color!);
    return GestureDetector(
      onTap: () => context.openYtCategory(
        browseId: chip.browseId,
        params: chip.params,
        name: chip.title,
      ),
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: width,
        height: height,
        decoration: squircleDecoration(
            radius: 12, color: c.surface, borderColor: c.line),
        child: Row(
          mainAxisSize: width == null ? MainAxisSize.min : MainAxisSize.max,
          children: [
            // YouTube ships a stripe colour per category; using it keeps a
            // 49-chip grid scannable instead of a wall of identical pills.
            Container(
              width: 4,
              height: height,
              decoration: BoxDecoration(
                color: stripe,
                borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(12)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                chip.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: SunohType.sans(
                    fontSize: 13, fontWeight: FontWeight.w500, color: c.fg),
              ),
            ),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}

/// Vertical gap between chip rows in the home grid.
const double kYtChipRowGap = 10;

// ── One category ───────────────────────────────────────────────────────────

class YtCategoryScreen extends ConsumerWidget {
  const YtCategoryScreen({
    super.key,
    required this.browseId,
    required this.params,
    this.name,
  });
  final String browseId;
  final String params;
  final String? name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final async = ref
        .watch(ytMusicCategoryProvider((browseId: browseId, params: params)));

    return async.when(
      loading: () =>
          _YtScaffold(title: name ?? 'Browse', colors: c, children: [_loading(c)]),
      error: (e, _) => _YtScaffold(
        title: name ?? 'Browse',
        colors: c,
        children: [_error(c, 'Couldn’t load this category.')],
      ),
      data: (sections) => _YtScaffold(
        title: name ?? 'Browse',
        colors: c,
        children: [
          if (sections.isEmpty) _error(c, 'Nothing here right now.'),
          for (final section in sections) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text(section.heading,
                  style: SunohType.heading(
                      fontSize: 19, color: c.fg, letterSpacing: -0.2)),
            ),
            SizedBox(
              height: 196,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: section.items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final item = section.items[i];
                  return GestureDetector(
                    onTap: () => context.openYtItem(item),
                    behavior: HitTestBehavior.opaque,
                    child: SizedBox(
                      width: 140,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          squircleClip(
                            radius: 14,
                            child: SunohArt(
                              id: item.id,
                              imageUrl: item.artwork,
                              size: 140,
                              radius: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: SunohType.sans(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: c.fg)),
                          if ((item.subtitle ?? '').isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(item.subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: SunohType.sans(
                                    fontSize: 11, color: c.fgMute)),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 26),
          ],
        ],
      ),
    );
  }
}
