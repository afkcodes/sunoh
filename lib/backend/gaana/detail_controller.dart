// Route controllers for single-entity Gaana endpoints: album, playlist,
// artist, song, stream and radio detail. Feed-style endpoints are in
// controller.dart.
//
// albumDetail and playlistDetail are the reason this port exists: Gaana
// answers them with a non-JSON page when asked from the old server's address,
// and with JSON from a phone on an ordinary connection.
import '../common.dart' show isValidTitle, promiseAllLimit;
import '../local_backend.dart';
import 'controller.dart' show guarded;
import 'http.dart';
import 'mapper.dart';
import 'sections.dart';
import 'util.dart';

LocalReply _ok(Object? data) =>
    LocalReply(data, message: 'OK', source: 'gaana');

/// Cross-provider sections for songDetail ("More from Artist" and "You Might
/// Also Like", both sourced from Saavn). They need the Saavn port, which this
/// package must not import, so the /music wiring installs it here. Left null,
/// songDetail simply ships without them, which is also what the server did
/// whenever Saavn failed.
Future<List<Json>> Function(Json song, String? lang)? saavnSongSections;

LocalApiError _fail(GaanaResult r, String fallback) =>
    LocalApiError(failureText(r, fallback), error: r.error);

Json _asJson(Object? v) => Map<String, dynamic>.from(v as Map);

List<Object?> _list(Object? v) =>
    truthy(v) ? List<Object?>.from(v as List) : [];

int _count(Object? v) => lengthOf(v) ?? 0;

/// `data.tracks?.[0] || data.song || data` for songDetail replies.
Object? _songPayload(Object? data) =>
    or(or(at(get(data, 'tracks'), 0), get(data, 'song')), data);

Future<LocalReply> playlistController(
  Map<String, String> params,
  Map<String, String> query,
) => guarded(() async {
  final r = await gaanaFetch({
    'seokey': params['playlistId'],
    'type': 'playlistDetail',
  }, languages: query['lang']);
  if (r.error != null) throw _fail(r, 'Failed to fetch playlist');

  final data = r.data as Map;
  final playlist = mapGaanaPlaylist(_asJson(or(data['playlist'], data)));
  if (truthy(data['tracks'])) {
    playlist['songs'] = [
      for (final t in (data['tracks'] as List)) mapGaanaTrack(t as Map),
    ];
  }
  return _ok({'playlist': playlist});
});

Future<LocalReply> albumController(
  Map<String, String> params,
  Map<String, String> query,
) => guarded(() async {
  final lang = query['lang'];
  final r = await gaanaFetch({
    'seokey': params['albumId'],
    'type': 'albumDetail',
  }, languages: lang);
  if (r.error != null) throw _fail(r, 'Failed to fetch album');

  final detail = r.data as Map;
  final album = mapGaanaAlbum(_asJson(or(detail['album'], detail)));
  if (truthy(detail['tracks'])) {
    album['songs'] = [
      for (final t in (detail['tracks'] as List)) mapGaanaTrack(t as Map),
    ];
  }

  final internalAlbumId = or(
    or(get(detail['album'], 'album_id'), detail['entity_id']),
    detail['id'],
  );
  final primaryArtistId = or(
    get(at(get(detail['album'], 'primaryartist'), 0), 'artist_id'),
    get(at(detail['artist'], 0), 'artist_id'),
  );

  // Independent calls: run together so the album costs one round trip.
  final results = await Future.wait([
    truthy(internalAlbumId)
        ? gaanaFetch({
            'type': 'albumSimilar',
            'id': internalAlbumId,
          }, languages: lang)
        : Future.value(const GaanaResult()),
    truthy(primaryArtistId)
        ? gaanaFetch({
            'type': 'albumArtistSongs',
            'id': primaryArtistId,
            'factor': 10,
          }, languages: lang)
        : Future.value(const GaanaResult()),
  ]);

  final sections = <Json>[];
  final similar = get(results[0].data, 'album');
  if (_count(similar) > 0) {
    sections.add({
      'heading': 'Similar Albums',
      'data': [
        for (final a in (similar as List))
          mapGaanaEntity({...(a as Map), 'entity_type': 'ALBUM'}),
      ],
      'source': 'gaana',
    });
  }
  final more = get(results[1].data, 'entities');
  if (_count(more) > 0) {
    sections.add({
      'heading': 'More from Artist',
      'data': [for (final e in (more as List)) mapGaanaEntity(e)],
      'source': 'gaana',
    });
  }
  return _ok({'album': album, 'sections': sections});
});

Future<GaanaResult> _artistSection(
  Object internalId,
  String path,
  int index,
  String? lang, [
  Map<String, Object?> extra = const {},
]) => gaanaFetch({
  'type': 'artistDetailSection',
  'apiPath': 'https://apiv2.gaana.com/$path/$internalId',
  ...extra,
  'index': index,
}, languages: lang);

