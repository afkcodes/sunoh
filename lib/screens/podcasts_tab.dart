// Podcasts tab — country-aware home feed from /podcasts/home.
//
// Visually distinct from the music home in two ways:
//   1. Tiles are "labeled cards": a squircle cover sits ON TOP of a
//      separate label block that holds title + author. The seam between
//      the cover and the label gives podcasts a "packaged" feel — a
//      show is a series, not a single track, and the wrapper reinforces
//      that visually. Music tiles stay bare cover + floating text.
//   2. Section headers sit flush against the 20-px gutter — the
//      previous incarnation wrapped `SectionHeader` (which has its own
//      gutter built in) in an outer `Padding(horizontal: 20)` so
//      everything ended up indented 40 px from the edge.
//
// Country comes from the device locale; the backend has its own
// IP-geo fallback if the locale doesn't carry one.

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../api/dto.dart';
import '../data/models.dart';
import '../providers/app_state_provider.dart';
import '../providers/podcast_provider.dart';
import '../router/router.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/ui.dart';
import 'podcast_categories_screen.dart' show PodcastCategoryCard;

class PodcastsTab extends ConsumerWidget {
  const PodcastsTab({super.key, required this.colors});
  final SunohColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = colors;
    final country =
        PlatformDispatcher.instance.locale.countryCode?.toUpperCase();
    final async = ref.watch(podcastHomeProvider(country));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header — eyebrow on the left, Browse-categories chip on the
        // right. Sits in the same 20-px gutter every section header
        // uses, so everything aligns down the tab.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              eyebrow('PODCASTS', c.fgMute, size: 10, letterSpacing: 1.4),
              GestureDetector(
                onTap: () => context.openPodcastCategories(),
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

        if (s.subscribedPodcasts.isNotEmpty) ...[
          _SubscribedStrip(shows: s.subscribedPodcasts, colors: c),
          const SizedBox(height: 28),
        ],

        async.when(
          loading: () => _Skeleton(colors: c),
          error: (e, _) => _ErrorState(colors: c, message: '$e'),
          data: (sections) {
            if (sections.isEmpty) return _Empty(colors: c);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < sections.length; i++) ...[
                  // Mirror music home's "featured" treatment — the
                  // first section (typically "Trending in <country>")
                  // gets larger tiles to anchor the page.
                  _PodcastSection(
                      section: sections[i],
                      colors: c,
                      featured: i == 0),
                  if (i < sections.length - 1) const SizedBox(height: 32),
                  // Drop the categories preview after the featured
                  // (first) section so it sits between Trending and
                  // the rest — discovery aid that breaks up the wall
                  // of show tiles.
                  if (i == 0) ...[
                    const _CategoriesPreview(),
                    const SizedBox(height: 32),
                  ],
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}

class _SubscribedStrip extends StatelessWidget {
  const _SubscribedStrip({required this.shows, required this.colors});
  final List<FeedItem> shows;
  final SunohColors colors;
  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // SectionHeader has its own 20-px horizontal padding baked in.
        SectionHeader(title: 'Your shows', colors: c),
        SizedBox(
          height: 132,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: shows.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final show = shows[i];
              return GestureDetector(
                onTap: () => context.openRef(DetailRef('podcast', show.id,
                    source: show.source)),
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 108,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      squircleClip(
                        radius: 10,
                        child: SunohArt(
                          id: show.id,
                          imageUrl: show.artwork,
                          size: 108,
                          radius: 10,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(show.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SunohType.sans(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: c.fg)),
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
}

/// Categories preview strip. Shows the first 8 categories as a 2-col
/// grid (clipped) with a "See all" CTA opening the full taxonomy.
/// Lives between the featured/trending section and the rest of the
/// home feed.
class _CategoriesPreview extends ConsumerWidget {
  const _CategoriesPreview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final accent = s.resolvedAccent;
    final async = ref.watch(podcastCategoriesProvider);
    final cats = async.asData?.value ?? const [];
    // Only render when categories have actually arrived — until then
    // the section header would look orphaned with nothing beneath.
    if (cats.isEmpty) return const SizedBox.shrink();
    // Pick a small, sane subset to preview. Prefer the headline-style
    // ones the user is most likely to want, fall back to "first N"
    // when those aren't in the dictionary.
    const preferred = [
      'News',
      'Comedy',
      'Society',
      'Education',
      'Technology',
      'Sports',
      'Business',
      'Health',
      'Music',
      'Film',
      'Books',
      'History',
    ];
    final byName = {for (final cat in cats) cat.name: cat};
    final picks = <PodcastCategory>[];
    for (final name in preferred) {
      final cat = byName[name];
      if (cat != null) picks.add(cat);
      if (picks.length == 12) break;
    }
    if (picks.length < 12) {
      for (final cat in cats) {
        if (picks.length == 12) break;
        if (picks.any((p) => p.id == cat.id)) continue;
        picks.add(cat);
      }
    }
    // Match the music home's channel-browse: horizontally-scrolling
    // 3-row grid. Same tile dimensions (180×64) so the discovery
    // surface for podcast categories feels the same shape as the
    // discovery surface for music channels.
    const tileW = 180.0;
    const tileH = 64.0;
    const gap = 10.0;
    const rows = 3;
    final totalH = rows * tileH + (rows - 1) * gap;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Categories',
          colors: c,
          onSeeAll: () => context.openPodcastCategories(),
        ),
        SizedBox(
          height: totalH,
          child: GridView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: rows,
              // In a horizontal GridView, childAspectRatio is
              // cross/main = height/width, not the other way around.
              childAspectRatio: tileH / tileW,
              mainAxisSpacing: gap,
              crossAxisSpacing: gap,
            ),
            itemCount: picks.length,
            itemBuilder: (context, i) => PodcastCategoryCard(
              category: picks[i],
              colors: c,
              accent: accent,
            ),
          ),
        ),
      ],
    );
  }
}

class _PodcastSection extends StatelessWidget {
  const _PodcastSection({
    required this.section,
    required this.colors,
    this.featured = false,
  });
  final HomeSection section;
  final SunohColors colors;
  final bool featured;
  @override
  Widget build(BuildContext context) {
    final c = colors;
    final items = section.items;
    // featured = 220 px tiles (matches music home's first section);
    // standard = 160 px.
    final width = featured ? 220.0 : 160.0;
    final height = featured ? 256.0 : 192.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: section.heading, colors: c),
        SizedBox(
          height: height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, i) => _PodcastTile(
              item: items[i],
              colors: c,
              width: width,
            ),
          ),
        ),
      ],
    );
  }
}

