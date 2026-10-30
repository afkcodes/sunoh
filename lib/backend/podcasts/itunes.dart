// Apple Podcasts top charts, ported from sunoh-api src/podcast/itunes.ts.
//
// Discovery only: Apple yields iTunes ids, which PodcastIndex then resolves
// to the show the rest of the app plays. The RSS-JSON endpoint is the only
// one that still works (the applemarketingtools one began answering 405).
import 'dart:convert';

import 'package:dio/dio.dart';

const _userAgent = 'sunoh-api/1.0 (+https://sunoh.online)';

/// Top podcasts for [country] (ISO alpha-2), optionally one iTunes genre.
/// Returns iTunes ids in chart order; any failure is an empty list so one
/// bad section never fails the whole home page.
Future<List<String>> appleChart(
  Dio dio,
  String country,
  int count, {
  String? genreId,
}) async {
  final cc = Uri.encodeComponent(country.toLowerCase());
  final n = count.clamp(1, 100);
  final genre = genreId == null ? '' : '/genre=${Uri.encodeComponent(genreId)}';
  final url =
      'https://itunes.apple.com/$cc/rss/toppodcasts/limit=$n$genre/json';
  try {
    final res = await dio.get<String>(
      url,
      options: Options(
        headers: {'User-Agent': _userAgent, 'Accept': 'application/json'},
        responseType: ResponseType.plain,
        sendTimeout: const Duration(seconds: 6),
        receiveTimeout: const Duration(seconds: 6),
      ),
    );
    return parseAppleChart(jsonDecode(res.data ?? ''));
  } on DioException {
    return const [];
  } on FormatException {
    return const [];
  }
}

/// Pulls `feed.entry[].id.attributes['im:id']`, skipping malformed entries.
List<String> parseAppleChart(Object? body) {
  if (body is! Map) return const [];
  final feed = body['feed'];
  final entries = feed is Map ? feed['entry'] : null;
  if (entries is! List) return const [];
  final out = <String>[];
  for (final e in entries) {
    if (e is! Map) continue;
    final idObj = e['id'];
    final attrs = idObj is Map ? idObj['attributes'] : null;
    final id = attrs is Map ? attrs['im:id'] : null;
    if (id != null) out.add('$id');
  }
  return out;
}
