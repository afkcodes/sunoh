// Gaana entity -> sunoh DTO shape (src/mappers/gaana.mapper.ts).
//
// JSON parity note: the server serialised with JSON.stringify, which drops
// `undefined` values. Dart has no undefined, so every output map goes through
// [_defined] and a null drops the key. The one visible difference is a field
// Gaana sent as an explicit `null`, which the server would have echoed and we
// omit; every DTO parser in lib/api/dto.dart treats the two the same.
import 'dart:convert';

import 'crypto.dart';
import 'util.dart';

typedef Json = Map<String, dynamic>;

Json _defined(Map<String, Object?> m) => {
  for (final e in m.entries)
    if (e.value != null) e.key: e.value,
};

/// Gaana keeps extra metadata in an array of {key, value} objects.
Object? extractGaanaEntityInfo(Object? entityInfo, String key) {
  if (entityInfo is! List) return null;
  for (final info in entityInfo) {
    if (info is Map && info['key'] == key) return info['value'];
  }
  return null;
}

/// Picks one usable URL out of Gaana's image fields, which may be a plain
/// string, a JSON-encoded string (`atwj`) or a size map.
Object? getGaanaImageUrl(Object? imageSource) {
  if (!truthy(imageSource)) return '';
  Object? fromMap(Map m) =>
      or(or(or(m['size_l'], m['size_m']), m['size_s']), m.values.firstOrNull);
  if (imageSource is String) {
    if (imageSource.startsWith('{')) {
      try {
        final parsed = jsonDecode(imageSource);
        if (parsed is Map) return fromMap(parsed);
        return imageSource;
      } catch (_) {
        return imageSource;
      }
    }
    return imageSource;
  }
  if (imageSource is Map) return fromMap(imageSource);
  return '';
}

/// 50/150/500 variants of a Gaana CDN URL, staying inside the URL's own
/// pattern (size_* or crop_*) so no variant redirects, plus `size_xxl` for
/// size_* URLs: Gaana's CDN renders it at 1200x1200 where `size_l` is only
/// 400x400 (checked across a sample of album covers), and the largest label
/// is what FeedItem.artwork picks. The art widget falls back to size_xl and
/// size_l if a cover has no xxl rendition (api/art_urls.dart).
List<Json> createGaanaImageLinks(Object? link) {
  if (link is! String || link.isEmpty) return [];
  const targets = [
    ('50x50', 'size_s', 'crop_80x80'),
    ('150x150', 'size_m', 'crop_175x175'),
    ('500x500', 'size_l', 'crop_480x480'),
  ];
  return [
    for (final (name, suffix, crop) in targets)
      {'quality': name, 'link': _variant(link, suffix, crop)},
    if (link.contains('size_'))
      {
        'quality': '1200x1200',
        'link': link.replaceFirst(RegExp(r'size_[a-z]+'), 'size_xxl'),
      },
  ];
}

String _variant(String link, String suffix, String crop) {
  var out = link;
  if (link.contains('size_')) {
    out = link.replaceFirst(RegExp(r'size_[a-z]+'), suffix);
  } else if (link.contains('crop_')) {
    out = link.replaceFirst(RegExp(r'crop_\d+x\d+'), crop);
  }
  // size_xl redirects in loops on Gaana's CDN.
  if (out.contains('size_xl')) out = out.replaceFirst('size_xl', 'size_l');
  return out;
}

/// Best available image field -> one consistent set of links. Legacy
/// size-based fields (atwj, atw) come first because mixing families breaks
/// some images.
List<Json> getGaanaImagery(Object? data) {
  if (!truthy(data)) return [];
  if (data is String) return createGaanaImageLinks(data);
  const fields = [
    'atwj',
    'atw',
    'artwork_large',
    'artwork_medium',
    'artwork_web',
    'artwork_bio',
    'artwork',
  ];
  for (final f in fields) {
    final url = getGaanaImageUrl(get(data, f));
    if (truthy(url)) return createGaanaImageLinks(url);
  }
  return [];
}

