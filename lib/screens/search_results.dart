// The results view: the top-result card, a section of results, the
// skeleton shown while the query is in flight, and the nothing-found state.
//
// Split out of `search_screen.dart`, which was 1115 lines. The jump chips
// live with the pinned header (search_header.dart), and the merging of every
// search behind a query in search_outcome.dart.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dto.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';
import 'feed_motion.dart';
import 'feed_row.dart';
import 'feed_tiles.dart';
import 'search_outcome.dart';
import 'search_tiles.dart';

/// Rows a section shows, the top-result card included when it leads one.
const int _kRowsPerSection = 8;

/// The top-result card's own hero scope: its item is also its section's
/// first, and two covers of one item under one tag is an error.
const String _kTopScope = 'search top';

/// A section of results: its heading with the count on the right, then
/// rows. [leadShown] is set on the section whose first item already
/// appears as the top-result card above it.
class ResultsSection extends StatelessWidget {
  const ResultsSection({
    super.key,
    required this.section,
    required this.colors,
    required this.onPlay,
    this.leadShown = false,
  });
  final HomeSection section;
  final SunohColors colors;
  final void Function(FeedItem song) onPlay;
  final bool leadShown;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final skip = leadShown ? 1 : 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 22, 16, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  labelFor(section.heading),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SunohType.heading(fontSize: 17, color: c.fg),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${section.items.length}',
                style: SunohType.mono(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: c.fgDim,
                ),
              ),
            ],
          ),
        ),
        for (final item
            in section.items.skip(skip).take(_kRowsPerSection - skip))
          ResultRow(
            colors: c,
            item: item,
            heroTag: feedHeroTag(section.heading, section.items, item),
            onTap: () => openResult(
              context,
              item,
              sectionSource: section.source,
              onPlay: onPlay,
              hero: feedHeroRef(section.heading, section.items, item, 48),
            ),
          ),
      ],
    );
  }
}

class ResultsSkeleton extends StatelessWidget {
  const ResultsSkeleton({super.key});
  @override
  Widget build(BuildContext context) {
    return Pulse(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: SkeletonBar(
              height: 120,
              width: double.infinity,
              radius: SunohRadius.card,
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 22, 16, 14),
            child: SkeletonBar(height: 17, width: 90, radius: 4),
          ),
          for (var i = 0; i < 5; i++)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  SkeletonBar(height: 48, width: 48, radius: SunohRadius.row),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBar(height: 14, width: 180, radius: 4),
                        SizedBox(height: 6),
                        SkeletonBar(height: 12, width: 120, radius: 4),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The results, as a sliver.
///
/// A sliver rather than a column so the sections build as they are reached.
/// Under the old `SingleChildScrollView` every row of every section — songs,
/// albums, artists, podcasts, three YouTube sections — was laid out the
/// moment the query resolved, whether or not anything was scrolled to.
///
/// The leading section's first item — the API's top result when it marks
/// one, since that section is sorted first — is drawn as the top-result
/// card, and its section continues beneath without it.
///
/// Keyed by query where it is built: each new query is a new State, and so
/// a new entrance for its results.
class SearchResults extends ConsumerStatefulWidget {
  const SearchResults({
    super.key,
    required this.query,
    required this.colors,
    required this.sectionKey,
    required this.onPlay,
  });

  final String query;
  final SunohColors colors;

  /// Keyed so the header's jump chips can find a section on screen.
  final GlobalKey Function(String heading) sectionKey;
  final void Function(FeedItem song) onPlay;

  @override
  ConsumerState<SearchResults> createState() => _SearchResultsState();
}

class _SearchResultsState extends ConsumerState<SearchResults> {
  final _gate = EntranceGate();

  @override
  Widget build(BuildContext context) {
    final query = widget.query;
    final colors = widget.colors;
    // Typed but the debounce hasn't fired — show the same skeleton the
    // request would, so there is no flicker when it does.
    if (query.isEmpty) {
      return const SliverToBoxAdapter(child: ResultsSkeleton());
    }
    final outcome = watchSearch(ref, query);
    if (outcome.loading) {
      return const SliverToBoxAdapter(child: ResultsSkeleton());
    }
    if (outcome.error != null) {
      return SliverToBoxAdapter(
        child: SearchHint(
          colors: colors,
          label: 'Couldn’t reach search. Try again.',
          detail: '${outcome.error}',
        ),
      );
    }
    if (outcome.sections.isEmpty) {
      return SliverToBoxAdapter(
        child: SearchHint(
          colors: colors,
          label: 'Nothing yet.',
          detail: 'No results for “$query”',
        ),
      );
    }

    final sections = outcome.sections;
    return SliverList.builder(
      itemCount: sections.length,
      itemBuilder: (context, i) {
        final section = sections[i];
        final rows = ResultsSection(
          section: section,
          colors: colors,
          onPlay: widget.onPlay,
          leadShown: i == 0,
        );
        return GatedEntrance(
          key: widget.sectionKey(section.heading),
          gate: _gate,
          index: i,
          child: i > 0
              ? rows
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TopResultCard(
                      item: section.items.first,
                      colors: colors,
                      heroTag: feedHeroTag(
                        _kTopScope,
                        section.items,
                        section.items.first,
                      ),
                      onTap: () => openResult(
                        context,
                        section.items.first,
                        sectionSource: section.source,
                        onPlay: widget.onPlay,
                        hero: feedHeroRef(
                          _kTopScope,
                          section.items,
                          section.items.first,
                          kTopResultArt,
                        ),
                      ),
                    ),
                    if (section.items.length > 1) rows,
                  ],
                ),
        );
      },
    );
  }
}

/// Nothing to show: an error, or a query that matched nothing. Set like the
/// prototype's empty state — left-aligned on the gutter, a 22dp title and a
/// line of explanation under it.
class SearchHint extends StatelessWidget {
  const SearchHint({
    super.key,
    required this.colors,
    required this.label,
    this.detail,
  });
  final SunohColors colors;
  final String label;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: SunohType.heading(fontSize: 22, color: c.fg)),
          if (detail != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                detail!,
                style: SunohType.sans(fontSize: 14, color: c.fgDim),
              ),
            ),
        ],
      ),
    );
  }
}
