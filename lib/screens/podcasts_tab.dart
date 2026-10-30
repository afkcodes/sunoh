// Podcasts tab — country-aware home feed from /podcasts/home.
//
// Drawn with the same tiles, rows and section rhythm as the Music tab (see
// feed_tiles.dart): a show is a cover with its title and author beneath, on
// the 16dp gutter, 30dp between sections. It used to set the title inside
// the cover over a scrim, which made the one tab look like a different app
// and put text over artwork that already carries the show's name.
//
// Country comes from the device locale; the backend has its own
// IP-geo fallback if the locale doesn't carry one.

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remixicon/remixicon.dart';

import '../api/dto.dart';
import '../data/models.dart';
import '../providers/app_state_provider.dart';
import '../providers/podcast_provider.dart';
import '../router/router.dart';
import '../theme/tokens.dart';
import '../widgets/motion.dart';
import '../widgets/ui.dart';
import 'feed_tiles.dart';
import 'podcast_categories_screen.dart' show PodcastCategoryCard;

void _openShow(BuildContext context, FeedItem show) =>
    context.openRef(DetailRef('podcast', show.id, source: show.source));

String? _author(FeedItem show) => show.subtitle;

class PodcastsTab extends ConsumerWidget {
  const PodcastsTab({super.key, required this.colors});
  final SunohColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = colors;
    final country = PlatformDispatcher.instance.locale.countryCode
        ?.toUpperCase();
    final async = ref.watch(podcastHomeProvider(country));

    // Each block enters a step after the one above it. A Column, not a lazy
    // list, so a block is built once and its entrance never replays.
    var block = 0;
    Widget enter(Widget child) => FadeSlideIn(index: block++, child: child);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        enter(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                eyebrow('Podcasts', c.fgMute, size: 10.5, letterSpacing: 0.84),
                SunohChip(
                  label: 'Browse',
                  selected: false,
                  colors: c,
                  icon: RemixIcons.apps_2_line,
                  onTap: () => context.openPodcastCategories(),
                ),
              ],
            ),
          ),
        ),
        if (s.subscribedPodcasts.isNotEmpty)
          enter(
            _Section(
              title: 'Your shows',
              colors: c,
              // Titles only, as this strip always was.
              child: FeedTileRow(
                items: s.subscribedPodcasts,
                colors: c,
                onTap: (show) => _openShow(context, show),
              ),
            ),
          ),
        async.when(
          loading: () => _Skeleton(colors: c),
          error: (e, _) => _ErrorState(colors: c, message: '$e'),
          data: (sections) {
            if (sections.isEmpty) return _Empty(colors: c);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < sections.length; i++) ...[
                  // The first section (typically "Trending in <country>")
                  // takes the wider tile, as the made-for-you row does on
                  // Music, to anchor the page.
                  enter(
                    _Section(
                      title: sections[i].heading,
                      colors: c,
                      child: FeedTileRow(
                        items: sections[i].items,
                        colors: c,
                        width: i == 0 ? kTileWideWidth : kTileWidth,
                        subtitleOf: _author,
                        onTap: (show) => _openShow(context, show),
                      ),
                    ),
                  ),
                  // The categories preview sits between Trending and the
                  // rest — a discovery aid that breaks up the wall of shows.
                  if (i == 0) enter(const _CategoriesPreview()),
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

/// A section: 30dp above, the shared header, then its content.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.colors,
    required this.child,
    this.onSeeAll,
  });
  final String title;
  final SunohColors colors;
  final Widget child;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: title, colors: colors, onSeeAll: onSeeAll),
          child,
        ],
      ),
    );
  }
}

/// Categories preview strip: twelve categories as a horizontally scrolling
/// three-row grid, with "See all" opening the full taxonomy.
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
    // The cards are the categories screen's own, so the preview continues
    // straight into "See all". They carry no artwork, so they stay cards
    // rather than becoming browse tiles.
    const tileW = 180.0;
    const tileH = 64.0;
    const gap = 8.0;
    const rows = 3;
    const totalH = rows * tileH + (rows - 1) * gap;
    return _Section(
      title: 'Categories',
      colors: c,
      onSeeAll: () => context.openPodcastCategories(),
      child: SizedBox(
        height: totalH,
        child: GridView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.colors});
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    Widget row(String title) => _Section(
      title: title,
      colors: c,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < 4; i++) ...[
              if (i > 0) const SizedBox(width: kTileGap),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBar(
                    height: kTileWidth,
                    width: kTileWidth,
                    radius: SunohRadius.tile,
                  ),
                  SizedBox(height: 9),
                  SkeletonBar(height: 13, width: 116, radius: 4),
                  SizedBox(height: 4),
                  SkeletonBar(height: 11, width: 76, radius: 4),
                ],
              ),
            ],
          ],
        ),
      ),
    );
    return Pulse(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [row('Trending'), row('News')],
      ),
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
      padding: const EdgeInsets.fromLTRB(16, 30, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Couldn’t load podcasts.',
            style: SunohType.heading(fontSize: 16, color: c.fgDim),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: SunohType.sans(fontSize: 12, color: c.fgMute, height: 1.4),
          ),
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
      padding: const EdgeInsets.fromLTRB(16, 30, 16, 24),
      child: Text(
        'Nothing here yet.',
        style: SunohType.sans(fontSize: 13, color: c.fgMute),
      ),
    );
  }
}
