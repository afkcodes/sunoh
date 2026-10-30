// The browse view: what Search shows before anything has been typed —
// recent searches, trending carousels and the browse-all grid — plus the
// skeletons each of those shows while loading.
//
// Split out of `search_screen.dart`, which was 1115 lines.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_state_provider.dart';
import '../providers/search_provider.dart';
import '../router/router.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';
import 'feed_motion.dart';
import 'feed_tiles.dart';
import 'search_tiles.dart';

/// Recent searches as rows under a header with "Clear". At most ten — the
/// store caps them — so a plain column.
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
        // SectionHeader's measures with "Clear" where "See all" would be.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  'Recent searches',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SunohType.heading(
                    fontSize: 20,
                    color: c.fg,
                    height: 1.1,
                  ),
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onClear,
                child: Padding(
                  padding: const EdgeInsets.only(left: 12, top: 6),
                  child: Text(
                    'Clear',
                    style: SunohType.sans(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: c.fgDim,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        for (final q in recents)
          RecentRow(query: q, colors: c, onTap: () => onTap(q)),
      ],
    );
  }
}

class TrendingSkeleton extends StatelessWidget {
  const TrendingSkeleton({super.key});
  @override
  Widget build(BuildContext context) {
    return Pulse(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: SkeletonBar(height: 22, width: 160, radius: 6),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < 4; i++) ...[
                  if (i > 0) const SizedBox(width: kTileGap),
                  const SizedBox(
                    width: kTileWidth,
                    child: Column(
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
                  ),
                ],
              ],
            ),
          ),
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
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 175 / BrowseTile.height,
          children: [
            for (var i = 0; i < 6; i++)
              const SkeletonBar(
                height: double.infinity,
                width: double.infinity,
                radius: SunohRadius.card,
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
/// handful of rows and the browse grid is another, and building them as
/// they are reached costs nothing over building them together. Each block
/// is 30dp below the last; the first sits 12dp under the field.
class SearchBrowse extends ConsumerStatefulWidget {
  const SearchBrowse({
    super.key,
    required this.colors,
    required this.onPickRecent,
  });

  final SunohColors colors;
  final void Function(String query) onPickRecent;

  @override
  ConsumerState<SearchBrowse> createState() => _SearchBrowseState();
}

class _SearchBrowseState extends ConsumerState<SearchBrowse> {
  /// A new State each time the browse view comes back from results, so the
  /// view enters again then and not on every scroll back up.
  final _gate = EntranceGate();

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final trending = ref.watch(trendingSearchProvider);
    final occasions = ref.watch(occasionsProvider('gaana'));
    final recents = ref.watch(appStateProvider).searchRecents;
    final lead = recents.isEmpty ? 0 : 1;

    return SliverMainAxisGroup(
      slivers: [
        if (recents.isNotEmpty)
          SliverToBoxAdapter(
            child: GatedEntrance(
              gate: _gate,
              index: 0,
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: RecentSearches(
                  colors: c,
                  recents: recents,
                  onTap: widget.onPickRecent,
                  onClear: () =>
                      ref.read(appStateProvider).clearSearchRecents(),
                ),
              ),
            ),
          ),
        // Trending — the feed's tile rows, one per section.
        trending.when(
          loading: () => SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: lead == 0 ? 12 : 30),
              child: const TrendingSkeleton(),
            ),
          ),
          error: (e, _) => const SliverToBoxAdapter(child: SizedBox.shrink()),
          data: (sections) {
            final nonEmpty = sections.where((s) => s.items.isNotEmpty).toList();
            if (nonEmpty.isEmpty) {
              return const SliverToBoxAdapter(child: SizedBox.shrink());
            }
            return SliverList.builder(
              itemCount: nonEmpty.length,
              itemBuilder: (context, i) => GatedEntrance(
                gate: _gate,
                index: lead + i,
                child: Padding(
                  padding: EdgeInsets.only(top: lead + i == 0 ? 12 : 30),
                  child: TrendingRow(section: nonEmpty[i], colors: c),
                ),
              ),
            );
          },
        ),
        // Browse all — live occasions, as browse tiles two to a row.
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 30),
            child: SectionHeader(title: 'Browse all', colors: c),
          ),
        ),
        occasions.when(
          loading: () => const SliverToBoxAdapter(child: OccasionsSkeleton()),
          error: (e, _) => const SliverToBoxAdapter(child: SizedBox.shrink()),
          data: (items) {
            if (items.isEmpty) {
              return const SliverToBoxAdapter(child: SizedBox.shrink());
            }
            return SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  mainAxisExtent: BrowseTile.height,
                ),
                itemCount: items.length,
                itemBuilder: (context, i) => BrowseTile(
                  item: items[i],
                  onTap: () => context.openOccasion(items[i]),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
