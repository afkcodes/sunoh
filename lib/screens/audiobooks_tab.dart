// Audiobooks tab — multi-section feed from /audiobooks/home.
//
// Visually shares language with the podcasts tab: a top-of-tab
// header strip (eyebrow + "Browse" chip), then a stream of horizontal
// strips of squircle tiles. Two tile kinds:
//   - audiobook tile (cover + title + author)
//   - audiobook_category tile (chip with name + count)
//
// Backend serves enriched data (cover + author scraped per book during
// home aggregation) so cold tab open is one round-trip; cache means
// subsequent opens are instant.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../api/dto.dart';
import '../providers/audiobook_provider.dart';
import '../router/router.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/ui.dart';
import 'audiobook_categories_screen.dart' show AudiobookCategoryCard;

class AudiobooksTab extends ConsumerWidget {
  const AudiobooksTab({super.key, required this.colors});
  final SunohColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    final async = ref.watch(audiobookHomeProvider);

    // Tab root is a plain Column — the parent _RootScroll handles
    // scrolling for this whole branch. Using Expanded + ListView here
    // (as a sibling of the heading row) would force a Flex parent and
    // collapse the list to 0 px height inside the SingleChildScrollView
    // wrapper → blank tab. PodcastsTab follows the same
    // straight-children pattern.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              eyebrow('AUDIOBOOKS', c.fgMute, size: 10, letterSpacing: 1.4),
              GestureDetector(
                onTap: () => context.openAudiobookCategories(),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: squircleDecoration(
                    radius: 999,
                    color: c.surface,
                    borderColor: c.line,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(SolarIconsOutline.widget,
                          size: 12, color: c.fgDim),
                      const SizedBox(width: 6),
                      Text('Browse',
                          style: SunohType.sans(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: c.fgDim)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        async.when(
          data: (sections) {
            if (sections.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 48),
                child: Center(
                  child: Text('No audiobooks yet',
                      style: SunohType.sans(fontSize: 13, color: c.fgMute)),
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < sections.length; i++) ...[
                  // Mirror music + podcasts home: the first section
                  // (always "Latest additions") gets the featured
                  // treatment with bigger tiles, the rest are standard
                  // size. Keeps the visual rhythm consistent across
                  // tabs.
                  _AudiobookSection(
                    section: sections[i],
                    colors: c,
                    featured: i == 0,
                  ),
                  if (i < sections.length - 1)
                    const SizedBox(height: 32),
                ],
                const SizedBox(height: 24),
              ],
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(
                'Couldn’t load audiobooks. Try again later.',
                textAlign: TextAlign.center,
                style: SunohType.sans(fontSize: 13, color: c.fgMute),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One horizontal strip — SectionHeader (shared with music + podcasts
/// so the title styling is consistent across tabs) + a scrolling
/// row of tiles. The chip strip ("Browse genres") is a special case:
/// renders short chip rows instead of cover tiles.
class _AudiobookSection extends StatelessWidget {
  const _AudiobookSection({
    required this.section,
    required this.colors,
    this.featured = false,
  });
  final HomeSection section;
  final SunohColors colors;
  /// First section on the tab gets the featured treatment — bigger
  /// covers to anchor the page. Matches music/podcast home.
  final bool featured;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final items = section.items;
    if (items.isEmpty) return const SizedBox.shrink();
    final isCategoryStrip = items.first.type == 'audiobook_category';

    // Category preview reuses the same 3-row horizontal grid of
    // gradient cards as PodcastsTab._CategoriesPreview — keeps the
    // "Browse genres" surface visually identical across tabs and lines
    // up with what the user sees when they tap "See all" into the full
    // genres screen (also gradient cards).
    if (isCategoryStrip) {
      return _AudiobookCategoryPreview(
        items: items,
        colors: c,
      );
    }

    // Book strips: featured 220, standard 160 — same dimensions music +
    // podcast home strips use.
    final tileWidth = featured ? 220.0 : 160.0;
    final stripHeight = featured ? 296.0 : 232.0;
    final gap = featured ? 14.0 : 12.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: section.heading, colors: c),
        SizedBox(
          height: stripHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: items.length,
            separatorBuilder: (_, _) => SizedBox(width: gap),
            itemBuilder: (ctx, i) => _AudiobookTile(
              item: items[i],
              colors: c,
              width: tileWidth,
              featured: featured,
            ),
          ),
        ),
      ],
    );
  }
}

/// 3-row horizontal grid of gradient category cards — clone of
/// PodcastsTab._CategoriesPreview so the "Browse genres" preview reads
/// identically across the two tabs. Each tile uses the same
/// `AudiobookCategoryCard` the full Genres screen uses, so the visual
/// continues straight through if the user taps "See all".
class _AudiobookCategoryPreview extends StatelessWidget {
  const _AudiobookCategoryPreview({
    required this.items,
    required this.colors,
  });
  final List<FeedItem> items;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    const tileW = 180.0;
    const tileH = 64.0;
    const gap = 10.0;
    const rows = 3;
    final totalH = rows * tileH + (rows - 1) * gap;
    // Build lightweight AudiobookCategory shims from the home payload
    // so AudiobookCategoryCard doesn't have to learn a second shape.
    final cats = [
      for (final it in items)
        AudiobookCategory(
          id: int.tryParse(it.id) ?? 0,
          name: it.title,
          slug: it.id,
          count: 0,
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Genres',
          colors: c,
          onSeeAll: () => context.openAudiobookCategories(),
        ),
        SizedBox(
          height: totalH,
          child: GridView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: rows,
              // Horizontal GridView: childAspectRatio = height/width.
              childAspectRatio: tileH / tileW,
              mainAxisSpacing: gap,
              crossAxisSpacing: gap,
            ),
            itemCount: cats.length,
            itemBuilder: (context, i) =>
                AudiobookCategoryCard(category: cats[i], colors: c),
          ),
        ),
      ],
    );
  }
}

/// Cover + title + author. Width passed in so featured / standard
/// strips can use the same widget at different sizes — matches the
/// pattern used by music + podcast home.
class _AudiobookTile extends StatelessWidget {
  const _AudiobookTile({
    required this.item,
    required this.colors,
    required this.width,
    this.featured = false,
  });
  final FeedItem item;
  final SunohColors colors;
  final double width;
  final bool featured;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return GestureDetector(
      onTap: () => context.openAudiobook(item.id, item: item),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            squircleClip(
              radius: featured ? 16 : 14,
              child: SunohArt(
                id: item.id,
                imageUrl: item.artwork,
                size: width,
                radius: featured ? 16 : 14,
              ),
            ),
            SizedBox(height: featured ? 10 : 8),
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: SunohType.sans(
                fontSize: featured ? 14 : 13,
                fontWeight: FontWeight.w600,
                color: c.fg,
                height: 1.2,
              ),
            ),
            if ((item.subtitle ?? '').isNotEmpty) ...[
              SizedBox(height: featured ? 4 : 2),
              Text(
                item.subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SunohType.sans(
                  fontSize: featured ? 12.5 : 11.5,
                  color: c.fgMute,
                  height: 1.2,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

