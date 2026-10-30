// Port of sunoh-api src/saavn/helper.ts: the section/list mappers that sit
// above mapper.dart. Output maps are built with [clean] (see extract.dart).
import '../common.dart';
import 'config.dart';
import 'extract.dart';
import 'mapper.dart';

const _excludedKeys = ['history', 'city_mod'];

List<Object?> _list(Object? v) =>
    v is List ? v : throw StateError('not a list');

/// Maps one raw module item by its declared `type`; unknown types fall back
/// to a generic tile (radio stations, shows...).
Object? dataSanitizer(Object? data) {
  final type = ex(data, homeConfig['type']!);
  if (type == 'song') return mapSaavnSong(data);
  if (type == 'album') return mapSaavnAlbum(data);
  if (type == 'playlist') return mapSaavnPlaylist(data);
  if (type == 'artist') return mapSaavnArtist(data);
  if (type == 'channel') return mapSaavnChannel(data);

  final idRaw = or([ex(data, homeConfig['id']!), '']);
  final stationType = ex(data, homeConfig['stationType']!);
  final query = or([prop(prop(data, 'more_info'), 'query'), '']);

  // For artist stations the id is often the artist name (the real station id
  // is only minted when the station is created).
  final id = idRaw == '' && stationType == 'artist' ? query : idRaw;

  return clean({
    'id': id,
    'title': or([ex(data, homeConfig['title']!), '']),
    'subtitle': ex(data, homeConfig['subtitle']!),
    'type': or([type, 'unknown']),
    'image': createImageLinks(or([ex(data, homeConfig['images']!), ''])),
    'language': ex(data, homeConfig['language']!),
    'source': 'saavn',
    // The frontend uses this to know it is an artist radio.
    'stationType': stationType,
    'songId': idRaw,
    'token': ex(data, homeConfig['token']!),
  });
}

List<Map<String, Object?>> songDataSanitizer(List<Object?> data) => [
  for (final s in data) mapSaavnSong(s),
];

Map<String, Object?> albumDataSanitizer(Object? data) => mapSaavnAlbum(data);

List<Map<String, Object?>> homeDataMapper(Object? data) {
  final modules = prop(data, 'modules');
  final modulesArr = [
    if (modules is Map) ...modules.keys.cast<String>(),
    'browse_discover',
  ].where((k) => !_excludedKeys.contains(k));
  final mapped = <Map<String, Object?>>[];

  for (final module in modulesArr) {
    Object? heading = ex(prop(modules, module), homeConfig['heading']!);
    if (module == 'browse_discover' && !truthy(heading)) heading = 'Browse';
    final items = prop(data, module);
    if (items is List && items.isNotEmpty && truthy(heading)) {
      mapped.add({
        'heading': heading,
        'data': [for (final d in items) dataSanitizer(d)],
        'source': 'saavn',
      });
    }
  }

  return mapped
      .where((d) => !str(d['heading']).toLowerCase().contains('podcasts'))
      .toList();
}

/// The "more like this" blocks Saavn lists under `modules` for albums and
/// playlists; each is later fetched by `source` with `source_params`.
List<Map<String, Object?>> _recoSections(Object? data) {
  final sections = <Map<String, Object?>>[];
  final modules = prop(data, 'modules');
  if (modules is Map) {
    for (final key in modules.keys.where(
      (d) => !['artists', 'list'].contains(d),
    )) {
      sections.add(
        clean({
          for (final e in albumRecoConfig.entries)
            e.key: ex(modules[key], e.value),
        }),
      );
    }
  }
  return sections;
}

Map<String, Object?> albumDataMapper(Object? data) => {
  ...mapSaavnAlbum(data),
  'sections': _recoSections(data),
};

Map<String, Object?> playlistDataMapper(Object? data) => {
  ...mapSaavnPlaylist(data),
  'sections': _recoSections(data),
};

List<Object?> recommendationDataMapper(Object? data) => [
  for (final item in truthy(data) ? _list(data) : const <Object?>[])
    dataSanitizer(item),
];

Map<String, Object?> stationSongsMapper(Object? data) {
  final songs = <Object?>[];
  final list = prop(data, 'list');
  if (list is List) {
    songs.addAll(list);
  } else if (data is Map) {
    for (final e in data.entries) {
      if (e.key == 'stationid' || e.key == 'error' || e.key == 'status') {
        continue;
      }
      if (truthy(prop(e.value, 'song'))) {
        songs.add(prop(e.value, 'song'));
      } else if (truthy(prop(e.value, 'id'))) {
        songs.add(e.value);
      }
    }
  }
  return clean({
    'list': songDataSanitizer(songs),
    'id': prop(data, 'stationid'),
  });
}

List<Map<String, Object?>> topSearchMapper(Object? data) {
  final albums = <Object?>[];
  final artists = <Object?>[];
  final playlists = <Object?>[];
  final songs = <Object?>[];
  for (final d in truthy(data) ? _list(data) : const <Object?>[]) {
    final type = prop(d, 'type');
    if (type == 'album') {
      albums.add(d);
    } else if (type == 'song') {
      songs.add(d);
    } else if (type == 'artist') {
      artists.add(d);
    } else if (type == 'playlist') {
      playlists.add(d);
    }
  }
  return [
    {
      'heading': 'Albums',
      'data': albums.map(mapSaavnAlbum).toList(),
      'source': 'saavn',
    },
    {
      'heading': 'Playlists',
      'data': playlists.map(mapSaavnPlaylist).toList(),
      'source': 'saavn',
    },
    {
      'heading': 'Artists',
      'data': artists.map(mapSaavnArtist).toList(),
      'source': 'saavn',
    },
    {
      'heading': 'Songs',
      'data': songs.map(mapSaavnSong).toList(),
      'source': 'saavn',
    },
  ].where((s) => (s['data']! as List).isNotEmpty).toList();
}

