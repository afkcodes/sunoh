// Search-screen Riverpod providers:
//
//   * `searchProvider(query)` — per-query live results (`/music/search?q=…
//     &type=all`). 5 min keepAlive (typed queries turn over fast).
//   * `trendingSearchProvider` — populates the "browse" view's trending
//     carousels when the search box is empty. Matches the RN reference's
//     `useTrendingSearch` (1 hour staleTime).
//   * `occasionsProvider(provider)` — populates the explore-categories
//     grid. 1 hour keepAlive (occasions change rarely).
//
// Debouncing is the SCREEN's job, not the provider's — the family is keyed
// by the debounced query so each distinct active query gets a single
// coalesced inflight + cache entry.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dto.dart';
import 'api_providers.dart';

final searchProvider = FutureProvider.autoDispose
    .family<List<HomeSection>, String>((ref, query) async {
  final link = ref.keepAlive();
  Future<void>.delayed(const Duration(minutes: 5)).then((_) => link.close());
  final api = ref.watch(sunohApiProvider);
  return api.fetchSearch(query);
});

final trendingSearchProvider =
    FutureProvider.autoDispose<List<HomeSection>>((ref) async {
  final link = ref.keepAlive();
  Future<void>.delayed(const Duration(hours: 1)).then((_) => link.close());
  final api = ref.watch(sunohApiProvider);
  return api.fetchTrendingSearch();
});

final occasionsProvider = FutureProvider.autoDispose
    .family<List<FeedItem>, String>((ref, provider) async {
  final link = ref.keepAlive();
  Future<void>.delayed(const Duration(hours: 1)).then((_) => link.close());
  final api = ref.watch(sunohApiProvider);
  return api.fetchOccasions(provider: provider);
});
