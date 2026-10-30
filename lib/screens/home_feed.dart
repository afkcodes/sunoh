// Home's Music tab: the live /music/home feed with the YouTube Music rows
// woven in, the moods strip, and the loading and error states.
//
// Split out of home_screen.dart (954 lines). The screen owns the header and
// the scrolling; this owns what the feed is made of. How a single section is
// drawn lives in home_section.dart.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dto.dart';
import '../api/ytmusic_api.dart' show YtCategoryChip;
import '../providers/app_state_provider.dart';
import '../providers/home_provider.dart';
import '../providers/ytmusic_provider.dart';
import '../router/router.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';
import 'feed_motion.dart';
import 'feed_tiles.dart';
import 'home_section.dart';
import 'yt_moods_screens.dart' show YtCategoryChipTile, kYtChipRowGap;

/// How many primary-feed sections to show between each interleaved
/// YouTube Music row. 3 keeps sunoh's own feed dominant while surfacing the
/// YouTube rows well before the user hits the bottom.
const int _kYtInterleaveEvery = 3;

/// Weave [secondary] sections into [primary], one after every [everyN]
/// primary sections. Leftover secondary sections are appended.
///
/// Slot 0 is never taken: the first section gets the featured treatment and
/// should stay sunoh's own.
List<HomeSection> _interleave({
  required List<HomeSection> primary,
  required List<HomeSection> secondary,
  required int everyN,
}) {
  if (secondary.isEmpty) return primary;
  if (primary.isEmpty) return secondary;

  final out = <HomeSection>[];
  final queue = [...secondary];
  for (var i = 0; i < primary.length; i++) {
    out.add(primary[i]);
    final placed = i + 1;
    if (placed % everyN == 0 && queue.isNotEmpty) {
      out.add(queue.removeAt(0));
    }
  }
  out.addAll(queue);
  return out;
}

class MusicTab extends ConsumerStatefulWidget {
  const MusicTab({super.key, required this.colors});
  final SunohColors colors;

  @override
  ConsumerState<MusicTab> createState() => _MusicTabState();
}

class _MusicTabState extends ConsumerState<MusicTab> {
  /// The feed's entrance plays once per visit to the tab. A new State comes
  /// with each switch back to Music, and with it a new gate.
  final _gate = EntranceGate();

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final (languages, density) = ref.watch(
      appStateProvider.select((s) => (s.selectedLanguagesCsv, s.density)),
    );
    final feedAsync = ref.watch(homeFeedProvider(languages));
    final gap = 30 * density.scale;

    return feedAsync.when(
      loading: () => const SliverToBoxAdapter(child: _LoadingFeed()),
      error: (e, _) => SliverToBoxAdapter(
        child: _ErrorFeed(
          message: 'Couldn’t load the home feed.',
          detail: '$e',
          onRetry: () => ref.invalidate(homeFeedProvider(languages)),
          colors: c,
        ),
      ),
      data: (sections) {
        final nonEmpty = sections.where((s) => s.items.isNotEmpty).toList();
        if (nonEmpty.isEmpty) {
          return SliverToBoxAdapter(
            child: _ErrorFeed(
              message: 'Nothing in the feed right now.',
              colors: c,
              onRetry: () => ref.invalidate(homeFeedProvider(languages)),
            ),
          );
        }
        // YouTube Music rows. Watched separately (not awaited alongside the
        // main feed) so a slow or failing InnerTube response never holds up
        // or breaks the home screen — the rows simply aren't there.
        final ytSections =
            ref.watch(ytMusicHomeProvider).asData?.value ??
            const <HomeSection>[];
        final ytNonEmpty = ytSections.where((s) => s.items.isNotEmpty).toList();

        // Interleave rather than append. Bolting them on the end buries them
        // below a long feed, and makes the tail read as a separate app. The
        // first slot is deliberately left to sunoh's own featured section.
        final merged = _interleave(
          primary: nonEmpty,
          secondary: ytNonEmpty,
          everyN: _kYtInterleaveEvery,
        );

        // Widget instances, not built widgets. Constructing twenty-odd of
        // these is nothing; it is their build methods — each resolving a
        // strip of artwork — that cost, and the delegate below only calls
        // those for rows actually on screen.
        final rows = <Widget>[];
        var wideUsed = false;
        for (var i = 0; i < merged.length; i++) {
          // The first all-playlist row after the hero is the made-for-you
          // shape and gets the wider tile; one per feed, or it stops
          // meaning anything.
          final wide = i > 0 && !wideUsed && isPlaylistRow(merged[i]);
          wideUsed |= wide;
          rows.add(
            Padding(
              // The hero sits 6dp under the tab chips, as in the prototype;
              // every later section is 30dp below the one before.
              padding: EdgeInsets.only(top: i == 0 ? 6 : gap),
              child: HomeFeedSection(
                section: merged[i],
                colors: c,
                featured: i == 0,
                wide: wide,
              ),
            ),
          );
          // Moods & genres sits after the first couple of rows — high enough
          // to be discoverable, not so high it displaces the feed.
          if (i == 1) {
            rows.add(
              Padding(
                padding: EdgeInsets.only(top: gap),
                child: _MoodsRow(colors: c),
              ),
            );
          }
        }

        return SliverList.builder(
          itemCount: rows.length,
          itemBuilder: (_, i) =>
              GatedEntrance(gate: _gate, index: i, child: rows[i]),
        );
      },
    );
  }
}