const _contentKeys = ['topquery', 'albums', 'playlists', 'artists'];

/// Maps the `autocomplete.get` response (search type `all`).
List<Map<String, Object?>> autoCompleteDataMapper(Object? data) {
  // The TS names this `excludedKeys` but it is the kept set: everything but
  // podcast shows/episodes.
  final keys = [
    if (data is Map) ...data.keys.cast<String>(),
  ].where((k) => !['episodes', 'shows'].contains(k));

  final out = <Map<String, Object?>>[];
  for (final key in keys) {
    final Object? mapped;
    if (_contentKeys.contains(key)) {
      mapped = [
        for (final d in _list(prop(prop(data, key), 'data')))
          switch (prop(d, 'type')) {
            'song' => mapSaavnSong(d),
            'album' => mapSaavnAlbum(d),
            'artist' => mapSaavnArtist(d),
            'playlist' => mapSaavnPlaylist(d),
            _ => dataSanitizer(d),
          },
      ];
    } else if (key == 'songs') {
      mapped = _list(prop(prop(data, key), 'data')).map(mapSaavnSong).toList();
    } else {
      mapped = (data as Map)[key];
    }
    out.add({
      'heading': capitalizeFirstLetter(key),
      'data': mapped,
      'source': 'saavn',
    });
  }
  return out
      .where((s) => s['data'] is List && (s['data']! as List).isNotEmpty)
      .toList();
}

List<Map<String, Object?>> similarArtistsDataMapper(Object? data) => [
  for (final a in truthy(data) ? _list(data) : const <Object?>[])
    mapSaavnArtist(a),
];

Map<String, Object?> artistDataMapper(Object? data) {
  final sections = <Map<String, Object?>>[];
  final modules = prop(data, 'modules');

  if (modules is Map) {
    for (final key in modules.keys.cast<String>()) {
      final title = prop(modules[key], 'title');
      if (['topEpisodes', 'episodes', 'shows', 'topShows'].contains(key)) {
        continue;
      }
      final items = prop(data, key);
      if (key == 'similarArtists') {
        sections.add(
          clean({
            'heading': title,
            'data': similarArtistsDataMapper(defined(items)),
            'source': 'saavn',
          }),
        );
      } else if (items is List) {
        sections.add(
          clean({
            'heading': title,
            'data': [for (final d in items) dataSanitizer(d)],
            'source': 'saavn',
          }),
        );
      }
    }
  }
  return {...mapSaavnArtist(data), 'sections': sections};
}

/// Song detail response: the mapped songs plus the "more like this" blocks
/// described in `modules` (each later fetched by `endpoint`).
({List<Map<String, Object?>> songs, List<Map<String, Object?>> sections})
songsDetailsMapper(Object? data) {
  final rawSongs = prop(data, 'songs');
  final songs = songDataSanitizer(
    truthy(rawSongs) ? _list(rawSongs) : const [],
  );
  final sections = <Map<String, Object?>>[];
  final modules = prop(data, 'modules');
  if (modules is Map) {
    for (final key in modules.keys.cast<String>()) {
      sections.add(
        clean({
          'module_id': key,
          for (final e in songDetailsConfig.entries)
            e.key: ex(modules[key], e.value),
        }),
      );
    }
  }
  return (songs: songs, sections: sections);
}

List<Map<String, Object?>> channelDataMapper(Object? data) {
  // Saavn sometimes wraps the response in a `data` field, sometimes not.
  final source = or([prop(data, 'data'), data]);
  final sections = <Map<String, Object?>>[];
  if (!truthy(source)) return sections;

  Object? title(String key) => prop(prop(source, 'modules'), key);

  final topPlaylists = prop(source, 'top_playlists');
  if (topPlaylists is List) {
    sections.add({
      'heading': or([prop(title('top_playlists'), 'title'), 'Top Playlists']),
      'data': topPlaylists.map(mapSaavnPlaylist).toList(),
      'source': 'saavn',
    });
  }
  final topSongs = prop(source, 'top_songs');
  if (topSongs is List) {
    sections.add({
      'heading': or([prop(title('top_songs'), 'title'), 'Top Songs']),
      'data': topSongs.map(mapSaavnSong).toList(),
      'source': 'saavn',
    });
  }

  final modules = prop(source, 'modules');
  if (modules is Map) {
    for (final key in modules.keys.cast<String>()) {
      final items = prop(source, key);
      if (['top_playlists', 'top_songs'].contains(key) ||
          items is! List ||
          items.isEmpty) {
        continue;
      }
      final mapped = [for (final it in items) dataSanitizer(it)];
      // Slots filled only with `radio_station` tiles (e.g. quick_stations)
      // are curated stations Saavn will not seed through the public radio
      // API ("No new song found"); keeping them would render unplayable
      // tiles. Partially-station sections keep their playable items.
      final filtered = mapped
          .where((it) => prop(it, 'type') != 'radio_station')
          .toList();
      if (filtered.isEmpty) continue;
      sections.add({
        'heading': or([prop(modules[key], 'title'), toSentenceCase(key)]),
        'data': filtered,
        'source': 'saavn',
      });
    }
  }
  return sections;
}
