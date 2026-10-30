// Song, artist and song-recommendation controllers (port of the same-named
// functions in sunoh-api src/saavn/controller.ts).
import 'package:flutter/foundation.dart';

import '../common.dart';
import '../local_backend.dart';
import 'client.dart';
import 'config.dart';
import 'controller_shared.dart';
import 'extract.dart';
import 'helper.dart';
import 'mapper.dart';

/// The first song of a `webapi.get` song response, which Saavn shapes as
/// `{songs: [..]}` or occasionally a bare array.
Object? _firstSong(Object? full) {
  final songs = prop(full, 'songs');
  final first = songs is List && songs.isNotEmpty ? songs.first : null;
  if (truthy(first)) return first;
  return full is List && full.isNotEmpty ? full.first : null;
}

Future<Object?> _fetchSong(String token, String? lang) async {
  final r = await saavnFetch({
    '__call': saavnEndpoints.songLink,
    'token': token,
    'type': 'song',
    ...saavnCommonParams,
  }, lang: lang);
  return r.data;
}

/// Artist pages list songs/albums without media URLs in a few shelves; fill
/// them in so those tiles are playable.
Future<Object?> _hydrate(Object? item, String? lang) async {
  try {
    final type = prop(item, 'type');
    final mediaUrls = prop(item, 'mediaUrls');
    final id = str(prop(item, 'id'));
    if (type == 'song' && (mediaUrls is! List || mediaUrls.isEmpty)) {
      final song = _firstSong(await _fetchSong(id, lang));
      if (truthy(song)) return mapSaavnSong(song);
    } else if (type == 'album') {
      final r = await saavnFetch({
        '__call': saavnEndpoints.albumToken,
        'token': id,
        'type': 'album',
        ...saavnCommonParams,
      }, lang: lang);
      final list = prop(r.data, 'list');
      final track = list is List && list.isNotEmpty ? list.first : null;
      if (truthy(track)) {
        final songToken = getToken(
          str(or([prop(track, 'perma_url'), prop(track, 'url'), ''])),
        );
        final songId = or([songToken, prop(track, 'id')]);
        final song = _firstSong(await _fetchSong(str(songId), lang));
        return mapSaavnSong(truthy(song) ? song : track);
      }
    }
  } catch (_) {
    // No ids in the log: they are content identifiers.
    debugPrint('[saavn] artist shelf hydration failed; keeping the bare tile');
  }
  return item; // Fall back to the unhydrated tile.
}

Future<LocalReply> artistController(
  Map<String, String> params,
  Map<String, String> query,
) async {
  final lang = saavnLanguages(query);
  final page = query['page'] ?? '0';
  final count = query['count'] ?? '50';

  final r = await saavnFetch({
    '__call': saavnEndpoints.artistLink,
    'token': params['artistId'],
    'type': 'artist',
    'p': page,
    'n_song': count,
    'n_album': count,
    ...saavnCommonParams,
  }, lang: lang);
  if (r.error != null) throw saavnFail('Failed to fetch artist details', r);

  final artist = artistDataMapper(r.data);
  for (final section
      in (artist['sections']! as List).cast<Map<String, Object?>>()) {
    final heading = prop(section, 'heading');
    final h = heading is String ? heading.toLowerCase() : null;
    final data = section['data'];
    if ((h == 'singles' || h == 'latest release' || h == 'latest releases') &&
        data is List) {
      // Only the first 20 shelf items are hydrated and kept, as in the TS.
      section['data'] = await promiseAllLimit<Object?, Object?>(
        data.take(20).toList(),
        10,
        (item) => _hydrate(item, lang),
      );
    }
  }
  return LocalReply(artist, message: r.message, source: 'saavn');
}