List<Json> _mediaUrls(Map data) {
  final streamUrl = or(
    extractGaanaEntityInfo(data['entity_info'], 'stream_url'),
    data['urls'],
  );
  if (streamUrl is! Map) return [];
  final out = <Json>[];
  for (final e in streamUrl.entries) {
    final msg = get(e.value, 'message');
    final link = decryptGaanaUrl(msg is String ? msg : null);
    if (link.isNotEmpty) out.add({'quality': e.key, 'link': link});
  }
  return out;
}

Object? _artistsInfo(Map data) => or(
  or(
    or(extractGaanaEntityInfo(data['entity_info'], 'artist'), data['artist']),
    data['primaryartist'],
  ),
  const [],
);

List<Json> _mapArtists(Object? info, {required bool withRole}) => [
  for (final a in (info is List ? info : [info]))
    _defined({
      'id': or(get(a, 'seokey'), get(a, 'artist_id')),
      'name': get(a, 'name'),
      if (withRole) 'role': get(a, 'role'),
      'image': getGaanaImagery(a),
      'type': 'artist',
    }),
];

String _subtitle(List<Json> artists) =>
    artists.map((a) => a['name'] ?? '').join(', ');

/// JS template-literal rendering of a possibly-missing value.
String _tpl(Object? v) => v == null ? 'undefined' : jsString(v)!;

Json mapGaanaSong(Map data) {
  final info = data['entity_info'];
  final albumFromInfo = at(extractGaanaEntityInfo(info, 'album'), 0);
  final Object? albumInfo = truthy(albumFromInfo)
      ? albumFromInfo
      : (truthy(data['album_id'])
            ? {
                'name': data['album_title'],
                'album_id': data['album_id'],
                'album_seokey': data['albumseokey'],
              }
            : <String, Object?>{});
  final year = or(
    or(extractGaanaEntityInfo(info, 'release_date'), data['release_date']),
    data['year'],
  );
  final artists = _mapArtists(_artistsInfo(data), withRole: true);

  return _defined({
    'id': or(or(data['seokey'], data['track_id']), data['entity_id']),
    'title': or(data['name'], data['track_title']),
    'subtitle': _subtitle(artists),
    'type': 'song',
    'image': getGaanaImagery(data),
    'language': data['language'],
    'year': jsString(year)?.split('-').first,
    'duration': or(extractGaanaEntityInfo(info, 'duration'), data['duration']),
    'playCount': or(
      extractGaanaEntityInfo(info, 'play_ct'),
      jsString(data['total_favourite_count']),
    ),
    'mediaUrls': _mediaUrls(data),
    'artists': artists,
    'album': _defined({
      'id': or(get(albumInfo, 'album_seokey'), get(albumInfo, 'album_id')),
      'name': or(get(albumInfo, 'name'), get(albumInfo, 'album_title')),
      'url': get(albumInfo, 'album_seokey'),
    }),
    'hasLyrics':
        truthy(data['lyrics_url']) ||
        truthy(extractGaanaEntityInfo(info, 'lyrics_url')),
    'copyright': or(data['recordlevel'], data['vendor_name']),
    'releaseDate': year,
    'source': 'gaana',
  });
}

Json mapGaanaTrack(Map data) => mapGaanaSong(data);

Json mapGaanaAlbum(Map data) {
  final info = data['entity_info'];
  final year = or(extractGaanaEntityInfo(info, 'release_date'), data['year']);
  final language = data['language'];
  final artists = _mapArtists(_artistsInfo(data), withRole: false);
  return _defined({
    'id': or(or(data['seokey'], data['entity_id']), data['album_id']),
    'title': or(data['name'], data['title']),
    'subtitle': _subtitle(artists),
    'headerDesc': 'Album • ${_tpl(language)} • ${_tpl(year)}',
    'description': data['detailed_description'],
    'type': 'album',
    'image': getGaanaImagery(data),
    'language': language,
    'year': jsString(year),
    'songCount': or(
      jsString(lengthOf(extractGaanaEntityInfo(info, 'track_ids'))),
      jsString(data['trackcount']),
    ),
    'artists': artists,
    'songs': <Json>[],
    'copyright': or(data['recordlevel'], data['vendor_name']),
    'releaseDate': data['release_date'],
    'playCount': data['al_play_ct'],
    'source': 'gaana',
    'url': data['seokey'],
  });
}

