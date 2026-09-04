// The results view: the section-jump pills, a section of results, and the
// skeleton shown while the query is in flight.
//
// Split out of `search_screen.dart`, which was 1115 lines.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dto.dart';
import '../data/models.dart';
import '../providers/audiobook_provider.dart';
import '../providers/podcast_provider.dart';
import '../providers/search_provider.dart';
import '../providers/ytmusic_provider.dart';
import '../router/router.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';
import 'search_tiles.dart';

class SectionPills extends StatelessWidget {
  const SectionPills({
    super.key,
    required this.sections,
    required this.colors,
    required this.onTap,
  });
  final List<HomeSection> sections;
  final SunohColors colors;
  final void Function(String heading) onTap;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: sections.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final s = sections[i];
          final label = _shortLabel(s.heading);
          return GestureDetector(
            onTap: () => onTap(s.heading),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: squircleDecoration(
                radius: 999,
                color: c.surface,
                borderColor: c.line,
              ),
              child: Center(
                child: Text(
                  label,
                  style: SunohType.sans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: c.fg,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Compact display label for a section heading. Most headings come
  /// straight from the upstream API ("Songs", "Artists") and read
  /// fine; the longer / casing-inconsistent ones get normalised.
  static String _shortLabel(String heading) {
    final h = heading.trim();
    final lower = h.toLowerCase();
    if (lower.contains('top result') || lower == 'topquery') return 'Top';
    if (lower.contains('podcast')) return 'Podcasts';
    return h.isEmpty ? '—' : h[0].toUpperCase() + h.substring(1);
  }
}

class ResultsSection extends StatelessWidget {
  const ResultsSection({
    super.key,
    required this.section,
    required this.colors,
    required this.onPlay,
  });
  final HomeSection section;
  final SunohColors colors;
  final void Function(FeedItem song) onPlay;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
          child: eyebrow(section.heading.toUpperCase(), c.fgMute),
        ),
        for (final item in section.items.take(8))
          ResultRow(
            colors: c,
            item: item,
            onTap: () {
              // YouTube ids are browse ids that sunoh-api can't resolve —
              // route them to the YouTube screens instead.
              if ((item.source ?? section.source) == 'youtube' &&
                  item.type != 'song') {
                context.openYtItem(item);
                return;
              }
              switch (item.type) {
                case 'song':
                  onPlay(item);
                case 'audiobook':
                  // Open the book detail screen — chapter list lives
                  // there; tapping a chapter row plays it via the
                  // standard track queue.
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
                  // Unknown type — fall through to a no-op so we don't
                  // route somewhere invalid.
                  break;
              }
            },
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
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: SkeletonBar(height: 11, width: 90, radius: 4),
            ),
            for (var i = 0; i < 6; i++)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    SkeletonBar(height: 42, width: 42, radius: 4),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBar(height: 13, width: 180, radius: 4),
                          SizedBox(height: 6),
                          SkeletonBar(height: 11, width: 120, radius: 4),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// What one search turned into, once every provider behind it has been
/// merged: music, podcasts, audiobooks and the three YouTube Music searches.
///
/// Read by both the pinned header — which needs the headings to draw its
/// jump pills — and the list below it. Watching the same providers twice
/// costs nothing; Riverpod hands back the value it already has.
class SearchOutcome {
  const SearchOutcome({
    required this.loading,
    required this.error,
    required this.sections,
  });

  final bool loading;
  final Object? error;

  /// Non-empty sections, "Top results" first. Empty while loading, on an
  /// error, and when nothing matched — [loading] and [error] tell those apart.
  final List<HomeSection> sections;
}

/// Runs the search and merges everything that answered.
///
/// Only the music search decides loading and error: the others are extras,
/// and either of them failing should cost its own section rather than the
/// whole screen.
SearchOutcome watchSearch(WidgetRef ref, String query) {
  final music = ref.watch(searchProvider(query));
  final podcasts = ref.watch(podcastSearchProvider(query));
  final audiobooks = ref.watch(audiobookSearchProvider(query));
  final ytSongs = ref.watch(ytMusicSearchProvider(query));
  final ytArtists = ref.watch(ytMusicArtistSearchProvider(query));
  final ytAlbums = ref.watch(ytMusicAlbumSearchProvider(query));

  if (music.isLoading) {
    return const SearchOutcome(loading: true, error: null, sections: []);
  }
  if (music.hasError) {
    return SearchOutcome(
      loading: false,
      error: music.error,
      sections: const [],
    );
  }

  final out = [
    ...(music.asData?.value ?? const <HomeSection>[]).where(
      (s) => s.items.isNotEmpty,
    ),
  ];
  void add(String heading, List<FeedItem>? items, {String? source}) {
    if (items == null || items.isEmpty) return;
    out.add(HomeSection(heading: heading, items: items, source: source));
  }

  // Podcasts and audiobooks are shaped into HomeSections so the same section
  // renderer draws them; their `type` discriminators already route on tap.
  add('Podcasts', podcasts.asData?.value);
  add('Audiobooks', audiobooks.asData?.value);
  // These carry source='youtube', which routes them to the native resolver
  // tier on tap. Nothing else about the row needs to know.
  add('YouTube Music', ytSongs.asData?.value, source: 'youtube');
  add('YouTube artists', ytArtists.asData?.value, source: 'youtube');
  add('YouTube albums', ytAlbums.asData?.value, source: 'youtube');

  // "Top results" carries the richest cross-provider matches and is usually
  // what was actually being looked for, so it leads whatever order the API
  // returned in.
  out.sort((a, b) => _topPriority(b.heading) - _topPriority(a.heading));
  return SearchOutcome(loading: false, error: null, sections: out);
}

int _topPriority(String heading) {
  final h = heading.toLowerCase();
  if (h.contains('top result') || h == 'topquery' || h == 'top results') {
    return 100;
  }
  return 0;
}

/// The results, as a sliver.
///
/// A sliver rather than a column so the sections build as they are reached.
/// Under the old `SingleChildScrollView` every row of every section — songs,
/// albums, artists, podcasts, three YouTube sections — was laid out the
/// moment the query resolved, whether or not anything was scrolled to.
class SearchResults extends ConsumerWidget {
  const SearchResults({
    super.key,
    required this.query,
    required this.colors,
    required this.sectionKey,
    required this.onPlay,
  });

  final String query;
  final SunohColors colors;

  /// Keyed so the header's jump pills can find a section on screen.
  final GlobalKey Function(String heading) sectionKey;
  final void Function(FeedItem song) onPlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          label: 'Couldn\u2019t reach search. Try again.',
          detail: '${outcome.error}',
        ),
      );
    }
    if (outcome.sections.isEmpty) {
      return SliverToBoxAdapter(
        child: SearchHint(
          colors: colors,
          label: 'Nothing yet.',
          detail: 'No results for \u201C$query\u201D',
        ),
      );
    }

    final sections = outcome.sections;
    return SliverList.builder(
      itemCount: sections.length,
      itemBuilder: (context, i) => Padding(
        key: sectionKey(sections[i].heading),
        padding: EdgeInsets.only(top: i == 0 ? 4 : 20),
        child: ResultsSection(
          section: sections[i],
          colors: colors,
          onPlay: onPlay,
        ),
      ),
    );
  }
}

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
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 40),
      child: Center(
        child: Column(
          children: [
            Text(label, style: SunohType.heading(fontSize: 22, color: c.fgDim)),
            if (detail != null) ...[
              const SizedBox(height: 8),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: SunohType.sans(fontSize: 13, color: c.fgMute),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
