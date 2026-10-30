// Small pieces every saavn controller repeats in the TS.
import '../common.dart';
import '../local_backend.dart';
import 'client.dart';
import 'extract.dart';

/// `req.query.lang || req.query.languages`.
String? saavnLanguages(Map<String, String> query) {
  final l = or([query['lang'], query['languages']]);
  return l is String && l.isNotEmpty ? l : null;
}

/// TS `sendError(res, message || fallback, error, code)`.
LocalApiError saavnFail(String fallback, SaavnResponse r) => LocalApiError(
  r.message.isNotEmpty ? r.message : fallback,
  // The TS passes code 0 for network failures, which Fastify turns into a
  // 500; mirror that rather than inventing a status.
  code: r.code == 0 ? 500 : r.code,
  error: r.error,
);

/// `message || fallback` for the success envelope.
String saavnMessage(SaavnResponse r, String fallback) =>
    r.message.isNotEmpty ? r.message : fallback;

/// Fetches the secondary "more like this" lists named by [sections] in
/// parallel and keeps the non-empty ones, as album/playlist/song all do.
/// [paramsFor] builds each call's params from a section; [mapData] maps the
/// raw list.
Future<List<Map<String, Object?>>> saavnFetchSections(
  List<Map<String, Object?>> sections,
  Map<String, Object?> Function(Map<String, Object?> section) paramsFor,
  Object? Function(List<Object?> raw) mapData, {
  required String? lang,
}) async {
  final results = await Future.wait([
    for (final d in sections) saavnFetch(paramsFor(d), lang: lang),
  ]);
  return [
    for (var i = 0; i < results.length; i++)
      if (isValidArray(results[i].data))
        {
          'heading': sections[i]['heading'],
          'data': mapData((results[i].data! as List).cast<Object?>()),
          'source': 'saavn',
        },
  ];
}

/// JS `Number(x) || fallback` for query strings.
int saavnInt(String? raw, int fallback) {
  final n = num.tryParse(raw?.trim() ?? '');
  return n == null || n == 0 || n.isNaN ? fallback : n.toInt();
}