Json mapGaanaPlaylist(Map data) => _defined({
  'id': or(or(data['seokey'], data['entity_id']), data['playlist_id']),
  'title': or(data['name'], data['title']),
  'subtitle': data['language'],
  'type': 'playlist',
  'image': getGaanaImagery(data),
  'songCount': or(
    or(
      jsString(
        lengthOf(extractGaanaEntityInfo(data['entity_info'], 'track_ids')),
      ),
      jsString(data['trackcount']),
    ),
    jsString(data['count']),
  ),
  'followers': jsString(data['favorite_count']),
  'description': data['detailed_description'],
  'songs': <Json>[],
  'source': 'gaana',
  'url': data['seokey'],
});

Json mapGaanaArtist(Map data) => _defined({
  'id': or(or(data['seokey'], data['entity_id']), data['artist_id']),
  'name': data['name'],
  'type': 'artist',
  'image': getGaanaImagery(data),
  'followers': jsString(data['favorite_count']),
  'bio': or(data['desc'], data['detailed_description']),
  'songCount': jsString(data['songs']),
  'albumCount': jsString(data['albums']),
  'url': data['seokey'],
});

Json mapGaanaRadio(Map data) => _defined({
  'id': or(data['entity_id'], data['seokey']),
  'title': data['name'],
  'subtitle': data['language'],
  'type': 'radio_station',
  'image': getGaanaImagery(data),
  'language': data['language'],
  'stationType': 'radio_station',
  'source': 'gaana',
  'url': data['seokey'],
});

Json mapGaanaOccasion(Map data) => _defined({
  'id': or(data['seokey'], data['entity_id']),
  'title': data['name'],
  'type': 'occasion',
  'image': getGaanaImagery(data),
  'source': 'gaana',
  'url': data['seokey'],
});

Json mapGaanaSearchAlbum(Map data) {
  final raw = or(data['artist'], data['primaryartist']);
  final artists = [
    for (final a in (raw is List ? raw : const []))
      _defined({
        'id': or(get(a, 'seokey'), get(a, 'artist_id')),
        'name': get(a, 'name'),
        'type': 'artist',
      }),
  ];
  final releaseYear = (data['release_date'] is String)
      ? (data['release_date'] as String).split('-').first
      : null;
  final year = or(data['year'], releaseYear);
  final language = data['language'];
  return _defined({
    'id': or(or(data['seokey'], data['album_id']), data['entity_id']),
    'title': or(data['title'], data['name']),
    'subtitle': _subtitle(artists),
    'headerDesc': 'Album • ${_tpl(language)} • ${_tpl(year)}',
    'description': data['detailed_description'],
    'type': 'album',
    'image': getGaanaImagery(data),
    'language': language,
    'year': jsString(year),
    'songCount': jsString(data['trackcount']),
    'artists': [
      for (final a in artists) {...a, 'image': getGaanaImagery(a)},
    ],
    'songs': <Json>[],
    'copyright': or(data['recordlevel'], data['vendor_name']),
    'releaseDate': data['release_date'],
    'playCount': data['al_play_ct'],
    'source': 'gaana',
    'url': data['seokey'],
  });
}

/// Dispatch on `entity_type`; unknown types pass through untouched.
Object? mapGaanaEntity(Object? data) {
  if (data is! Map) throw ArgumentError('entity is not an object');
  final type = (truthy(data['entity_type']) ? '${data['entity_type']}' : '')
      .toUpperCase();
  return switch (type) {
    'TR' || 'TRACK' => mapGaanaSong(data),
    'AL' || 'ALBUM' => mapGaanaSearchAlbum(data),
    'PL' || 'PLAYLIST' => mapGaanaPlaylist(data),
    'AR' || 'ARTIST' => mapGaanaArtist(data),
    'RL' || 'RADIO' => mapGaanaRadio(data),
    'OC' || 'OCCASION' => mapGaanaOccasion(data),
    _ => data,
  };
}