Future<LocalReply> songController(
  Map<String, String> params,
  Map<String, String> query,
) async {
  try {
    final lang = saavnLanguages(query);
    final songId = params['songId'];

    final r = await saavnFetch({
      '__call': saavnEndpoints.songLink,
      'token': songId,
      'type': 'song',
      ...saavnCommonParams,
    }, lang: lang);
    if (r.error != null) throw saavnFail('Failed to fetch song details', r);

    // TS reads `data?.songs[0]?.id`, which throws when `songs` is missing;
    // the catch below turns that into the same failure envelope.
    final rawSongs = prop(r.data, 'songs');
    if (rawSongs is! List) throw StateError('songs missing');
    final lyricsId = prop(rawSongs.firstOrNull, 'id');
    final lyrics = await saavnFetch({
      '__call': saavnEndpoints.lyrics,
      'lyrics_id': lyricsId,
      ...saavnCommonParams,
    }, lang: lang);

    final detail = songsDetailsMapper(r.data);
    final sections = await saavnFetchSections(
      detail.sections,
      _recoParams,
      (raw) => [
        for (final d in raw)
          switch (prop(d, 'type')) {
            'song' => mapSaavnSong(d),
            'album' => albumDataMapper(d),
            'playlist' => playlistDataMapper(d),
            _ => albumDataMapper(d),
          },
      ],
      lang: lang,
    );

    final head = detail.songs.length == 1
        ? detail.songs.first
        : <String, Object?>{'songs': detail.songs};
    return LocalReply(
      {
        ...head,
        'sections': sections,
        'lyrics': or([prop(lyrics.data, 'lyrics'), '']),
      },
      message: r.message,
      source: 'saavn',
    );
  } on LocalApiError {
    rethrow;
  } catch (e) {
    throw LocalApiError('Failed to fetch song details', error: e.toString());
  }
}

Map<String, Object?> _recoParams(Map<String, Object?> d) => {
  '__call': d['endpoint'],
  'song_id': d['songId'],
  'artist_ids': d['artistIds'],
  'type': d['type'],
  'language': d['language'],
  'actor_ids': d['actorIds'],
  'pid': d['pid'],
  ...saavnCommonParams,
};

/// Songs similar to [songId]: the song's own recommendation shelves, Saavn's
/// "reco" list and a freshly created radio station, merged and de-duplicated.
Future<Map<String, Object?>> getSaavnSongRecommendData(
  String songId, [
  String? languages,
]) async {
  // 1. The song itself, for the shelves it advertises.
  final ctx = await saavnFetch({
    '__call': saavnEndpoints.songLink,
    'token': songId,
    'type': 'song',
    ...saavnCommonParams,
  }, lang: languages);
  final songs = prop(ctx.data, 'songs');
  if (ctx.error != null || songs is! List || songs.isEmpty) {
    throw StateError(
      ctx.message.isNotEmpty ? ctx.message : 'Failed to fetch song context',
    );
  }

  final numericId = prop(songs.first, 'id');
  final detail = songsDetailsMapper(ctx.data);

  // 2. Every shelf except the generic ones.
  final calls = <Future<SaavnResponse>>[
    for (final d in detail.sections.where(
      (d) => !['currentlyTrending', 'topSearches'].contains(d['module_id']),
    ))
      saavnFetch(_recoParams(d), lang: languages),
  ];

  // 3. Saavn's deterministic similar-songs list.
  calls.add(
    saavnFetch({
      '__call': saavnEndpoints.songRecommended,
      'pid': numericId,
      ...saavnCommonParams,
      'ctx': 'android',
    }, lang: languages),
  );

  // 4. A station for variety; failure here must not sink the rest.
  Object? stationId;
  try {
    final station = await saavnFetch({
      '__call': saavnEndpoints.radioCreate,
      'pid': numericId,
      'query': or([detail.songs.first['title'], '']),
      ...saavnCommonParams,
      'ctx': 'android',
    }, lang: languages);
    stationId = prop(station.data, 'stationid');
    if (truthy(stationId)) {
      calls.add(
        saavnFetch({
          '__call': saavnEndpoints.radioSongs,
          'stationid': stationId,
          'k': 25,
          'next': 1,
          ...saavnCommonParams,
          'ctx': 'android',
        }, lang: languages),
      );
    }
  } catch (_) {
    // Continue without the station.
  }

  final results = await Future.wait(calls);

  // 5. Flatten the several response shapes Saavn uses and de-duplicate by id.
  final recommendations = <Object?, Map<String, Object?>>{};
  for (final r in results) {
    final raw = r.data;
    if (!truthy(raw)) continue;
    final found = <Object?>[];
    if (raw is List) {
      found.addAll(raw);
    } else if (raw is Map) {
      for (final v in raw.values) {
        if (truthy(prop(v, 'song'))) {
          found.add(prop(v, 'song'));
        } else if (prop(v, 'type') == 'song') {
          found.add(v);
        } else if (v is List) {
          found.addAll(v);
        }
      }
    }
    for (final s in found) {
      if (prop(s, 'type') != 'song') continue;
      final sanitized = mapSaavnSong(s);
      final id = sanitized['id'];
      if (id != numericId && id != songId) recommendations[id] = sanitized;
    }
  }

  return clean({
    'list': recommendations.values.toList(),
    'stationId': truthy(stationId) ? stationId : undefined,
  });
}
