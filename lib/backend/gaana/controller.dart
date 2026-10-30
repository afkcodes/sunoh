// Route controllers for the feed-style Gaana endpoints (home, search,
// collections, occasions, radio shelves). The detail endpoints live in
// detail_controller.dart. Each is `xController(req, res)` in the TS, here
// `(params, query) -> LocalReply`, throwing LocalApiError where the TS called
// sendError.
import '../local_backend.dart';
import 'helper.dart';
import 'http.dart';
import 'mapper.dart';
import 'sections.dart';
import 'util.dart';

const _source = 'gaana';

LocalReply _ok(Object? data) =>
    LocalReply(data, message: 'OK', source: _source);

/// The catch-all every TS route has: any surprise becomes "Internal server
/// error", while deliberate LocalApiErrors pass through unchanged.
Future<LocalReply> guarded(Future<LocalReply> Function() body) async {
  try {
    return await body();
  } on LocalApiError {
    rethrow;
  } on GaanaBlocked {
    // Not a failure of the route: lets the interceptor ask the server.
    rethrow;
  } catch (e) {
    throw LocalApiError('Internal server error', error: '$e');
  }
}

/// For the controllers whose TS catch reports `error.message`.
Future<LocalReply> _guardedWithMessage(
  Future<LocalReply> Function() body,
) async {
  try {
    return await body();
  } on GaanaBlocked {
    rethrow;
  } catch (e) {
    final msg = e is GaanaException ? e.message : '$e';
    throw LocalApiError(
      msg.isNotEmpty ? msg : 'Internal server error',
      error: '$e',
    );
  }
}

Future<LocalReply> radioStationsController(
  Map<String, String> params,
  Map<String, String> query,
) => _guardedWithMessage(
  () async => _ok(await getGaanaRadioStations(query['lang'])),
);

Future<LocalReply> homeController(
  Map<String, String> params,
  Map<String, String> query,
) =>
    _guardedWithMessage(() async => _ok(await getGaanaHomeData(query['lang'])));

Future<LocalReply> collectionController(
  Map<String, String> params,
  Map<String, String> query,
) => guarded(() async {
  final r = await gaanaFetch({
    'type': 'collectionsDetail',
    'seokey': params['seokey'],
    'page': query['page'] ?? 0,
  }, languages: query['lang']);
  if (r.error != null) {
    throw LocalApiError(
      failureText(r, 'Failed to fetch collection'),
      error: r.error,
    );
  }
  final entities = get(r.data, 'entities');
  return _ok([
    for (final e in (truthy(entities) ? entities as List : const []))
      mapGaanaEntity(e),
  ]);
});

Future<LocalReply> albumListController(
  Map<String, String> params,
  Map<String, String> query,
) => guarded(() async {
  final lang = query['lang'];
  final language = or(or(query['language'], lang), 'hindi');
  final r = await gaanaFetch({
    'type': 'albumList',
    'language': language,
    'page': query['page'] ?? 0,
  }, languages: lang);
  if (r.error != null) {
    throw LocalApiError(
      failureText(r, 'Failed to fetch albums'),
      error: r.error,
    );
  }
  final albums = get(r.data, 'album');
  return _ok([
    for (final a in (truthy(albums) ? albums as List : const []))
      mapGaanaEntity({...(a as Map), 'entity_type': 'ALBUM'}),
  ]);
});

Future<LocalReply> searchController(
  Map<String, String> params,
  Map<String, String> query,
) => guarded(() async {
  final q = or(query['q'], query['query']);
  if (!truthy(q)) {
    throw LocalApiError('Query parameter q is required', code: 400);
  }
  final r = await gaanaFetch({
    'type': 'search',
    'keyword': q,
  }, languages: query['lang']);
  if (r.error != null) {
    throw LocalApiError(failureText(r, 'Search failed'), error: r.error);
  }
  return _ok(gaanaSearchMapper(r.data));
});

Future<LocalReply> _entityListFrom(
  String url,
  String? lang,
  String failure,
) async {
  final r = await fetchGet(url, languages: lang);
  if (r.error != null) {
    throw LocalApiError(failureText(r, failure), error: r.error);
  }
  final entities = get(r.data, 'entities');
  if (r.data == null) throw StateError('empty reply');
  return _ok([
    for (final e in (truthy(entities) ? entities as List : const []))
      mapGaanaEntity(e),
  ]);
}

Future<LocalReply> occasionController(
  Map<String, String> params,
  Map<String, String> query,
) => guarded(
  () => _entityListFrom(
    'https://apiv2.gaana.com/home/discover/category-listing/178?new_artwork=1&v=1',
    query['lang'],
    'Failed to fetch occasions',
  ),
);

Future<LocalReply> occasionDetailController(
  Map<String, String> params,
  Map<String, String> query,
) => guarded(() async {
  final lang = query['lang'];
  final r = await fetchGet(
    'https://apiv2.gaana.com/home/occasion/metadata/${params['slug']}',
    languages: lang,
  );
  if (r.error != null) {
    throw LocalApiError(
      failureText(r, 'Failed to fetch occasion detail'),
      error: r.error,
    );
  }
  final data = r.data as Map;
  return _ok(
    await hydrateGaanaSections(gaanaSectionMapper(data['occasion']), lang),
  );
});

Future<LocalReply> occasionItemsController(
  Map<String, String> params,
  Map<String, String> query,
) => guarded(
  () => _entityListFrom(
    'https://apiv2.gaana.com/home/discover/category/${params['id']}'
        '?limit=${query['limit'] ?? '0,40'}',
    query['lang'],
    'Failed to fetch occasion items',
  ),
);
