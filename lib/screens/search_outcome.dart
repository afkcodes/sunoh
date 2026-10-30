// What a query turned into: the music search, podcasts and the
// three YouTube Music searches, merged into one ordered list of sections.
//
// Split out of search_results.dart along the data/drawing seam. The pinned
// header's jump chips and the results list both read it.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dto.dart';
import '../providers/podcast_provider.dart';
import '../providers/search_provider.dart';
import '../providers/ytmusic_provider.dart';

/// What one search turned into, once every provider behind it has been
/// merged: music, podcasts and the three YouTube Music searches.
///
/// Read by both the pinned header — which needs the headings to draw its
/// jump chips — and the list below it. Watching the same providers twice
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

  // Podcasts are shaped into HomeSections so the same section renderer draws
  // them; their `type` discriminators already route on tap.
  add('Podcasts', podcasts.asData?.value);
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