/// Horizontal strip of YouTube Music mood/genre chips, with a "See all"
/// into the full index. Renders nothing until the chips load, so a slow or
/// failed fetch just leaves the feed as it was.
class _MoodsRow extends ConsumerWidget {
  const _MoodsRow({required this.colors});
  final SunohColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    final groups = ref.watch(ytMusicMoodsProvider).asData?.value;
    if (groups == null || groups.isEmpty) return const SizedBox.shrink();

    // Flatten across grids ("Moods & moments" then "Genres") and take a
    // sample — the full 49 chips live behind See all.
    final chips = [for (final g in groups) ...g.chips].take(21).toList();
    if (chips.isEmpty) return const SizedBox.shrink();

    // Lay out as a horizontally-scrolling grid of `rows` stacked chips
    // rather than one long line: three short rows fit far more categories
    // in the same vertical space and read as a browsable block instead of
    // an endless strip. Falls back to fewer rows when there aren't enough
    // chips to fill them.
    final rows = chips.length >= 9 ? 3 : (chips.length >= 4 ? 2 : 1);
    final columns = <List<YtCategoryChip>>[];
    for (var i = 0; i < chips.length; i += rows) {
      columns.add(chips.sublist(i, (i + rows).clamp(0, chips.length)));
    }
    final gridHeight =
        YtCategoryChipTile.height * rows + kYtChipRowGap * (rows - 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Moods & genres',
          colors: c,
          onSeeAll: () => context.openYtMoods(),
        ),
        SizedBox(
          height: gridHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: columns.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, col) {
              final cells = columns[col];
              return Column(
                children: [
                  for (var r = 0; r < rows; r++) ...[
                    if (r > 0) const SizedBox(height: kYtChipRowGap),
                    // Short trailing columns keep their slots so the grid
                    // stays rectangular instead of ragged at the edge.
                    if (r < cells.length)
                      YtCategoryChipTile(chip: cells[r], colors: c, width: 148)
                    else
                      const SizedBox(
                        width: 148,
                        height: YtCategoryChipTile.height,
                      ),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

// Skeleton placeholder for the feed — the hero cards and two rows of covers,
// at the sizes the real ones arrive at, pulsing so the wait reads as
// intentional rather than stuck.
class _LoadingFeed extends StatelessWidget {
  const _LoadingFeed();

  @override
  Widget build(BuildContext context) {
    final card = MediaQuery.sizeOf(context).width - 58;
    return Pulse(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 6, 16, 14),
            child: SkeletonBar(height: 22, width: 180, radius: 6),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                SkeletonBar(height: 212, width: card, radius: SunohRadius.card),
                const SizedBox(width: 10),
                SkeletonBar(height: 212, width: card, radius: SunohRadius.card),
              ],
            ),
          ),
          const SizedBox(height: 30),
          const _SkeletonRow(),
          const SizedBox(height: 30),
          const _SkeletonRow(),
        ],
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    return Column(
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
    );
  }
}

class _ErrorFeed extends StatelessWidget {
  const _ErrorFeed({
    required this.message,
    required this.colors,
    required this.onRetry,
    this.detail,
  });
  final String message;
  final String? detail;
  final SunohColors colors;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 80, 16, 80),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: SunohType.heading(fontSize: 18, color: c.fg),
          ),
          if (detail != null) ...[
            const SizedBox(height: 8),
            Text(
              detail!,
              textAlign: TextAlign.center,
              style: SunohType.sans(fontSize: 12, color: c.fgMute),
            ),
          ],
          const SizedBox(height: 20),
          SunohChip(
            label: 'Try again',
            selected: false,
            colors: c,
            onTap: onRetry,
          ),
        ],
      ),
    );
  }
}
