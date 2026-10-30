import 'package:flutter_test/flutter_test.dart';
import 'package:sunoh/api/art_urls.dart';
import 'package:sunoh/backend/gaana/mapper.dart';
import 'package:sunoh/backend/podcasts/mappers.dart';
import 'package:sunoh/backend/saavn/mapper.dart';
import 'package:sunoh/backend/spotify/scraper.dart';

void main() {
  group('Saavn', () {
    test('fans one size out to 50, 150 and 500, best last', () {
      final l = createImageLinks('https://c.saavncdn.com/1/x-150x150.jpg');
      expect(l.map((e) => e['quality']), ['50x50', '150x150', '500x500']);
      expect(l.last['link'], 'https://c.saavncdn.com/1/x-500x500.jpg');
    });

    test('an unusual size such as 350x350 is rewritten, not mislabelled', () {
      final l = createImageLinks('https://c.saavncdn.com/1/x-350x350.jpg');
      expect(l.last['link'], 'https://c.saavncdn.com/1/x-500x500.jpg');
      expect(l.first['link'], 'https://c.saavncdn.com/1/x-50x50.jpg');
    });
  });

  group('Gaana', () {
    test('size_ URLs fan out and the large rung is last', () {
      final l = createGaanaImageLinks(
        'https://a10.gaanacdn.com/x/size_m_1.jpg',
      );
      expect(l.last['link'], contains('size_xxl'));
      expect(l.last['quality'], '1200x1200');
    });

    test('a crop_ URL has no xxl rung', () {
      final l = createGaanaImageLinks('https://h/crop_175x175/a.jpg');
      expect(l.last['quality'], '500x500');
    });

    test('a size_xxl cover falls back to size_xl, then size_l', () {
      expect(
        artUrlChain('https://a10.gaanacdn.com/gn_img/albums/a/b/size_xxl.jpg'),
        [
          'https://a10.gaanacdn.com/gn_img/albums/a/b/size_xxl.jpg',
          'https://a10.gaanacdn.com/gn_img/albums/a/b/size_xl.jpg',
          'https://a10.gaanacdn.com/gn_img/albums/a/b/size_l.jpg',
        ],
      );
    });

    test('a size map yields its largest field', () {
      expect(
        getGaanaImageUrl({'size_s': 's', 'size_m': 'm', 'size_l': 'l'}),
        'l',
      );
    });
  });

  group('podcasts', () {
    test(
      'the large tier prefers artwork and is upscaled when Apple-hosted',
      () {
        final l = buildImages(
          'https://x/small.jpg',
          'https://is1-ssl.mzstatic.com/image/thumb/a/b.jpg/100x100bb.jpg',
        );
        expect(l.last['link'], endsWith('/1200x1200bb.jpg'));
        expect(l.first['link'], 'https://x/small.jpg');
      },
    );
  });

  group('Spotify', () {
    test('largestSourceUrl picks the widest, whatever the order', () {
      expect(
        largestSourceUrl([
          {'url': 'a', 'width': 64},
          {'url': 'c', 'width': 640},
          {'url': 'b', 'width': 300},
        ]),
        'c',
      );
      expect(
        largestSourceUrl([
          {'url': 'only'},
        ]),
        'only',
      );
      expect(largestSourceUrl(null), isNull);
    });
  });
}
