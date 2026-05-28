// Riverpod providers for the Podcasts surface.
//
//   * `podcastHomeProvider` — multi-section /podcasts/home, 1h keepAlive
//     (matches the backend Redis TTL). Family keyed by country code so
//     `?country=US` and `?country=IN` get separate cache entries; pass
//     `null` to let the backend auto-detect.
//   * `podcastSearchProvider(query)` — typed search, 5m keepAlive.
//     Debouncing is the screen's job.
//   * `podcastShowProvider(id)` — show detail bundled with first 30
//     episodes, 30m keepAlive.
//   * `podcastCategoriesProvider` — 24h keepAlive (categories are
//     stable; ~112 entries).
//   * `podcastsByCategoryProvider(slug)` — per-category browse, 1h keepAlive.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dto.dart';
import 'api_providers.dart';

final podcastHomeProvider = FutureProvider.autoDispose
    .family<List<HomeSection>, String?>((ref, country) async {
  final link = ref.keepAlive();
  Future<void>.delayed(const Duration(hours: 1)).then((_) => link.close());
  final api = ref.watch(sunohApiProvider);
  return api.fetchPodcastHome(country: country);
});

final podcastSearchProvider = FutureProvider.autoDispose
    .family<List<FeedItem>, String>((ref, query) async {
  final link = ref.keepAlive();
  Future<void>.delayed(const Duration(minutes: 5)).then((_) => link.close());
  if (query.trim().isEmpty) return const [];
  final api = ref.watch(sunohApiProvider);
  return api.fetchPodcastSearch(query);
});

final podcastShowProvider = FutureProvider.autoDispose
    .family<PodcastShowDetail, String>((ref, id) async {
  final link = ref.keepAlive();
  Future<void>.delayed(const Duration(minutes: 30)).then((_) => link.close());
  final api = ref.watch(sunohApiProvider);
  return api.fetchPodcastShow(id);
});

final podcastCategoriesProvider =
    FutureProvider.autoDispose<List<PodcastCategory>>((ref) async {
  final link = ref.keepAlive();
  Future<void>.delayed(const Duration(hours: 24)).then((_) => link.close());
  final api = ref.watch(sunohApiProvider);
  return api.fetchPodcastCategories();
});

final podcastsByCategoryProvider = FutureProvider.autoDispose
    .family<List<FeedItem>, String>((ref, slug) async {
  final link = ref.keepAlive();
  Future<void>.delayed(const Duration(hours: 1)).then((_) => link.close());
  final api = ref.watch(sunohApiProvider);
  return api.fetchPodcastsByCategory(slug);
});
