// Home, search and top-search: the reads that do not hinge on one entity id.
// Port of the matching parts of sunoh-api src/saavn/controller.ts.
import '../local_backend.dart';
import 'client.dart';
import 'config.dart';
import 'controller_shared.dart';
import 'extract.dart';
import 'helper.dart';
import 'mapper.dart';

Future<List<Map<String, Object?>>> getSaavnHomeData([String? languages]) async {
  final r = await saavnFetch({
    '__call': saavnEndpoints.home,
    ...saavnCommonParams,
  }, lang: languages);
  if (r.error != null) {
    throw StateError(
      r.message.isNotEmpty ? r.message : 'Failed to fetch Saavn home data',
    );
  }
  return homeDataMapper(r.data);
}

Future<LocalReply> homeController(
  Map<String, String> params,
  Map<String, String> query,
) async {
  try {
    final data = await getSaavnHomeData(saavnLanguages(query));
    return LocalReply(
      data,
      message: 'Home data fetched successfully',
      source: 'saavn',
    );
  } catch (e) {
    final msg = e is StateError ? e.message : '';
    throw LocalApiError(
      msg.isNotEmpty ? msg : 'Failed to fetch home data',
      error: msg.isNotEmpty ? msg : e.toString(),
    );
  }
}

/// The mapped search payload for [type]: a `{heading, list, source, count}`
/// map for songs/albums/artists/playlists, a section list for `all`.
Object? _mapSearch(String type, Object? data) {
  Map<String, Object?> listOf(String heading, Object? Function(Object?) f) {
    final results = prop(data, 'results');
    if (results is! List) throw StateError('results is not a list');
    // `total` is dropped when Saavn omits it, as JSON.stringify would.
    return clean({
      'heading': heading,
      'list': [for (final d in results) f(d)],
      'source': 'saavn',
      'count': prop(data, 'total'),
    });
  }

  switch (type) {
    case 'albums':
      return listOf('Albums', albumDataMapper);
    case 'songs':
      return listOf('Songs', mapSaavnSong);
    case 'artists':
      return listOf('Artists', artistDataMapper);
    case 'playlists':
      return listOf('Playlists', playlistDataMapper);
    default:
      return autoCompleteDataMapper(data);
  }
}

Map<String, Object?> _searchParams(
  String? q,
  String type,
  int page,
  int count, {
  required String? call,
}) => {
  '__call': call,
  'q': q,
  'query': q,
  'p': page,
  'n': count,
  ...saavnCommonParams,
  'api_version': ['artist', 'all'].contains(type) ? 3 : 4,
};

Future<Object?> getSaavnSearchData(
  String? q, [
  String type = 'all',
  int page = 1,
  int count = 20,
  String? languages,
]) async {
  final r = await saavnFetch(
    _searchParams(
      q,
      type,
      page,
      count,
      call: saavnSearchEndpoints[type] ?? saavnSearchEndpoints['all'],
    ),
    lang: languages,
  );
  if (r.error != null) {
    throw StateError(r.message.isNotEmpty ? r.message : 'Saavn search failed');
  }
  return _mapSearch(type, r.data);
}

Future<LocalReply> searchController(
  Map<String, String> params,
  Map<String, String> query,
) async {
  final q = query['q'];
  final type = (query['type'] ?? 'all').toLowerCase();
  final page = saavnInt(query['page'], 1);
  final count = saavnInt(query['count'], 30);

  final r = await saavnFetch(
    _searchParams(q, type, page, count, call: saavnSearchEndpoints[type]),
    lang: saavnLanguages(query),
  );
  if (r.error != null) throw saavnFail('Search failed', r);

  final Object? data;
  try {
    data = _mapSearch(type, r.data);
  } catch (e) {
    throw LocalApiError('Data mapping error', error: e.toString());
  }
  return LocalReply(data, message: r.message, source: 'saavn');
}

Future<List<Map<String, Object?>>> getSaavnTopSearchData([
  String? languages,
]) async {
  final r = await saavnFetch({
    '__call': saavnSearchEndpoints['top_search'],
    ...saavnCommonParams,
  }, lang: languages);
  if (r.error != null) {
    throw StateError(
      r.message.isNotEmpty ? r.message : 'Saavn top search failed',
    );
  }
  return topSearchMapper(r.data);
}
