import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunoh/backend/gaana/gaana.dart' as gaana;
import 'package:sunoh/backend/local_backend.dart';
import 'package:sunoh/backend/music/home_merge.dart';
import 'package:sunoh/backend/music/routes.dart';
import 'package:sunoh/backend/music/search_merge.dart';

Map<String, Object?> item(String title, {String? artist}) => {
  'title': title,
  'subtitle': ?artist,
};

Map<String, Object?> section(String heading, List<Object?> data, String src) =>
    {'heading': heading, 'data': data, 'source': src};

List<String> titles(Object? data) => [
  for (final i in data! as List) (i as Map)['title'] as String,
];

class _NoNetwork implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => throw StateError('fell through to the network');

  @override
  void close({bool force = false}) {}
}

void main() {
  group('home merge', () {
    test('same-named shelves merge, Saavn first then Gaana interleaved', () {
      final out = mergeHomeSections(
        [
          section('Top Charts', [item('S1'), item('S2'), item('S3')], 'saavn'),
        ],
        [
          section('City Top Charts', [item('G1'), item('G2')], 'gaana'),
        ],
      );
      expect(out, hasLength(1));
      expect(out.single['heading'], 'Top Charts');
      expect(out.single['source'], 'unified');
      expect(titles(out.single['data']), ['S1', 'G1', 'S2', 'G2', 'S3']);
    });

    test('untitled items are dropped and empty leftover shelves vanish', () {
      final out = mergeHomeSections([
        section('Moods', [item('Untitled'), item('12345')], 'saavn'),
        section('Charts', [item('Real'), item('unknown')], 'saavn'),
      ], []);
      expect(out, hasLength(1));
      expect(titles(out.single['data']), ['Real']);
    });

    test('priority shelves lead, leftovers alternate saavn / gaana', () {
      final out = mergeHomeSections(
        [
          section('Radio', [item('R')], 'saavn'),
          section('Trending Now', [item('T')], 'saavn'),
          section('A', [item('a')], 'saavn'),
          section('B', [item('b')], 'saavn'),
        ],
        [
          section('Recommended for you', [item('g')], 'gaana'),
          section('C', [item('c')], 'gaana'),
        ],
      );
      expect(
        [for (final s in out) s['heading']],
        ['Trending', 'Radio', 'A', 'Recommended for you', 'B', 'C'],
      );
    });

    test('malformed sections are skipped', () {
      final out = mergeHomeSections(
        [
          null,
          {'heading': 'x'},
        ],
        [
          section('X', [item('ok')], 'gaana'),
        ],
      );
      expect(out, hasLength(1));
    });
  });

  group('search merge', () {
    test('dedupe keys on alphanumeric title + first artist', () {
      final out = dedupeItems([
        item('Kesariya!', artist: 'Arijit Singh, Pritam'),
        item('kesariya', artist: 'arijit singh'),
        item('Kesariya', artist: 'Someone Else'),
        item('Untitled'),
        null,
      ]);
      expect(out, hasLength(2));
      expect(dedupeItems('nope'), isEmpty);
    });

    test('artists[0].name beats subtitle', () {
      final out = dedupeItems([
        {
          'title': 'X',
          'artists': [
            {'name': 'A'},
          ],
          'subtitle': 'B',
        },
        {'title': 'X', 'subtitle': 'A'},
      ]);
      expect(out, hasLength(1));
    });

    test('heading normalisation', () {
      expect(normalizeHeading(' Top Query '), 'topresults');
      expect(normalizeHeading('Track'), 'songs');
      expect(normalizeHeading('Playlist'), 'playlists');
    });

    test('type=all: Gaana All replaces the Saavn hero, categories merge', () {
      final saavn = [
        section('Top Result', [item('old')], 'saavn'),
        section('Songs', [item('Kesariya', artist: 'Arijit')], 'saavn'),
      ];
      final gaanaSecs = [
        section('All', [item('hero')], 'gaana'),
        section('Songs', [
          item('kesariya', artist: 'arijit'),
          item('Deva Deva', artist: 'Arijit'),
        ], 'gaana'),
        section('Albums', [item('Brahmastra')], 'gaana'),
      ];
      final out =
          mergeSearchResults(saavn, gaanaSecs, 'all')!
              as List<Map<String, Object?>>;
      expect(
        [for (final s in out) s['heading']],
        ['Top Results', 'Songs', 'Albums'],
      );
      expect(out[0]['source'], 'gaana');
      expect(titles(out[1]['data']), ['Kesariya', 'Deva Deva']);
      expect(out[1]['source'], 'unified');
      expect(out[2]['source'], 'gaana');
    });

    test('type=all with Saavn empty still leads with the Gaana hero', () {
      final out =
          mergeSearchResults([], [
                section('All', [item('hero')], 'gaana'),
              ], 'all')!
              as List;
      expect((out.single as Map)['heading'], 'Top Results');
    });

    test('type=playlists takes only Gaana Playlists / Mix', () {
      final out =
          mergeSearchResults(
                {
                  'list': [item('P1')],
                },
                [
                  section('Mix', [item('M1')], 'gaana'),
                  section('Songs', [item('no')], 'gaana'),
                ],
                'playlists',
              )!
              as Map;
      expect(titles(out['list']), ['P1', 'M1']);
      expect(out['source'], 'unified');
    });

    test('other typed lists merge the matching Gaana heading only', () {
      final out =
          mergeSearchResults(
                {
                  'list': [item('A1')],
                },
                [
                  section('Albums', [item('A2')], 'gaana'),
                ],
                'albums',
              )!
              as Map;
      expect(titles(out['list']), ['A1', 'A2']);
      final untouched =
          mergeSearchResults(
                {
                  'list': [item('A1')],
                },
                [
                  section('Songs', [item('S')], 'gaana'),
                ],
                'albums',
              )!
              as Map;
      expect(untouched.containsKey('source'), isFalse);
    });
  });

  group('routing', () {
    test('byProvider is an exact match with a fallback', () async {
      final c = byProvider({
        'gaana': (p, q) async => const LocalReply('g'),
      }, (p, q) async => const LocalReply('f'));
      expect((await c({}, {'provider': 'gaana'})).data, 'g');
      expect((await c({}, {'provider': 'Gaana'})).data, 'f');
      expect((await c({}, {})).data, 'f');
    });

    late Dio dio;
    setUp(() {
      final routes = LocalRoutes();
      registerMusicRoutes(routes);
      dio = Dio(BaseOptions(baseUrl: 'https://x.test'))
        ..httpClientAdapter = _NoNetwork()
        ..interceptors.add(LocalBackendInterceptor(routes));
    });

    test('languages is answered locally', () async {
      final r = await dio.get<Map<String, dynamic>>('/music/languages');
      expect(r.data!['status'], 'success');
      expect(r.data!['message'], 'Languages fetched successfully');
      expect((r.data!['data'] as List).first, {
        'name': 'Hindi',
        'value': 'hindi',
      });
      expect(r.data!['data'] as List, hasLength(17));
    });

    test(
      'unsupported provider combinations fail with the server text',
      () async {
        for (final (path, text) in [
          (
            '/music/song/abc/stream',
            'Song streams are only supported for Gaana provider currently',
          ),
          (
            '/music/occasions',
            'Occasions are only supported for Gaana provider currently',
          ),
          (
            '/music/occasions/x',
            'Occasion details are only supported for Gaana and Saavn provider '
                'currently',
          ),
          ('/music/radio/bogus', 'Invalid session ID format'),
          ('/music/recommend', 'Could not identify a song for recommendations'),
        ]) {
          try {
            await dio.get<Object?>(path);
            fail('$path should fail');
          } on DioException catch (e) {
            expect(e.response?.statusCode, 400, reason: path);
            expect((e.response!.data as Map)['message'], text, reason: path);
          }
        }
      },
    );

    test('gaana radio sessions need no network', () async {
      final r = await dio.get<Map<String, dynamic>>(
        '/music/radio/session',
        queryParameters: {'id': 'abc', 'type': 'featured', 'provider': 'gaana'},
      );
      expect(r.data!['data'], {'stationId': 'gaana_abc'});
      expect(r.data!['source'], 'unified');
    });

    test('registering installs the Saavn song-section hook', () {
      gaana.saavnSongSections = null;
      registerMusicRoutes(LocalRoutes());
      expect(gaana.saavnSongSections, isNotNull);
    });
  });
}
