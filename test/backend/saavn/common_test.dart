import 'package:flutter_test/flutter_test.dart';
import 'package:sunoh/backend/common.dart';

// Encrypted with the TS createDownloadLinks key via crypto-js (DES, ECB,
// PKCS7), so a pass here means Dart decrypts what the server decrypts.
const _enc96 =
    'ID2ieOjCrwfgWvL5sXl4B1ImC5QfbsDyQd+aqn5Yzr3aGttEjbIm9m+XHLUinhCK';
const _enc160 = 'ID2ieOjCrwfV6LxSR1XCFYNHW5/d+XV3aC4g2XuVLUjH/44gfyKFgw==';
const _encPlain = 'ID2ieOjCrwfV6LxSR1XCFcs87EwN1Bvsg/MVov9or3s=';

void main() {
  group('createDownloadLinks', () {
    test('fans out every bitrate from a _96 link', () {
      final out = createDownloadLinks(_enc96) as List;
      expect(out.map((q) => (q as Map)['quality']), [
        '12kbps',
        '48kbps',
        '96kbps',
        '160kbps',
        '320kbps',
      ]);
      expect(
        (out[0] as Map)['link'],
        'https://aac.saavncdn.com/123/abcdef_12.mp4',
      );
      expect(
        (out[4] as Map)['link'],
        'https://aac.saavncdn.com/123/abcdef_320.mp4',
      );
    });

    test('only the first marker occurrence is rewritten', () {
      final out = createDownloadLinks(_enc160) as List;
      expect((out[1] as Map)['link'], 'https://x.example/a/b_48.mp4?x=1');
    });

    test('returns the bare string when no bitrate marker is present', () {
      expect(createDownloadLinks(_encPlain), 'https://x.example/plain.mp4');
    });
  });

  group('common', () {
    test('case helpers', () {
      expect(toCamelCase('new_albums'), 'newAlbums');
      expect(toCamelCase('Top-Shows now'), 'topShowsNow');
      expect(toSentenceCase('top_playlists'), 'Top Playlists');
      expect(toSentenceCase('newTrending'), 'New Trending');
      expect(capitalizeFirstLetter('albums'), 'Albums');
    });

    test('tokens', () {
      expect(
        getToken('https://www.jiosaavn.com/song/x/KQE9fDgEbVw'),
        'KQE9fDgEbVw',
      );
      expect(
        getToken('https://www.jiosaavn.com/song/x/KQE9fDgEbVw/'),
        'KQE9fDgEbVw',
      );
      expect(getToken(''), '');
      expect(extractToken('a/b/c'), 'c');
      expect(extractToken('a/b/'), isNull);
    });

    test('validators', () {
      expect(isValidArray([1]), isTrue);
      expect(isValidArray([]), isFalse);
      expect(isValidArray(null), isFalse);
      expect(isValidObject({}), isTrue);
      expect(isValidObject([]), isFalse);
      expect(isValidTitle('Unknown'), isFalse);
      expect(isValidTitle('12345'), isFalse);
      expect(isValidTitle('  '), isFalse);
      expect(isValidTitle(null), isFalse);
      expect(isValidTitle('Tum Hi Ho'), isTrue);
    });

    test('detectLanguage', () {
      expect(detectLanguage('best Punjabi songs'), 'punjabi');
      expect(detectLanguage('xyz'), isNull);
      expect(detectLanguage(''), isNull);
    });

    test('promiseAllLimit keeps order and caps concurrency', () async {
      var live = 0, peak = 0;
      final out = await promiseAllLimit<int, int>(
        List.generate(8, (i) => i),
        3,
        (i) async {
          live++;
          if (live > peak) peak = live;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          live--;
          return i * 2;
        },
      );
      expect(out, [0, 2, 4, 6, 8, 10, 12, 14]);
      expect(peak, lessThanOrEqualTo(3));
    });
  });
}
