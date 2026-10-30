import 'package:flutter_test/flutter_test.dart';
import 'package:sunoh/backend/saavn/saavn.dart' as saavn;

import 'shape_diff.dart';

// Encrypts 'https://aac.saavncdn.com/123/abcdef_96.mp4' (see common_test).
const _enc96 =
    'ID2ieOjCrwfgWvL5sXl4B1ImC5QfbsDyQd+aqn5Yzr3aGttEjbIm9m+XHLUinhCK';

// A trimmed `webapi.get?type=song` item: only the fields the mapper reads.
Map<String, Object?> _rawSong() => {
  'id': 'YiVML4Zo',
  'title': 'Gehra Hua (From &quot;Dhurandhar&quot;)',
  'subtitle': 'Shashwat Sachdev - Gehra Hua',
  'type': 'song',
  'image': 'https://c.saavncdn.com/450/Gehra-Hua-150x150.jpg',
  'language': 'hindi',
  'year': '2025',
  'play_count': '123',
  'perma_url': 'https://www.jiosaavn.com/song/gehra-hua/KQE9fDgEbVw',
  'more_info': {
    'album': 'Dhurandhar',
    'album_id': '99',
    'album_url': 'https://www.jiosaavn.com/album/dhurandhar/Zk5',
    'encrypted_media_url': _enc96,
    'duration': '248',
    'copyright_text': '(C) 2025',
    'release_date': '2025-12-05',
    'has_lyrics': 'true',
    'artistMap': {
      'artists': [
        {
          'id': '1',
          'name': 'Arijit Singh',
          'role': 'singer',
          'image': 'https://c.saavncdn.com/a/x-50x50.jpg',
          'type': 'artist',
          'perma_url':
              'https://www.jiosaavn.com/artist/arijit-singh/LlRWpHzy3Hc_',
        },
      ],
    },
  },
};

