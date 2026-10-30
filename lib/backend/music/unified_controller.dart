// Unified home, search and recommend (port of the same-named controllers in
// sunoh-api src/music/controller.ts). Fetching lives here, merging in
// home_merge.dart / search_merge.dart.
import '../common.dart';
import '../gaana/gaana.dart' as gaana;
import '../gaana/util.dart' show get, or;
import '../local_backend.dart';
import '../saavn/saavn.dart' as saavn;
import 'home_merge.dart';
import 'search_merge.dart';
import 'shared.dart';

String? _languages(Map<String, String> query) =>
    firstNonEmpty([query['lang'], query['languages']]);

Future<LocalReply> unifiedHomeController(
  Map<String, String> params,
  Map<String, String> query,
) => unifiedGuard('Failed to fetch unified home data', () async {
  // Both providers start together; a failed one just contributes nothing.
  var blocked = false;
  final saavnF = settle(saavn.getSaavnHomeData(_languages(query)));
  final gaanaF = settle(
    gaana.getGaanaHomeData(query['lang']),
    onBlocked: () => blocked = true,
  );
  final saavnData = await saavnF ?? const [];
  final gaanaData = await gaanaF ?? const [];
  // Gaana banned this phone: the server's merge also tolerates a failed
  // provider, so Saavn's half is a valid answer. With nothing from Saavn
  // either, let the server answer instead of showing an empty home. The
  // partial flag keeps the cache from pinning the Gaana-less feed.
  if (blocked && saavnData.isEmpty) throw const gaana.GaanaBlocked();
  return unified(
    mergeHomeSections(saavnData, gaanaData),
    'Unified home data fetched successfully',
    partial: blocked,
  );
});

Future<LocalReply> unifiedSearchController(
  Map<String, String> params,
  Map<String, String> query,
) => unifiedGuard('Unified search failed', () async {
  final q = firstNonEmpty([query['q'], query['query']]) ?? '';
  final lang = query['lang'];
  final type = query['type'] ?? 'all';
  final page = int.tryParse(query['page'] ?? '') ?? 1;
  final count = int.tryParse(query['count'] ?? '') ?? 20;
  final languages = _languages(query);

  if (q.isEmpty) {
    var blocked = false;
    final topF = settle(saavn.getSaavnTopSearchData(languages));
    final trendF = settle(
      gaana.getGaanaTrendingSearchData(lang),
      onBlocked: () => blocked = true,
    );
    final shelves = List<Object?>.of(await topF ?? const []);
    final trending = [
      for (final i in await trendF ?? const [])
        if (isValidTitle(or(get(i, 'title'), get(i, 'name')))) i,
    ];
    if (trending.isNotEmpty) {
      shelves.insert(0, {
        'heading': 'Trending on Gaana',
        'data': trending,
        'source': 'gaana',
      });
    }
    // Trending is one optional shelf; without it the Saavn shelves stand.
    if (blocked && shelves.isEmpty) throw const gaana.GaanaBlocked();
    return unified(
      shelves,
      'Top search results fetched successfully',
      partial: blocked,
    );
  }

  var blocked = false;
  final saavnF = settle(
    saavn.getSaavnSearchData(q, type, page, count, languages),
  );
  final gaanaF = settle(
    gaana.getGaanaSearchData(q, lang),
    onBlocked: () => blocked = true,
  );
  final saavnResults = await saavnF;
  final gaanaResults = await gaanaF ?? const [];
  // Same reasoning as home: Saavn alone is what the server returns when
  // Gaana fails. If Saavn failed too there is nothing to show, so ask the
  // server rather than return an empty list.
  if (blocked && saavnResults == null) throw const gaana.GaanaBlocked();
  return unified(
    mergeSearchResults(saavnResults ?? <Object?>[], gaanaResults, type),
    'Search results fetched successfully',
    partial: blocked,
  );
});

Future<LocalReply> unifiedRecommendController(
  Map<String, String> params,
  Map<String, String> query,
) => unifiedGuard('Failed to fetch recommendations', () async {
  final searchQuery = firstNonEmpty([query['q'], query['query']]);
  final languages = _languages(query);
  var songId = firstNonEmpty([params['songId'], query['songId']]);

  // No id but a text query: take Saavn's best song match as the seed.
  if (songId == null && searchQuery != null) {
    final found = await saavn.getSaavnSearchData(
      searchQuery,
      'songs',
      1,
      1,
      languages,
    );
    final list = found is Map ? found['list'] : null;
    if (list is List && list.isNotEmpty && list.first is Map) {
      final id = (list.first as Map)['id'];
      if (id != null) songId = '$id';
    }
  }
  if (songId == null) {
    throw LocalApiError('Could not identify a song for recommendations');
  }
  final data = await saavn.getSaavnSongRecommendData(songId, languages);
  return unified(data, 'Recommendations fetched successfully');
});
