// Riverpod providers for the sunoh-radio integration.
//
// Mirrors the shape of `podcast_provider.dart`. Five providers cover
// every Radio surface the app needs today:
//
//   * `radioHomeProvider(country)` — country-aware multi-section feed
//     for the Radio top-tab. 1h keepAlive (matches the backend Redis TTL).
//   * `radioSearchProvider(query)` — typed search, 5m keepAlive.
//   * `radioGenresProvider` — facet list, 24h keepAlive (genres are
//     near-static across the upstream catalog).
//   * `radioCountriesProvider` — same shape, 24h keepAlive.
//   * `radiosByGenreProvider({genre, country})` — per-genre listings
//     for the genre drilldown screen. 1h keepAlive.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dto.dart';
import 'api_providers.dart';

/// `radioHomeProvider(country)` — multi-section feed for the Radio tab.
/// `country` is the ISO-2 device locale; pass null to let the backend
/// auto-detect (CF-IPCountry → Accept-Language → default IN).
final radioHomeProvider = FutureProvider.autoDispose
    .family<List<HomeSection>, String?>((ref, country) async {
  final link = ref.keepAlive();
  Future<void>.delayed(const Duration(hours: 1)).then((_) => link.close());
  final api = ref.watch(sunohApiProvider);
  return api.fetchRadioHome(country: country);
});

/// `radioSearchProvider(query)` — typed search. 5 min keepAlive so
/// navigating away + back doesn't re-fetch when the query is unchanged.
final radioSearchProvider = FutureProvider.autoDispose
    .family<List<FeedItem>, String>((ref, query) async {
  final link = ref.keepAlive();
  Future<void>.delayed(const Duration(minutes: 5)).then((_) => link.close());
  if (query.trim().isEmpty) return const [];
  final api = ref.watch(sunohApiProvider);
  return api.fetchRadioSearch(query);
});

/// `radioGenresProvider` — full genre facet list. Long keepAlive
/// because the upstream catalog's genre taxonomy is near-static.
final radioGenresProvider = FutureProvider.autoDispose<List<RadioFacet>>(
    (ref) async {
  final link = ref.keepAlive();
  Future<void>.delayed(const Duration(hours: 24)).then((_) => link.close());
  final api = ref.watch(sunohApiProvider);
  return api.fetchRadioGenres();
});

/// `radioCountriesProvider` — same shape as genres.
final radioCountriesProvider =
    FutureProvider.autoDispose<List<RadioFacet>>((ref) async {
  final link = ref.keepAlive();
  Future<void>.delayed(const Duration(hours: 24)).then((_) => link.close());
  final api = ref.watch(sunohApiProvider);
  return api.fetchRadioCountries();
});

/// Composite key for the per-genre listing — `(genre, country)` keeps
/// the country-scoped responses separate in the cache so switching
/// countries doesn't show stale per-genre stations.
class RadioGenreKey {
  const RadioGenreKey({required this.genre, this.country});
  final String genre;
  final String? country;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RadioGenreKey &&
          other.genre == genre &&
          other.country == country);

  @override
  int get hashCode => Object.hash(genre, country);
}

/// `radiosByGenreProvider({genre, country})` — per-genre listing.
/// Default limit 50 (server-side max is 100); the screen can paginate
/// by re-calling api.fetchRadioStations directly when needed.
final radiosByGenreProvider = FutureProvider.autoDispose
    .family<List<FeedItem>, RadioGenreKey>((ref, key) async {
  final link = ref.keepAlive();
  Future<void>.delayed(const Duration(hours: 1)).then((_) => link.close());
  final api = ref.watch(sunohApiProvider);
  return api.fetchRadioStations(
    genre: key.genre,
    country: key.country,
    limit: 50,
  );
});
