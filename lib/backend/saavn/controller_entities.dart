// Album, playlist and channel controllers (port of the same-named functions in
// sunoh-api src/saavn/controller.ts).
import '../local_backend.dart';
import 'client.dart';
import 'config.dart';
import 'controller_shared.dart';
import 'helper.dart';

Map<String, Object?> _without(Map<String, Object?> m, String key) => {
  for (final e in m.entries)
    if (e.key != key) e.key: e.value,
};

Future<LocalReply> albumRecommendationController(
  Map<String, String> params,
  Map<String, String> query,
) async {
  final r = await saavnFetch({
    '__call': saavnEndpoints.albumRecommended,
    'albumid': params['albumId'],
    'type': 'album',
    'includeMetaTags': 0,
    ...saavnCommonParams,
  }, lang: saavnLanguages(query));
  if (r.error != null) {
    throw saavnFail('Failed to fetch album recommendations', r);
  }
  return LocalReply(
    recommendationDataMapper(r.data),
    message: r.message,
    source: 'saavn',
  );
}

Future<LocalReply> albumController(
  Map<String, String> params,
  Map<String, String> query,
) async {
  try {
    final lang = saavnLanguages(query);
    final r = await saavnFetch({
      '__call': saavnEndpoints.albumToken,
      'token': params['albumId'],
      'type': 'album',
      'includeMetaTags': 0,
      ...saavnCommonParams,
    }, lang: lang);
    if (r.error != null) throw saavnFail('Failed to fetch album details', r);

    final album = albumDataMapper(r.data);
    final sections = await saavnFetchSections(
      (album['sections']! as List).cast<Map<String, Object?>>(),
      (d) => {
        '__call': d['endpoint'],
        'albumid': d['albumId'],
        'album_year': d['year'],
        'type': d['type'],
        'language': d['language'],
        ...saavnCommonParams,
      },
      recommendationDataMapper,
      lang: lang,
    );
    return LocalReply(
      {..._without(album, 'sections'), 'sections': sections},
      message: saavnMessage(r, 'Album details fetched successfully'),
      source: 'saavn',
    );
  } on LocalApiError {
    rethrow;
  } catch (e) {
    throw LocalApiError('Failed to fetch album details', error: e.toString());
  }
}

Future<LocalReply> playlistController(
  Map<String, String> params,
  Map<String, String> query,
) async {
  try {
    final playlistId = params['playlistId'] ?? '';
    final page = query['page'] ?? '0';
    final count = query['count'] ?? '50';
    final lang = saavnLanguages(query);

    // Channels expose playlists by numeric `listing_id` rather than the
    // perma_url token `webapi.get` needs; `playlist.getDetails` returns the
    // same list[] + modules{} shape, so no remap is required.
    final isNumericId = RegExp(r'^\d+$').hasMatch(playlistId);

    final r = await saavnFetch(
      isNumericId
          ? {
              '__call': saavnEndpoints.playlistId,
              'listid': playlistId,
              'n': count,
              'p': page,
              ...saavnCommonParams,
            }
          : {
              '__call': saavnEndpoints.playlistToken,
              'token': playlistId,
              'type': 'playlist',
              'includeMetaTags': 0,
              'n': count,
              'p': page,
              ...saavnCommonParams,
            },
      lang: lang,
    );
    if (r.error != null) throw saavnFail('Failed to fetch playlist', r);

    final playlist = playlistDataMapper(r.data);
    final sections = await saavnFetchSections(
      (playlist['sections']! as List).cast<Map<String, Object?>>(),
      (d) => {
        '__call': d['endpoint'],
        'listid': d['listId'],
        'entity_type': d['type'],
        'entity_language': d['language'],
        ...saavnCommonParams,
      },
      recommendationDataMapper,
      lang: lang,
    );
    return LocalReply(
      {..._without(playlist, 'sections'), 'sections': sections},
      message: r.message,
      source: 'saavn',
    );
  } on LocalApiError {
    rethrow;
  } catch (e) {
    throw LocalApiError('Failed to fetch playlist', error: e.toString());
  }
}

Future<LocalReply> channelController(
  Map<String, String> params,
  Map<String, String> query,
) async {
  final channelId = params['channelId'] ?? '';
  final page = query['page'] ?? '1';
  final count = query['count'] ?? '50';

  try {
    // Numeric ids use channel.getDetails; anything else is a perma_url token.
    // JS `Number('')` is 0, so the empty string counts as numeric.
    final trimmed = channelId.trim();
    final isToken = trimmed.isNotEmpty && num.tryParse(trimmed) == null;

    final r = await saavnFetch({
      '__call': isToken
          ? saavnEndpoints.channelToken
          : saavnEndpoints.channelId,
      isToken ? 'token' : 'channel_id': channelId,
      'type': 'channel',
      'p': page,
      'n': count,
      'includeMetaTags': 0,
      ...saavnCommonParams,
    }, lang: saavnLanguages(query));
    if (r.error != null) throw saavnFail('Failed to fetch channel details', r);

    return LocalReply(
      channelDataMapper(r.data),
      message: r.message,
      source: 'saavn',
    );
  } on LocalApiError {
    rethrow;
  } catch (e) {
    throw LocalApiError('Internal server error', error: e.toString());
  }
}
