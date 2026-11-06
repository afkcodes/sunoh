// Home, radio-shelf, search and trending data functions, plus the section
// hydration they share (src/gaana/controller.ts, the non-route half).
import '../common.dart' show isValidTitle, promiseAllLimit;
import 'helper.dart';
import 'http.dart';
import 'mapper.dart';
import 'util.dart';

/// Thrown where the TS threw `new Error(message)`; controllers turn it into
/// the failure envelope with the same text.
class GaanaException implements Exception {
  GaanaException(this.message);
  final String message;
  @override
  String toString() => message;
}

String failureText(GaanaResult r, String fallback) =>
    r.message.isNotEmpty ? r.message : fallback;

List<Object?> _validEntities(Object? entities) => [
  for (final e in (entities as List))
    if (_titled(mapGaanaEntity(e))) mapGaanaEntity(e),
];

bool _titled(Object? m) => isValidTitle(or(get(m, 'title'), get(m, 'name')));

Json _section(Object? heading, List<Object?> data) => {
  'heading': heading,
  'data': data,
  'source': 'gaana',
};

/// Turns section metadata (heading + a url / seokey / inline entities) into
/// populated shelves. A shelf that fails to load is skipped, never fatal:
/// one dead Gaana endpoint must not blank the whole home screen.
Future<List<Json>> hydrateGaanaSections(
  List<Json> sectionMetadata,
  String? lang,
) async {
  const excluded = ['Plan Upgrade', 'One Month Trial'];
  final relevant = sectionMetadata.where((s) {
    final h = s['heading'];
    if (!truthy(h)) return false;
    if (excluded.contains(h)) return false;
    final url = s['url'];
    if (url is String && url.contains('gaanaplusservice')) return false;
    return truthy(url) ||
        truthy(s['seokey']) ||
        (s['entities'] is List && (s['entities'] as List).isNotEmpty);
  }).toList();

  const timeout = Duration(seconds: 5);
  final populated = await promiseAllLimit<Json, Json?>(relevant, 5, (s) async {
    final entities = s['entities'];
    if (entities is List && entities.isNotEmpty) {
      return _section(s['heading'], _validEntities(entities));
    }

    if (truthy(s['seokey'])) {
      final r = await gaanaFetch(
        {'type': 'collectionsDetail', 'seokey': s['seokey'], 'page': 0},
        languages: lang,
        timeout: timeout,
      );
      final list = get(r.data, 'entities');
      if (r.error == null && truthy(list)) {
        try {
          return _section(s['heading'], _validEntities(list));
        } catch (_) {
          // Malformed shelf: fall through to the url path like a failed fetch.
        }
      }
    }

    final url = s['url'];
    if (url is! String || url.isEmpty) return null;
    final isPublic =
        url.startsWith('https://apiv2.gaana.com') ||
        url.startsWith('https://api.gaana.com');
    // Direct GET for discovery/occasion URLs; the apiv2 proxy mangles them.
    final r = (url.startsWith('http') && isPublic)
        ? await fetchGet(url, languages: lang, timeout: timeout)
        : await gaanaFetch(
            {'apiPath': url, 'type': 'homeSec'},
            languages: lang,
            timeout: timeout,
          );
    final list = get(r.data, 'entities');
    if (r.error == null && truthy(list)) {
      try {
        return _section(s['heading'], _validEntities(list));
      } catch (_) {
        return null;
      }
    }
    return null;
  });

  return [
    for (final s in populated)
      if (s != null && (s['data'] as List).isNotEmpty) s,
  ];
}

Future<List<Json>> getGaanaHomeData([String? lang]) async {
  final r = await gaanaFetch({'type': 'home'}, languages: lang);
  if (r.error != null) {
    throw GaanaException(failureText(r, 'Failed to fetch Gaana home'));
  }
  return hydrateGaanaSections(gaanaHomeMapper(r.data), lang);
}

Future<List<Json>> getGaanaRadioStations([String? lang]) async {
  final r = await gaanaFetch({'type': 'home'}, languages: lang);
  if (r.error != null) {
    throw GaanaException(failureText(r, 'Failed to fetch Gaana home'));
  }
  final radio = gaanaHomeMapper(r.data)
      .where((s) => '${s['heading'] ?? ''}'.toLowerCase().contains('radio'))
      .toList();
  return hydrateGaanaSections(radio, lang);
}

Future<List<Json>> getGaanaSearchData(String q, [String? lang]) async {
  final r = await gaanaFetch({'type': 'search', 'keyword': q}, languages: lang);
  if (r.error != null) {
    throw GaanaException(failureText(r, 'Gaana search failed'));
  }
  return gaanaSearchMapper(r.data);
}

Future<List<Object?>> getGaanaTrendingSearchData([String? lang]) async {
  final r = await gaanaFetch({'type': 'searchTrending'}, languages: lang);
  if (r.error != null) {
    throw GaanaException(failureText(r, 'Gaana trending search failed'));
  }
  // Trending returns { entities: [...] }.
  final e = get(r.data, 'entities');
  return [
    for (final x in (truthy(e) ? e as List : const [])) mapGaanaEntity(x),
  ];
}