/// Minimal podcast tile — square cover with a bottom gradient overlay
/// carrying the title IN the artwork (Apple Podcasts / Pocket Casts
/// style). Distinct from music's "cover + text below" pattern; no
/// extra surface blocks, no negative-margin tricks.
///
/// The author goes BELOW the cover as a small subdued line so the
/// tile still gives the show a byline without putting it inside the
/// gradient (gradients over busy artwork already strain readability).
class _PodcastTile extends StatelessWidget {
  const _PodcastTile({
    required this.item,
    required this.colors,
    required this.width,
  });
  final FeedItem item;
  final SunohColors colors;
  final double width;
  @override
  Widget build(BuildContext context) {
    final c = colors;
    return GestureDetector(
      onTap: () => context
          .openRef(DetailRef('podcast', item.id, source: item.source)),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            squircleClip(
              radius: 14,
              child: SizedBox(
                width: width,
                height: width,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    SunohArt(
                      id: item.id,
                      imageUrl: item.artwork,
                      size: width,
                      radius: 14,
                    ),
                    // Bottom gradient — opaque-black at the foot, fully
                    // transparent at the top of the gradient zone.
                    // Pure black + alpha is fine here (not a palette
                    // mix), so the "Colors.transparent muddies the
                    // fade" gotcha from the design system doesn't bite.
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 80,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0),
                                Colors.black.withValues(alpha: 0.78),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 10,
                      child: Text(item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: SunohType.sans(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              height: 1.2,
                              letterSpacing: -0.1)),
                    ),
                  ],
                ),
              ),
            ),
            if ((item.subtitle ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(item.subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SunohType.sans(fontSize: 11.5, color: c.fgMute)),
            ],
          ],
        ),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.colors});
  final SunohColors colors;
  @override
  Widget build(BuildContext context) {
    final c = colors;
    Widget row(String title) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(title: title, colors: c),
            SizedBox(
              height: 192,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: 4,
                itemBuilder: (_, _) => Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: SizedBox(
                    width: 152,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 152,
                          height: 152,
                          decoration: squircleDecoration(
                              radius: 14,
                              color: c.surface,
                              borderColor: c.line),
                        ),
                        const SizedBox(height: 10),
                        Container(height: 13, width: 130, color: c.surface),
                        const SizedBox(height: 4),
                        Container(height: 11, width: 90, color: c.surface),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row('Trending'),
        const SizedBox(height: 28),
        row('News'),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.colors, required this.message});
  final SunohColors colors;
  final String message;
  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Couldn’t load podcasts.',
              style: SunohType.heading(fontSize: 16, color: c.fgDim)),
          const SizedBox(height: 6),
          Text(message,
              style: SunohType.sans(
                  fontSize: 12, color: c.fgMute, height: 1.4)),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.colors});
  final SunohColors colors;
  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Text('Nothing here yet.',
          style: SunohType.sans(fontSize: 13, color: c.fgMute)),
    );
  }
}
