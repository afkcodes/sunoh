// Riverpod providers for the cozyaudiobooks.com integration.
//
// Mirrors the shape of `podcast_provider.dart` / `radio_provider.dart`.
//
//   * `audiobookHomeProvider` — multi-section feed for the tab. 1 h
//     keepAlive (matches the backend Redis TTL).
//   * `audiobookCategoriesProvider` — full facet list (24 h keepAlive
//     because the upstream is near-static).
//   * `audiobookSearchProvider(query)` — typed search, 5 min keepAlive.
//   * `audiobooksByCategoryProvider(key)` — skeleton listing for a
//     genre drilldown screen. 1 h keepAlive.
//   * `audiobookDetailProvider(slug)` — full enriched detail incl.
//     chapter list. Drives the detail screen + the lazy-enrichment
//     pass on category-list tiles. 24 h keepAlive so a user scrolling
//     a 50-tile category doesn't burn 50 round-trips on every revisit.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dto.dart';
import 'api_providers.dart';

final audiobookHomeProvider = FutureProvider.autoDispose<List<HomeSection>>((
  ref,
) async {
  final link = ref.keepAlive();
  Future<void>.delayed(const Duration(hours: 1)).then((_) => link.close());
  final api = ref.watch(sunohApiProvider);
  return api.fetchAudiobookHome();
});

final audiobookCategoriesProvider =
    FutureProvider.autoDispose<List<AudiobookCategory>>((ref) async {
      final link = ref.keepAlive();
      Future<void>.delayed(const Duration(hours: 24)).then((_) => link.close());
      final api = ref.watch(sunohApiProvider);
      return api.fetchAudiobookCategories();
    });

final audiobookSearchProvider = FutureProvider.autoDispose
    .family<List<FeedItem>, String>((ref, query) async {
      final link = ref.keepAlive();
      Future<void>.delayed(
        const Duration(minutes: 5),
      ).then((_) => link.close());
      if (query.trim().isEmpty) return const [];
      final api = ref.watch(sunohApiProvider);
      return api.fetchAudiobookSearch(query);
    });

/// Composite key for the per-category listing — `(id, page)` so
/// pagination doesn't collide with the per-category cache.
class AudiobookCategoryKey {
  const AudiobookCategoryKey({
    required this.id,
    this.page = 1,
    this.limit = 50,
  });
  final int id;
  final int page;
  final int limit;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AudiobookCategoryKey &&
          other.id == id &&
          other.page == page &&
          other.limit == limit);

  @override
  int get hashCode => Object.hash(id, page, limit);
}

final audiobooksByCategoryProvider = FutureProvider.autoDispose
    .family<List<FeedItem>, AudiobookCategoryKey>((ref, key) async {
      final link = ref.keepAlive();
      Future<void>.delayed(const Duration(hours: 1)).then((_) => link.close());
      final api = ref.watch(sunohApiProvider);
      return api.fetchAudiobooksByCategory(
        categoryId: key.id,
        page: key.page,
        limit: key.limit,
      );
    });

/// Per-slug detail. Long keepAlive so a user scrolling a category
/// grid doesn't refire the detail fetch on every viewport entry —
/// once it resolves for a slug, it stays warm.
final audiobookDetailProvider = FutureProvider.autoDispose
    .family<AudiobookDetail?, String>((ref, slug) async {
      final link = ref.keepAlive();
      Future<void>.delayed(const Duration(hours: 24)).then((_) => link.close());
      final api = ref.watch(sunohApiProvider);
      return api.fetchAudiobookDetail(slug);
    });
