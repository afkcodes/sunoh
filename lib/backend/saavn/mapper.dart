// Port of sunoh-api src/mappers/saavn.mapper.ts: raw JioSaavn JSON in, the
// sunoh song/album/artist/playlist/channel shapes out. Every map is built with
// [clean] so fields Saavn did not send are absent, as with JSON.stringify.
import '../common.dart';
import 'config.dart';
import 'extract.dart';

// 500x500 is the largest rendition Saavn's CDN publishes (the `-WxH` token is
// the only size control; the master is not exposed), so it is the ceiling.
const _imageSizes = ['50x50', '150x150', '500x500'];
final _sizeSuffix = RegExp(r'-(\d+)x(\d+)\.(?:jpg|jpeg|png|webp)(?:$|\?)');

/// Saavn images come as one URL with a size baked in; fan it out to the three
/// sizes the app asks for.
List<Map<String, String>> createImageLinks(Object? link) {
  if (link is! String || link.isEmpty) return [];
  // Any `-WxH.ext` size, not just the three we emit: a 250x250 or 350x350 URL
  // used to pass through labelled 500x500 and so never got the large render.
  final m = _sizeSuffix.firstMatch(link);
  if (m != null) {
    return [
      for (final quality in _imageSizes)
        {
          'quality': quality,
          'link': link.replaceRange(
            m.start + 1,
            m.start + 1 + '${m[1]}x${m[2]}'.length,
            quality,
          ),
        },
    ];
  }
  // Unfamiliar pattern: pass through.
  return [
    {'quality': '500x500', 'link': link},
  ];
}

Map<String, Object?> _extractAll(Object? data, Map<String, Object> config) => {
  for (final e in config.entries) e.key: ex(data, e.value),
};

List<Object?> _asList(Object? v) => v is List ? v : const [];

List<Object?> _mapArtists(Object? artists, {required bool withRole}) => [
  for (final a in _asList(or([artists, const []])))
    clean({
      'id': or([getToken(str(ex(a, 'perma_url'))), ex(a, 'id')]),
      'name': ex(a, 'name'),
      if (withRole) 'role': ex(a, 'role'),
      'image': createImageLinks(ex(a, 'image')),
      'type': ex(a, 'type'),
      'url': ex(a, 'perma_url'),
    }),
];

Map<String, Object?> mapSaavnSong(Object? data) {
  final song = _extractAll(data, songListConfig);

  final token = getToken(str(or([song['token'], ex(song, 'url'), ''])));
  final albumUrl = song['albumUrl'];
  final hasAlbumUrl = albumUrl is String && albumUrl.contains('/album/');
  final mediaUrls = song['mediaUrls'];

  return clean({
    'id': or([token, song['id']]),
    'songId': song['id'],
    'token': token,
    'title': isValidTitle(song['title'])
        ? song['title']
        : or([ex(song, 'song'), ex(song, 'name'), 'Unknown Song']),
    'subtitle': song['subtitle'],
    'type': 'song',
    'image': createImageLinks(ex(data, songListConfig['images']!)),
    'language': song['language'],
    'year': song['year'],
    'duration': song['duration'],
    'playCount': song['playCount'],
    'mediaUrls': truthy(mediaUrls)
        ? createDownloadLinks(mediaUrls as String)
        : <Object?>[],
    'artists': _mapArtists(song['artists'], withRole: true),
    'album': {
      'id': or([hasAlbumUrl ? getToken(albumUrl) : null, song['albumId'], '']),
      'name': isValidTitle(song['album']) ? song['album'] : '',
      'url': hasAlbumUrl ? albumUrl : '',
    },
    'hasLyrics': song['hasLyrics'] == 'true',
    'copyright': song['copyright'],
    'releaseDate': song['release_date'],
    'source': 'saavn',
  });
}

Map<String, Object?> mapSaavnAlbum(Object? data) {
  final album = _extractAll(data, albumConfig);
  final token = getToken(str(or([album['token'], ex(album, 'url'), ''])));
  final list = album['list'];

  return clean({
    'id': or([token, album['id']]),
    'title': album['title'],
    'subtitle': album['subtitle'],
    'headerDesc': album['description'],
    'type': 'album',
    'image': createImageLinks(ex(data, albumConfig['images']!)),
    'language': album['language'],
    'year': album['year'],
    'songCount': album['songCount'],
    'artists': _mapArtists(album['artists'], withRole: false),
    'songs': list is List ? [for (final s in list) mapSaavnSong(s)] : [],
    'source': 'saavn',
    'url': or([album['token'], ex(album, 'url')]),
  });
}

Map<String, Object?> mapSaavnArtist(Object? data) {
  final url = ex(data, artistMetaConfig['token']!);
  final id = ex(data, artistMetaConfig['id']!);
  return clean({
    'id': or([getToken(str(url)), id]),
    'name': ex(data, artistMetaConfig['title']!),
    'subtitle': ex(data, artistMetaConfig['subtitle']!),
    'image': createImageLinks(ex(data, artistMetaConfig['images']!)),
    'followers': ex(data, artistMetaConfig['followers']!),
    'type': 'artist',
    'url': url,
    'bio': ex(data, artistMetaConfig['bio']!),
  });
}

Map<String, Object?> mapSaavnPlaylist(Object? data) {
  final url = ex(data, albumConfig['token']!);
  final id = ex(data, albumConfig['id']!);
  final list = prop(data, 'list');
  return clean({
    'id': or([getToken(str(url)), id]),
    'title': ex(data, albumConfig['title']!),
    'subtitle': ex(data, albumConfig['subtitle']!),
    'type': 'playlist',
    'image': createImageLinks(ex(data, albumConfig['images']!)),
    'songCount': ex(data, albumConfig['songCount']!),
    'followers': ex(data, albumConfig['followerCount']!),
    'description': ex(data, albumConfig['description']!),
    'songs': list is List ? [for (final s in list) mapSaavnSong(s)] : [],
    'source': 'saavn',
    'url': url,
  });
}

Map<String, Object?> mapSaavnChannel(Object? data) {
  final url = ex(data, homeConfig['token']!);
  final id = ex(data, homeConfig['id']!);
  final language = ex(data, homeConfig['language']!);
  final stationType = ex(data, homeConfig['stationType']!);
  return clean({
    'id': or([id, getToken(str(url))]),
    'title': ex(data, homeConfig['title']!),
    'subtitle': or([ex(data, homeConfig['subtitle']!), language]),
    'type': truthy(stationType) ? 'radio_station' : 'channel',
    'image': createImageLinks(ex(data, homeConfig['images']!)),
    'language': language,
    'stationType': stationType,
    'source': 'saavn',
    'url': url,
  });
}
