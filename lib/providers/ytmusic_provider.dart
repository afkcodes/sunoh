// Riverpod providers for the YouTube Music integration (pure-Node
// InnerTube port in sunoh-api).
//
// Phase 1 ships search only — `ytmusicSearchProvider(query)`. Stream
// resolution goes through `StreamResolver` (with a dedicated tier for
// `source: 'youtube_music'`), not through a provider, because URLs
// are time-limited and IP-bound — caching beyond the resolver layer
// risks handing back expired URLs.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dto.dart';
import 'api_providers.dart';

/// Typed YouTube Music search. 5-min keepAlive so navigating away +
/// back doesn't re-fetch when the query is unchanged. Mirrors the
/// pattern used by [podcastSearchProvider] / [radioSearchProvider] /
/// [audiobookSearchProvider].
final ytmusicSearchProvider = FutureProvider.autoDispose
    .family<List<FeedItem>, String>((ref, query) async {
  final link = ref.keepAlive();
  Future<void>.delayed(const Duration(minutes: 5)).then((_) => link.close());
  if (query.trim().isEmpty) return const [];
  final api = ref.watch(sunohApiProvider);
  return api.fetchYouTubeMusicSearch(query);
});