Future<LocalReply> artistController(
  Map<String, String> params,
  Map<String, String> query,
) => guarded(() async {
  final lang = query['lang'];
  final r = await gaanaFetch({
    'type': 'artistDetailNew',
    'seokey': params['artistId'],
  }, languages: lang);
  final artistRaw = get(r.data, 'artist');
  if (r.error != null || !truthy(artistRaw)) {
    throw LocalApiError('Artist not found', error: r.error);
  }

  final artist = mapGaanaArtist(artistRaw as Map);
  final id = artistRaw['artist_id'] as Object;

  final res = await Future.wait([
    _artistSection(id, 'home/artist/tracks', 0, lang, {
      'sortBy': 'popularity',
      'sortOrder': 0,
      'request_type': 'web',
      'pkc': 'true',
      'st': 'hls',
      'song_type': 'new',
      'limit': '0,20',
    }),
    _artistSection(id, 'home/artist/album', 2, lang),
    _artistSection(id, 'home/artist/playlist', 1, lang),
    _artistSection(id, 'player/similar-artists', 4, lang),
  ]);

  const headings = [
    'Top Tracks',
    'Top Albums',
    'Related Playlists',
    'Similar Artists',
  ];
  final sections = <Json>[];
  for (var i = 0; i < res.length; i++) {
    final entities = get(res[i].data, 'entities');
    if (_count(entities) > 0) {
      sections.add({
        'heading': headings[i],
        'data': [for (final e in (entities as List)) mapGaanaEntity(e)],
        'source': 'gaana',
      });
    }
  }
  return _ok({'artist': artist, 'sections': sections});
});

Future<LocalReply> songController(
  Map<String, String> params,
  Map<String, String> query,
) => guarded(() async {
  final lang = query['lang'];
  final r = await gaanaFetch({
    'seokey': params['songId'],
    'type': 'songDetail',
  }, languages: lang);
  if (r.error != null) throw _fail(r, 'Failed to fetch song');

  final detail = _songPayload(r.data) as Map;
  final song = mapGaanaTrack(detail);
  final primaryArtistId = or(
    get(at(detail['artist'], 0), 'artist_id'),
    get(at(detail['primaryartist'], 0), 'artist_id'),
  );

  final sections = <Json>[];
  final hook = saavnSongSections;
  if (hook != null) {
    try {
      sections.addAll(await hook(song, lang));
    } on GaanaBlocked {
      rethrow;
    } catch (_) {
      // Cross-provider sections are decoration; the song itself must load.
    }
  }

  if (truthy(primaryArtistId)) {
    try {
      final res = await gaanaFetch({
        'type': 'albumArtistSongs',
        'id': primaryArtistId,
        'factor': 10,
      }, languages: lang);
      final entities = or(get(res.data, 'entities'), get(res.data, 'tracks'));
      final songs = [
        for (final t in _list(entities))
          if (isValidTitle(or(get(t, 'title'), get(t, 'name'))))
            mapGaanaEntity({
              ...(t as Map),
              'entity_type': or(t['entity_type'], 'TRACK'),
            }),
      ];
      if (songs.isNotEmpty) {
        sections.add({
          'heading': 'Trending from Artist',
          'data': songs,
          'source': 'gaana',
        });
      }
    } on GaanaBlocked {
      // A ban is not a bad shelf; let the server answer the whole song.
      rethrow;
    } catch (_) {
      // Same: a failed shelf is dropped, not an error.
    }
  }

  return _ok({...song, 'sections': sections});
});

Future<LocalReply> songStreamController(
  Map<String, String> params,
  Map<String, String> query,
) => guarded(() async {
  final r = await gaanaFetch({
    'seokey': params['songId'],
    'type': 'songDetail',
  }, languages: query['lang']);
  if (r.error != null) throw _fail(r, 'Failed to fetch song streams');
  return _ok(mapGaanaTrack(_songPayload(r.data) as Map)['mediaUrls']);
});

Future<LocalReply> radioDetailController(
  Map<String, String> params,
  Map<String, String> query,
) => guarded(() async {
  final lang = query['lang'];
  final r = await gaanaFetch({
    'id': params['radioId'],
    'type': 'gaanaradiodetail',
  }, languages: lang);
  if (r.error != null) throw _fail(r, 'Failed to fetch radio detail');

  final tracks = _list(get(r.data, 'tracks'));
  // The radio list carries no stream URLs; fetch each song's detail for them.
  final enriched = await promiseAllLimit<Object?, Json>(tracks, 10, (
    track,
  ) async {
    try {
      final seokey = get(track, 'seokey');
      if (!truthy(seokey)) return mapGaanaTrack(track as Map);
      final d = await gaanaFetch({
        'seokey': seokey,
        'type': 'songDetail',
      }, languages: lang);
      final full = or(
        or(or(at(get(d.data, 'tracks'), 0), get(d.data, 'song')), d.data),
        track,
      );
      return mapGaanaTrack(full as Map);
    } on GaanaBlocked {
      // Otherwise the list would silently lack stream URLs.
      rethrow;
    } catch (_) {
      return mapGaanaTrack(track as Map);
    }
  });
  return _ok(enriched);
});
