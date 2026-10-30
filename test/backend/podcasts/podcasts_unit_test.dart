import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunoh/backend/local_backend.dart';
import 'package:sunoh/backend/podcasts/country.dart';
import 'package:sunoh/backend/podcasts/itunes.dart';
import 'package:sunoh/backend/podcasts/mappers.dart';
import 'package:sunoh/backend/podcasts/podcast_index_client.dart';
import 'package:sunoh/backend/podcasts/routes.dart';

/// Canned upstream: path suffix -> JSON body; records requests.
class _Upstream implements HttpClientAdapter {
  _Upstream(this.replies);
  final Map<String, String> replies;
  final seen = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seen.add(options);
    final key = replies.keys.firstWhere(
      (k) => options.path.endsWith(k),
      orElse: () => '',
    );
    return ResponseBody.fromString(
      replies[key] ?? '{}',
      key.isEmpty ? 404 : 200,
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('auth headers: sha1(key+secret+time), lowercase hex', () {
    final h = podcastAuthHeaders('k', 's', 1700000000);
    expect(h['X-Auth-Key'], 'k');
    expect(h['X-Auth-Date'], '1700000000');
    expect(
      h['Authorization'],
      sha1.convert(utf8.encode('ks1700000000')).toString(),
    );
    expect(h['Authorization'], matches(RegExp(r'^[0-9a-f]{40}$')));
    expect(h['User-Agent'], isNotEmpty);
  });

  test('cleanParams drops null and empty', () {
    expect(cleanParams({'a': 1, 'b': null, 'c': '', 'd': true}), {
      'a': '1',
      'd': 'true',
    });
  });

  group('country', () {
    test('explicit beats device', () {
      expect(resolveCountry(explicit: 'us', deviceCountry: 'IN'), 'US');
    });
    test('unsupported explicit falls to device', () {
      expect(resolveCountry(explicit: 'FR', deviceCountry: 'us'), 'US');
    });
    test('nothing usable gives the default', () {
      expect(resolveCountry(explicit: 'x', deviceCountry: 'DE'), 'IN');
      expect(resolveCountry(), 'IN');
    });
  });

  group('mappers', () {
    test('show', () {
      final m = mapPodcastShow({
        'id': 42,
        'title': 'T',
        'author': 'A',
        'description': '',
        'image': 'i.png',
        'artwork': 'a.png',
        'categories': {'55': 'News', '59': 'Daily'},
        'itunesId': 0,
        'url': 'u',
      });
      expect(m['id'], '42');
      expect(m['subtitle'], 'A');
      expect(m.containsKey('description'), isFalse);
      expect(m.containsKey('itunesId'), isFalse);
      expect(m['categories'], ['News', 'Daily']);
      expect(m['image'], [
        {'quality': '150x150', 'link': 'i.png'},
        {'quality': '500x500', 'link': 'a.png'},
      ]);
      expect(m['type'], 'podcast');
    });

    test('single image yields one tier', () {
      expect(buildImages('x', null), hasLength(1));
      expect(buildImages('x', 'x'), hasLength(1));
      expect(buildImages(null, null), isEmpty);
    });

    test('episode', () {
      final m = mapPodcastEpisode({
        'id': 7,
        'title': 'E',
        'feedTitle': 'Show',
        'enclosureUrl': 'https://a/b.mp3',
        'duration': 90,
        'explicit': 1,
        'episode': 0,
        'feedId': 3,
      });
      expect(m['mediaUrls'], [
        {'quality': 'default', 'link': 'https://a/b.mp3'},
      ]);
      expect(m['explicit'], true);
      expect(m.containsKey('episode'), isFalse);
      expect(m['subtitle'], 'Show');
      expect(m['type'], 'episode');
      expect(
        mapPodcastEpisode({'id': 1, 'explicit': 0}).containsKey('explicit'),
        isFalse,
      );
    });

    test('lists tolerate null', () {
      expect(mapPodcastShows(null), isEmpty);
      expect(mapPodcastEpisodes('x'), isEmpty);
    });
  });

  test('apple chart parsing skips malformed entries', () {
    expect(
      parseAppleChart({
        'feed': {
          'entry': [
            {
              'id': {
                'attributes': {'im:id': '123'},
              },
            },
            {'id': {}},
            'junk',
          ],
        },
      }),
      ['123'],
    );
    expect(parseAppleChart(null), isEmpty);
  });

  group('routes', () {
    Dio build(_Upstream up, {String key = 'k'}) {
      final pi = PodcastIndexClient(
        dio: Dio()..httpClientAdapter = up,
        key: key,
        secret: key.isEmpty ? '' : 's',
        now: () => 1700000000,
      );
      final r = LocalRoutes();
      registerPodcastRoutes(r, client: pi);
      return Dio(BaseOptions(baseUrl: 'https://x.test'))
        ..interceptors.add(LocalBackendInterceptor(r));
    }

    test('unconfigured gives a clear 503', () async {
      final dio = build(_Upstream({}), key: '');
      await expectLater(
        dio.get('/podcasts/categories'),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'code',
            503,
          ),
        ),
      );
    });

    test('search envelope and params', () async {
      final up = _Upstream({
        '/search/byterm': '{"feeds":[{"id":1,"title":"Hi"}]}',
      });
      final res = await build(
        up,
      ).get('/podcasts/search', queryParameters: {'q': ' hi '});
      expect(res.data['message'], 'Search results');
      expect(res.data['source'], 'podcastindex');
      expect(res.data['data']['query'], 'hi');
      expect(res.data['data']['count'], 1);
      expect(up.seen.single.queryParameters['fulltext'], 'true');
      expect(up.seen.single.queryParameters['max'], '30');
      expect(up.seen.single.headers['X-Auth-Date'], '1700000000');
    });

    test('empty search is a 400', () async {
      await expectLater(
        build(_Upstream({})).get('/podcasts/search'),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'code',
            400,
          ),
        ),
      );
    });

    test('missing episode is a 404', () async {
      final dio = build(_Upstream({'/episodes/byguid': '{"episode":null}'}));
      await expectLater(
        dio.get('/podcasts/episode/g'),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'code',
            404,
          ),
        ),
      );
    });
  });
}
