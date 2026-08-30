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

import '../api/dto.dart';
import '../api/ytmusic_api.dart';
import '../providers/app_state_provider.dart';
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
    this.subtitle,
  });
  final String title;
  final String? subtitle;
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
            padding: EdgeInsets.fromLTRB(20, 8, 20, subtitle == null ? 20 : 4),
            child: Text(
              title,
              style: SunohType.heading(
                  fontSize: 30,
                  color: c.fg,
                  height: 1.05,
                  letterSpacing: -0.5),
            ),
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Text(subtitle!,
                  style: SunohType.sans(fontSize: 13, color: c.fgMute)),
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
        children: [_error(c, 'Couldn’t load this playlist.')],
      ),
      data: (detail) {
        if (detail == null) {
          return _YtScaffold(
            title: name ?? 'Playlist',
            colors: c,
            children: [_error(c, 'This playlist isn’t available.')],
          );
        }
        final tracks = detail.tracks;
        return _YtScaffold(
          title: detail.title,
          subtitle: detail.subtitle,
          colors: c,
          children: [
            if (detail.artwork != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Center(
                  child: squircleClip(
                    radius: 16,
                    child: SunohArt(
                      id: detail.id,
                      imageUrl: detail.artwork,
                      size: 200,
                      radius: 16,
                    ),
                  ),
                ),
              ),
            if (tracks.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: GestureDetector(
                  onTap: () => s.playApiQueue(
                    tracks,
                    0,
                    sourceLabel: 'YOUTUBE · ${detail.title}',
                  ),
                  child: Container(
                    height: 46,
                    alignment: Alignment.center,
                    decoration: squircleDecoration(
                        radius: 12, color: s.resolvedAccent),
                    child: Text('Play all',
                        style: SunohType.sans(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF0B0B0D))),
                  ),
                ),
              ),
            for (var i = 0; i < tracks.length; i++)
              _YtTrackRow(
                index: i + 1,
                song: tracks[i],
                colors: c,
                onTap: () => s.playApiQueue(
                  tracks,
                  i,
                  sourceLabel: 'YOUTUBE · ${detail.title}',
                ),
              ),
            if (tracks.isEmpty) _error(c, 'No tracks in this playlist.'),
          ],
        );
      },
    );
  }
}

class _YtTrackRow extends StatelessWidget {
  const _YtTrackRow({
    required this.index,
    required this.song,
    required this.colors,
    required this.onTap,
  });
  final int index;
  final FeedItem song;
  final SunohColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 7, 20, 7),
        child: Row(
          children: [
            SizedBox(
              width: 26,
              child: Text('$index'.padLeft(2, '0'),
                  style: SunohType.mono(fontSize: 11, color: c.fgMute)),
            ),
            squircleClip(
              radius: 8,
              child: SunohArt(
                id: song.id,
                imageUrl: song.artwork,
                size: 44,
                radius: 8,
                shadow: false,
              ),
            ),
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
                  if ((song.subtitle ?? '').isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(song.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            SunohType.sans(fontSize: 12, color: c.fgMute)),
                  ],
                ],
              ),
            ),
            if ((song.duration ?? '').isNotEmpty) ...[
              const SizedBox(width: 10),
              Text(_fmt(song.duration!),
                  style: SunohType.mono(fontSize: 11, color: c.fgMute)),
            ],
          ],
        ),
      ),
    );
  }

  static String _fmt(String seconds) {
    final s = int.tryParse(seconds);
    if (s == null) return '';
    final m = s ~/ 60;
    final r = s % 60;
    return '$m:${r.toString().padLeft(2, '0')}';
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
