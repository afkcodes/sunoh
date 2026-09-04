// The rows and tiles the search screen renders: a result row, a trending
// carousel row, and an occasion tile.
//
// Split out of `search_screen.dart`, which was 1115 lines. These three are
// the leaf widgets — they know how to draw one thing and nothing about the
// screen's state.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../api/dto.dart';
import '../data/models.dart';
import '../overlays/track_menu_sheet.dart';
import '../providers/app_state_provider.dart';
import '../router/router.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/ui.dart';

class ResultRow extends StatelessWidget {
  const ResultRow({
    super.key,
    required this.colors,
    required this.item,
    required this.onTap,
  });
  final SunohColors colors;
  final FeedItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final isArtist = item.type == 'artist';
    final isSong = item.type == 'song';
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            SunohArt(
              id: item.id,
              imageUrl: item.artwork,
              size: 42,
              radius: isArtist ? 999 : 4,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SunohType.sans(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: c.fg,
                    ),
                  ),
                  if (_subFor(item).isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      _subFor(item),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SunohType.sans(fontSize: 12, color: c.fgMute),
                    ),
                  ],
                ],
              ),
            ),
            if (isSong)
              GestureDetector(
                onTap: () => showTrackMenuSheet(
                  context,
                  song: item,
                  sourceLabel: 'SEARCH',
                ),
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: Icon(
                    SolarIconsBold.menuDots,
                    size: 18,
                    color: c.fgMute,
                  ),
                ),
              )
            else
              Icon(SolarIconsOutline.altArrowRight, size: 18, color: c.fgMute),
          ],
        ),
      ),
    );
  }

  /// Compact subtitle line — only returns *meaningful* text so the UI can
  /// skip the row entirely when nothing useful is available. Generic type
  /// labels ("Song" / "Album") are deliberately suppressed because saavn
  /// search returns subtitle:null + artists:[] for many songs and showing
  /// the bare word "Song" under every row reads as broken.
  String _subFor(FeedItem item) {
    final fromApi = (item.subtitle ?? '').trim();
    if (fromApi.isNotEmpty) return fromApi;
    final names = (item.artists ?? const [])
        .map((a) => a.name.trim())
        .where((n) => n.isNotEmpty)
        .take(2)
        .toList();
    if (names.isNotEmpty) return names.join(', ');
    return '';
  }
}

class TrendingRow extends ConsumerWidget {
  const TrendingRow({super.key, required this.section, required this.colors});
  final HomeSection section;
  final SunohColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    final s = ref.read(appStateProvider);
    final isArtistRow = section.items.every((it) => it.type == 'artist');
    final width = isArtistRow ? 96.0 : 140.0;
    final gap = isArtistRow ? 18.0 : 12.0;
    final items = section.items.take(10).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: section.heading, colors: c),
        HCardRow<FeedItem>(
          items: items,
          width: width,
          gap: gap,
          onTap: (item) {
            if ((item.source ?? section.source) == 'youtube' &&
                item.type != 'song') {
              context.openYtItem(item);
              return;
            }
            switch (item.type) {
              case 'song':
                // Songs play immediately — tapping a song in a "trending"
                // carousel should never open a song-detail screen.
                s.playApiSong(
                  item,
                  sourceLabel: 'TRENDING · ${section.heading}',
                );
              case 'audiobook':
                context.openAudiobook(item.id, item: item);
              case 'album':
              case 'playlist':
              case 'artist':
              case 'podcast':
                context.openRef(
                  DetailRef(
                    item.type,
                    item.id,
                    source: item.source ?? section.source,
                  ),
                );
              default:
                break;
            }
          },
          builder: (item, w) => isArtistRow
              ? Column(
                  children: [
                    SunohArt(
                      id: item.id,
                      imageUrl: item.artwork,
                      size: w - 10,
                      radius: 999,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      item.title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SunohType.sans(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: c.fg,
                        height: 1.2,
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SunohArt(
                      id: item.id,
                      imageUrl: item.artwork,
                      size: w,
                      radius: 10,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SunohType.sans(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: c.fg,
                        height: 1.2,
                      ),
                    ),
                    if ((item.displaySubtitle ?? '').isNotEmpty) ...[
                      const SizedBox(height: 3),
                      // One line, matching the home shelves: a wrapped
                      // subtitle leaves neighbouring cards at different
                      // heights down the row.
                      eyebrow(
                        item.displaySubtitle!,
                        c.fgMute,
                        size: 10,
                        letterSpacing: 0.8,
                        maxLines: 1,
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class OccasionTile extends StatelessWidget {
  const OccasionTile({super.key, required this.item, required this.colors});
  final FeedItem item;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    final url = item.artwork ?? '';
    return GestureDetector(
      onTap: () => context.openOccasion(item),
      child: squircleClip(
        radius: 14,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Image background — falls back to the painted album-art if no URL.
            SunohArt(id: item.id, imageUrl: url, size: 220, radius: 0),
            // Dark gradient (bottom-up) keeps the title legible regardless
            // of the cover's brightness.
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x00000000),
                      Color(0x66000000),
                      Color(0xCC000000),
                    ],
                    stops: [0.35, 0.75, 1],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 10,
              child: Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: SunohType.heading(
                  fontSize: 15,
                  color: Colors.white,
                  letterSpacing: -0.1,
                  height: 1.1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
