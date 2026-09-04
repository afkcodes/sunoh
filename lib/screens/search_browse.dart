// The browse view: what Search shows before anything has been typed —
// recent searches, trending carousels and the occasions grid — plus the
// skeletons each of those shows while loading.
//
// Split out of `search_screen.dart`, which was 1115 lines.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../providers/app_state_provider.dart';
import '../providers/search_provider.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';
import 'search_tiles.dart';

class RecentSearches extends StatelessWidget {
  const RecentSearches({
    super.key,
    required this.colors,
    required this.recents,
    required this.onTap,
    required this.onClear,
  });

  final SunohColors colors;
  final List<String> recents;
  final ValueChanged<String> onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Row(
            children: [
              eyebrow('RECENT', c.fgMute),
              const Spacer(),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onClear,
                child: Text(
                  'Clear',
                  style: SunohType.sans(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: c.fgMute,
                  ),
                ),
              ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              for (var i = 0; i < recents.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onTap(recents[i]),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: squircleDecoration(
                      radius: 999,
                      color: c.surface,
                      borderColor: c.line,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          SolarIconsOutline.clockCircle,
                          size: 13,
                          color: c.fgMute,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          recents[i],
                          style: SunohType.sans(fontSize: 13, color: c.fg),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class TrendingSkeleton extends StatelessWidget {
  const TrendingSkeleton({super.key});
  @override
  Widget build(BuildContext context) {
    const tile = 140.0;
    return Pulse(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: SkeletonBar(height: 22, width: 160, radius: 6),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < 4; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  const SizedBox(
                    width: tile,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBar(height: tile, width: tile, radius: 10),
                        SizedBox(height: 8),
                        SkeletonBar(height: 13, width: tile * 0.85, radius: 4),
                        SizedBox(height: 3),
                        SkeletonBar(height: 11, width: tile * 0.55, radius: 4),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }
}

class OccasionsSkeleton extends StatelessWidget {
  const OccasionsSkeleton({super.key});
  @override
  Widget build(BuildContext context) {
    return Pulse(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 171 / 110,
          children: [
            for (var i = 0; i < 6; i++)
              const SkeletonBar(
                height: double.infinity,
                width: double.infinity,
                radius: 14,
              ),
          ],
        ),
      ),
    );
  }
}

/// What Search shows before anything has been typed.
///
/// A sliver group rather than one adapter: the trending carousels are a
/// handful of rows and the occasions grid is another, and building them as
/// they are reached costs nothing over building them together.
class SearchBrowse extends ConsumerWidget {
  const SearchBrowse({
    super.key,
    required this.colors,
    required this.onPickRecent,
  });

  final SunohColors colors;
  final void Function(String query) onPickRecent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    final trending = ref.watch(trendingSearchProvider);
    final occasions = ref.watch(occasionsProvider('gaana'));
    final recents = ref.watch(appStateProvider).searchRecents;

    return SliverMainAxisGroup(
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        if (recents.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 28),
              child: RecentSearches(
                colors: c,
                recents: recents,
                onTap: onPickRecent,
                onClear: () => ref.read(appStateProvider).clearSearchRecents(),
              ),
            ),
          ),
        // Trending — same shape as home, horizontal carousels per section.
        trending.when(
          loading: () => const SliverToBoxAdapter(child: TrendingSkeleton()),
          error: (e, _) => const SliverToBoxAdapter(child: SizedBox.shrink()),
          data: (sections) {
            final nonEmpty = sections.where((s) => s.items.isNotEmpty).toList();
            if (nonEmpty.isEmpty) {
              return const SliverToBoxAdapter(child: SizedBox.shrink());
            }
            return SliverList.builder(
              itemCount: nonEmpty.length,
              itemBuilder: (context, i) => Padding(
                padding: EdgeInsets.only(
                  top: i == 0 ? 0 : 24,
                  bottom: i == nonEmpty.length - 1 ? 28 : 0,
                ),
                child: TrendingRow(section: nonEmpty[i], colors: c),
              ),
            );
          },
        ),
        // Explore Categories — live occasions. Default SectionHeader padding
        // so the header-to-content gap matches the home feed's sections.
        SliverToBoxAdapter(
          child: SectionHeader(title: 'Explore Categories', colors: c),
        ),
        occasions.when(
          loading: () => const SliverToBoxAdapter(child: OccasionsSkeleton()),
          error: (e, _) => const SliverToBoxAdapter(child: SizedBox.shrink()),
          data: (items) {
            if (items.isEmpty) {
              return const SliverToBoxAdapter(child: SizedBox.shrink());
            }
            return SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverGrid.count(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 171 / 110,
                children: [
                  for (final item in items) OccasionTile(item: item, colors: c),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
