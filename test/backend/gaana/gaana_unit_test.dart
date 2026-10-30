import 'package:flutter_test/flutter_test.dart';
import 'package:sunoh/backend/gaana/gaana.dart';

// Produced independently with `openssl enc -aes-128-cbc` under the key
// words from src/gaana/crypto.ts, so this checks the port against another
// AES implementation, not against itself. Layout: offset digit "3", two
// padding chars (the IV starts at index 3, digit included), 16-char IV, base64.
const _vector =
    '3xyabcdefghijklmnopxIXVQEx0MEq81YZQSo5pjrjRsmDs+d4VOYscb2Ur8Ppv4FD+qDhwqps5ipGkn/W/';

void main() {
  group('decryptGaanaUrl', () {
    test('decrypts a known vector to the https URL', () {
      expect(
        decryptGaanaUrl(_vector),
        'https://example.invalid/hls/track/master.m3u8',
      );
    });

    test('returns empty string on garbage, empty and null', () {
      expect(decryptGaanaUrl(''), '');
      expect(decryptGaanaUrl(null), '');
      expect(decryptGaanaUrl('x'), '');
      expect(decryptGaanaUrl('3xyabcdefghijklmnop!!!notbase64'), '');
      expect(decryptGaanaUrl('3xyabcdefghijklmnopAAAA'), '');
    });
  });

  group('mapGaanaSong', () {
    final track = {
      'seokey': 'parvati-JbDj9vrB3n',
      'track_id': '1',
      'track_title': 'Parvati',
      'album_id': '9',
      'album_title': 'An Album',
      'albumseokey': 'an-album',
      'language': 'Hindi',
      'release_date': '2024-05-01',
      'duration': 215,
      'total_favourite_count': 42,
      'atw': 'https://a10.gaanacdn.com/x/size_m_1.jpg',
      'artist': [
        {'name': 'A', 'artist_id': '7', 'seokey': 'a-seo'},
        {'name': 'B', 'artist_id': '8'},
      ],
      'urls': {
        'high': {'message': _vector},
        'bad': {'message': 'nope'},
      },
    };

    test('maps ids, strings and fallbacks', () {
      final s = mapGaanaSong(track);
      expect(s['id'], 'parvati-JbDj9vrB3n');
      expect(s['title'], 'Parvati');
      expect(s['subtitle'], 'A, B');
      expect(s['year'], '2024');
      expect(s['releaseDate'], '2024-05-01');
      expect(s['duration'], 215);
      expect(s['playCount'], '42');
      expect(s['hasLyrics'], false);
      expect(s['album'], {
        'id': 'an-album',
        'name': 'An Album',
        'url': 'an-album',
      });
      expect((s['artists'] as List).first['id'], 'a-seo');
      expect((s['artists'] as List).last['id'], '8');
      // role is undefined in the source, so the key must be absent.
      expect((s['artists'] as List).first.containsKey('role'), false);
    });

    test('keeps only media urls that decrypt', () {
      final urls = mapGaanaSong(track)['mediaUrls'] as List;
      expect(urls, [
        {
          'quality': 'high',
          'link': 'https://example.invalid/hls/track/master.m3u8',
        },
      ]);
    });

    test('image links follow the size_ pattern', () {
      final img = mapGaanaSong(track)['image'] as List;
      expect(img.map((e) => e['quality']), [
        '50x50',
        '150x150',
        '500x500',
        '1200x1200',
      ]);
      expect(img.first['link'], 'https://a10.gaanacdn.com/x/size_s_1.jpg');
      expect(img[2]['link'], 'https://a10.gaanacdn.com/x/size_l_1.jpg');
      expect(img.last['link'], 'https://a10.gaanacdn.com/x/size_xxl_1.jpg');
    });
  });

  group('images', () {
    test('crop_ urls and size_xl', () {
      final c = createGaanaImageLinks('https://h/crop_175x175/a.jpg');
      expect(c.last['link'], 'https://h/crop_480x480/a.jpg');
      final xl = createGaanaImageLinks('https://h/size_xl_1.jpg');
      expect(xl.first['link'], 'https://h/size_s_1.jpg');
    });

    test('atwj JSON string is preferred and parsed', () {
      final img = getGaanaImagery({
        'atwj': '{"size_m":"https://h/size_m_2.jpg"}',
        'atw': 'https://h/size_m_other.jpg',
      });
      expect(img.first['link'], 'https://h/size_s_2.jpg');
    });

    test('no image fields gives an empty list', () {
      expect(getGaanaImagery({'name': 'x'}), isEmpty);
    });
  });

  group('album, playlist, artist, entity', () {
    test('album headerDesc renders missing values like JS', () {
      final a = mapGaanaAlbum({
        'seokey': 'al',
        'name': 'N',
        'language': 'Hindi',
      });
      expect(a['headerDesc'], 'Album • Hindi • undefined');
      expect(a['songs'], isEmpty);
      expect(a.containsKey('year'), false);
    });

    test('album songCount prefers track_ids length', () {
      final a = mapGaanaAlbum({
        'seokey': 'al',
        'entity_info': [
          {
            'key': 'track_ids',
            'value': ['1', '2', '3'],
          },
        ],
        'trackcount': 9,
      });
      expect(a['songCount'], '3');
    });

    test('playlist and artist stringify counts', () {
      final p = mapGaanaPlaylist({'seokey': 'p', 'name': 'P', 'count': 50});
      expect(p['songCount'], '50');
      final r = mapGaanaArtist({'seokey': 'r', 'name': 'R', 'songs': 12});
      expect(r['songCount'], '12');
      expect(r['type'], 'artist');
    });

    test('mapGaanaEntity dispatches and passes unknown through', () {
      expect(mapGaanaEntity({'entity_type': 'PL', 'seokey': 'p'}), isA<Map>());
      expect(
        (mapGaanaEntity({'entity_type': 'RL', 'name': 'x'}) as Map)['type'],
        'radio_station',
      );
      expect(
        (mapGaanaEntity({'entity_type': 'OC', 'name': 'x'}) as Map)['type'],
        'occasion',
      );
      final raw = {'entity_type': 'ZZ'};
      expect(mapGaanaEntity(raw), same(raw));
    });
  });

  group('helpers', () {
    test('search groups are normalised and empty groups dropped', () {
      final out = gaanaSearchMapper({
        'gr': [
          {
            'ty': 'Track',
            'stxt': 'Songs',
            'gd': [
              {
                'id': '1',
                'ti': 'T',
                'seo': 't-seo',
                'ty': 'Track',
                'sti': 'X, Y',
                'aw': 'https://h/size_m_1.jpg',
              },
            ],
          },
          {'ty': 'Album', 'gd': []},
        ],
      });
      expect(out, hasLength(1));
      expect(out.first['heading'], 'Songs');
      final song = (out.first['data'] as List).first as Map;
      expect(song['id'], 't-seo');
      expect(song['subtitle'], 'X, Y');
    });

    test('section mapper drops placeholder headings', () {
      final out = gaanaSectionMapper([
        {'ga_header': 'Top Picks', 'url': 'u'},
        {'ga_header': 'Untitled'},
        {
          'entity_description': 'Fallback',
          'content': {
            'entities': [1],
          },
        },
      ]);
      expect(out.map((s) => s['heading']), ['Top Picks', 'Fallback']);
      expect(out.last['entities'], [1]);
    });

    test(
      'headers carry the language cookie, capitalised and encoded',
      () async {
        final h = await getGaanaHeaders('hindi, punjabi');
        expect(h['Cookie'], '__ul=Hindi%2CPunjabi');
        expect((await getGaanaHeaders()).containsKey('Cookie'), false);
      },
    );
  });
}
