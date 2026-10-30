// Radio / station controllers (port of the same-named functions in sunoh-api
// src/saavn/controller.ts). Station payloads are passed through as Saavn sent
// them except where the TS maps them.
import 'package:flutter/foundation.dart';

import '../local_backend.dart';
import 'client.dart';
import 'config.dart';
import 'controller_shared.dart';
import 'extract.dart';
import 'helper.dart';

Future<LocalReply> stationController(
  Map<String, String> params,
  Map<String, String> query,
) async {
  final language = query['language'];
  final languages = or([saavnLanguages(query), language, 'english']) as String;
  final name = query['name'];
  final q = query['query'];

  final r = await saavnFetch({
    '__call': saavnEndpoints.radioFeatured,
    'language': languages.toLowerCase().contains('english')
        ? 'english'
        : languages,
    'name': or([name, q]),
    'pid': '',
    'query': q ?? '',
    'mode': '',
    'artistid': '',
    'includeMetaTags': 0,
    ...saavnCommonParams,
  }, lang: languages);
  if (r.error != null) throw saavnFail('Failed to create station', r);
  return LocalReply(r.data, message: r.message, source: 'saavn');
}

Future<LocalReply> artistStationController(
  Map<String, String> params,
  Map<String, String> query,
) async {
  final artistId = query['artistId'];
  final name = query['name'];
  final q = query['query'];

  final r = await saavnFetch({
    '__call': saavnEndpoints.radioArtist,
    'artistid': or([artistId, '']), // callers may legitimately leave it empty
    // Prefer name, then query, then the id (which can itself be a name).
    'name': or([name, q, artistId]),
    'query': or([q, name, artistId]),
    'mode': '',
    ...saavnCommonParams,
  }, lang: saavnLanguages(query));
  if (r.error != null) throw saavnFail('Failed to create artist station', r);
  return LocalReply(r.data, message: r.message, source: 'saavn');
}

Future<LocalReply> entityStationController(
  Map<String, String> params,
  Map<String, String> query,
) async {
  final entityId = query['entityId'];
  final entityType = query['entityType'] ?? 'song';
  final isSong = entityType == 'song';

  final r = await saavnFetch({
    '__call': isSong ? saavnEndpoints.radioCreate : saavnEndpoints.radioEntity,
    'entity_id': entityId,
    'entity_type': entityType,
    'pid': isSong ? entityId : null,
    ...saavnCommonParams,
    'ctx': isSong ? 'android' : saavnCommonParams['ctx'],
  }, lang: saavnLanguages(query));
  if (r.error != null) throw saavnFail('Failed to create entity station', r);
  return LocalReply(r.data, message: r.message, source: 'saavn');
}

Future<LocalReply> featuredStationsController(
  Map<String, String> params,
  Map<String, String> query,
) async {
  final r = await saavnFetch({
    '__call': saavnEndpoints.featuredStations,
    ...saavnCommonParams,
  }, lang: saavnLanguages(query));
  if (r.error != null) throw saavnFail('Failed to fetch featured stations', r);
  final data = r.data;
  return LocalReply(
    data is List ? [for (final d in data) dataSanitizer(d)] : data,
    message: r.message,
    source: 'saavn',
  );
}

Future<LocalReply> stationSongsController(
  Map<String, String> params,
  Map<String, String> query,
) async {
  final stationId = params['stationId'];
  final next = query['next'] ?? '1';

  final r = await saavnFetch({
    '__call': saavnEndpoints.radioSongs,
    'stationid': stationId,
    'next': next,
    'k': or([query['count'], query['k'], 20]),
    ...saavnCommonParams,
    'ctx': 'android',
  }, lang: saavnLanguages(query));
  if (r.error != null) throw saavnFail('Failed to fetch station songs', r);

  final upstreamError = prop(r.data, 'error');
  if (truthy(upstreamError)) {
    // Station ids are content identifiers; keep them out of the log.
    debugPrint('[saavn] radio station returned an upstream error');
    throw LocalApiError(
      'Saavn API returned an error: ${str(upstreamError)}',
      error: upstreamError,
    );
  }
  return LocalReply(
    stationSongsMapper(r.data),
    message: r.message,
    source: 'saavn',
  );
}