void main() {
  group('mappers', () {
    test('image links fan out sizes', () {
      final out = saavn.createImageLinks('https://c/a-150x150.jpg');
      expect(out.map((e) => e['quality']), ['50x50', '150x150', '500x500']);
      expect(out.first['link'], 'https://c/a-50x50.jpg');
      expect(saavn.createImageLinks('https://c/a.jpg'), [
        {'quality': '500x500', 'link': 'https://c/a.jpg'},
      ]);
      expect(saavn.createImageLinks(null), isEmpty);
    });

    test('song', () {
      final s = saavn.mapSaavnSong(_rawSong());
      expect(s['id'], 'KQE9fDgEbVw');
      expect(s['songId'], 'YiVML4Zo');
      expect(s['token'], 'KQE9fDgEbVw');
      expect(s['type'], 'song');
      expect(s['year'], '2025');
      expect(s['hasLyrics'], isTrue);
      expect(s['releaseDate'], '2025-12-05');
      expect((s['mediaUrls'] as List).length, 5);
      expect((s['album'] as Map)['id'], 'Zk5');
      expect((s['album'] as Map)['url'], contains('/album/'));
      final artist = (s['artists'] as List).single as Map;
      expect(artist['id'], 'LlRWpHzy3Hc_');
      expect(artist['role'], 'singer');
      expect((artist['image'] as List).length, 3);
    });

    test('song omits absent fields instead of nulling them', () {
      final s = saavn.mapSaavnSong({'id': 'abc', 'title': 'Hello'});
      expect(s.containsKey('subtitle'), isFalse);
      expect(s.containsKey('language'), isFalse);
      expect(s['mediaUrls'], <Object?>[]);
      expect(s['album'], {'id': '', 'name': '', 'url': ''});
      expect(s['id'], 'abc');
    });

    test('song with a placeholder title falls back', () {
      final s = saavn.mapSaavnSong({'id': 'abc', 'title': 'Unknown'});
      expect(s['title'], 'Unknown Song');
    });

    test('album', () {
      final a = saavn.mapSaavnAlbum({
        'id': '9',
        'title': 'Dhurandhar',
        'subtitle': 'Various',
        'header_desc': 'desc',
        'perma_url': 'https://www.jiosaavn.com/album/dhurandhar/Zk5',
        'image': 'https://c/a-150x150.jpg',
        'year': '2025',
        'list': [_rawSong()],
        'more_info': {'song_count': '7'},
      });
      expect(a['id'], 'Zk5');
      expect(a['headerDesc'], 'desc');
      expect(a['songCount'], '7');
      expect(a['url'], 'https://www.jiosaavn.com/album/dhurandhar/Zk5');
      expect((a['songs'] as List).length, 1);
      expect(a['artists'], <Object?>[]);
    });

    test('artist', () {
      final a = saavn.mapSaavnArtist({
        'id': '7',
        'name': 'Arijit Singh',
        'perma_url':
            'https://www.jiosaavn.com/artist/arijit-singh/LlRWpHzy3Hc_',
        'image': 'https://c/a-150x150.jpg',
        'follower_count': '5',
      });
      expect(a['id'], 'LlRWpHzy3Hc_');
      expect(a['type'], 'artist');
      expect(a['followers'], '5');
      expect(a.containsKey('bio'), isFalse);
    });

    test('playlist', () {
      final p = saavn.mapSaavnPlaylist({
        'id': '1',
        'title': 'Hits',
        'perma_url': 'https://www.jiosaavn.com/featured/hits/AbC',
        'list': [_rawSong()],
        'more_info': {'follower_count': '3', 'song_count': '1'},
      });
      expect(p['id'], 'AbC');
      expect(p['followers'], '3');
      expect((p['songs'] as List).length, 1);
    });

    test('channel and radio station tiles', () {
      final c = saavn.mapSaavnChannel({
        'id': '5',
        'title': 'Retro',
        'type': 'channel',
        'more_info': {'language': 'hindi'},
      });
      expect(c['type'], 'channel');
      expect(c['subtitle'], 'hindi');
      final r = saavn.mapSaavnChannel({
        'id': '6',
        'more_info': {'featured_station_type': 'featured'},
      });
      expect(r['type'], 'radio_station');
    });
  });

  group('helpers', () {
    test('dataSanitizer generic tile uses query as artist-station id', () {
      final d =
          saavn.dataSanitizer({
                'id': '',
                'title': 'Arijit Radio',
                'type': 'radio_station',
                'more_info': {
                  'featured_station_type': 'artist',
                  'query': 'Arijit',
                },
              })
              as Map;
      expect(d['id'], 'Arijit');
      expect(d['songId'], '');
      expect(d['stationType'], 'artist');
      expect(d['type'], 'radio_station');
      expect(d['image'], <Object?>[]);
    });

    test(
      'homeDataMapper keeps non-empty headed modules and drops podcasts',
      () {
        final out = saavn.homeDataMapper({
          'modules': {
            'new_trending': {'title': 'Trending Now'},
            'podcasts': {'title': 'Top Podcasts'},
            'history': {'title': 'History'},
          },
          'new_trending': [_rawSong()],
          'podcasts': [_rawSong()],
          'history': [_rawSong()],
          'browse_discover': [
            {'id': '1', 'title': 'Pop', 'type': 'channel'},
          ],
        });
        expect(out.map((s) => s['heading']), ['Trending Now', 'Browse']);
        expect(out.first['source'], 'saavn');
      },
    );

    test('stationSongsMapper handles both response shapes', () {
      final byList = saavn.stationSongsMapper({
        'stationid': 'st',
        'list': [_rawSong()],
      });
      expect(byList['id'], 'st');
      expect((byList['list'] as List).length, 1);

      final byKeys = saavn.stationSongsMapper({
        'stationid': 'st',
        '0': {'song': _rawSong()},
        '1': {'id': 'x', 'title': 'T'},
        'status': 'ok',
      });
      expect((byKeys['list'] as List).length, 2);
    });

    test('topSearchMapper groups and drops empty sections', () {
      final out = saavn.topSearchMapper([
        {'type': 'song', 'id': '1', 'title': 'S'},
        {'type': 'artist', 'id': '2', 'name': 'A'},
      ]);
      expect(out.map((s) => s['heading']), ['Artists', 'Songs']);
    });

    test('autoCompleteDataMapper skips shows and empty sections', () {
      final out = saavn.autoCompleteDataMapper({
        'songs': {
          'data': [_rawSong()],
        },
        'albums': {'data': []},
        'shows': {
          'data': [1],
        },
        'topquery': {
          'data': [
            {'type': 'artist', 'id': '2', 'name': 'A'},
          ],
        },
      });
      expect(out.map((s) => s['heading']), ['Songs', 'Topquery']);
    });

    test('artistDataMapper builds sections and skips podcast modules', () {
      final out = saavn.artistDataMapper({
        'id': '7',
        'name': 'A',
        'modules': {
          'topSongs': {'title': 'Top Songs'},
          'topEpisodes': {'title': 'Eps'},
          'similarArtists': {'title': 'Similar'},
        },
        'topSongs': [_rawSong()],
        'similarArtists': [
          {'id': '8', 'name': 'B'},
        ],
      });
      final sections = out['sections'] as List;
      expect(sections.map((s) => (s as Map)['heading']), [
        'Top Songs',
        'Similar',
      ]);
    });

    test('songsDetailsMapper lists recommendation modules', () {
      final out = saavn.songsDetailsMapper({
        'songs': [_rawSong()],
        'modules': {
          'reco': {
            'title': 'You might like',
            'source': 'reco.getreco',
            'source_params': {'pid': '1', 'entity_type': 'song'},
          },
        },
      });
      expect(out.songs.length, 1);
      expect(out.sections.single['module_id'], 'reco');
      expect(out.sections.single['endpoint'], 'reco.getreco');
      expect(out.sections.single['pid'], '1');
    });

    test('channelDataMapper drops sections made only of radio stations', () {
      final out = saavn.channelDataMapper({
        'modules': {
          'quick_stations': {'title': 'Stations'},
          'mixed': {'title': 'Mixed'},
        },
        'quick_stations': [
          {'id': '1', 'title': 'S', 'type': 'radio_station'},
        ],
        'mixed': [
          {'id': '1', 'title': 'S', 'type': 'radio_station'},
          {'id': '2', 'title': 'P', 'type': 'playlist'},
        ],
      });
      expect(out.map((s) => s['heading']), ['Mixed']);
      expect((out.single['data'] as List).length, 1);
    });
  });

  group('shape_diff', () {
    test('ignores values and list length, flags keys and types', () {
      expect(
        shapeDiff(
          {
            'a': 1,
            'l': [
              {'x': 'a'},
              {'x': 'b'},
            ],
          },
          {
            'a': 9,
            'l': [
              {'x': 'c'},
            ],
          },
        ),
        isEmpty,
      );
      expect(shapeDiff({'a': 1}, {'a': '1'}), isNotEmpty);
      expect(shapeDiff({'a': 1, 'b': 2}, {'a': 1}), isNotEmpty);
      expect(shapeDiff({'a': 1}, {'a': 1, 'b': 2}), isNotEmpty);
    });
  });
}
