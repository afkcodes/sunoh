import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunoh/backend/local_backend.dart';
import 'package:sunoh/backend/spotify/match.dart';
import 'package:sunoh/backend/spotify/routes.dart';
import 'package:sunoh/backend/spotify/scraper.dart';
import 'package:sunoh/backend/spotify/types.dart';

String _fx(String n) =>
    File('test/backend/spotify/fixtures/$n').readAsStringSync();

SpotifyTrack _t(
  String name,
  List<String> artists, {
  int ms = 200000,
  String? isrc,
}) => SpotifyTrack(
  id: 'id',
  name: name,
  artists: artists,
  album: '',
  durationMs: ms,
  url: 'u',
  isrc: isrc,
);

/// Answers the embed page and the GraphQL call from fixtures.
class _Fake implements HttpClientAdapter {
  _Fake({this.graphqlOk = true, this.embedOk = true});
  final bool graphqlOk;
  final bool embedOk;

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? s,
    Future<void>? c,
  ) async {
    final isGql = o.uri.host == 'api-partner.spotify.com';
    final ok = isGql ? graphqlOk : embedOk;
    final body = !ok
        ? (isGql
              ? '{"errors":[{"message":"PersistedQueryNotFound"}]}'
              : '<html>none</html>')
        : _fx(isGql ? 'graphql_playlist.json' : 'embed_playlist.html');
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [isGql ? 'application/json' : 'text/html'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('extractPlaylistId', () {
    test('accepts urls, uris and raw ids', () {
      const id = '37i9dQZF1DXcBWIGoYBM5M';
      expect(extractPlaylistId('https://open.spotify.com/playlist/$id'), id);
      expect(
        extractPlaylistId('https://open.spotify.com/playlist/$id?si=abc'),
        id,
      );
      expect(extractPlaylistId(' spotify:playlist:$id '), id);
      expect(extractPlaylistId(id), id);
    });
    test('rejects junk', () {
      expect(extractPlaylistId(null), isNull);
      expect(extractPlaylistId('  '), isNull);
      expect(extractPlaylistId('https://example.com/x'), isNull);
      expect(extractPlaylistId('short'), isNull);
    });
  });

  group('extraction', () {
    test('embed page: tracks, token, metadata; episodes skipped', () {
      final p = parseEmbedPage(_fx('embed_playlist.html'))!;
      expect(p.name, 'Today’s Top Hits');
      expect(p.token, 'FAKE-TOKEN');
      expect(p.tracks, hasLength(3));
      final t = p.tracks.first;
      expect(t.id, '7bxaFZ1O3cHkgLKMsdC3xR');
      expect(t.name, 'Loser');
      expect(t.artists, ['Tame Impala']);
      expect(t.durationMs, 223069);
      expect(t.url, 'https://open.spotify.com/track/7bxaFZ1O3cHkgLKMsdC3xR');
    });
    test('embed page without a playlist entity is null', () {
      expect(parseEmbedPage('<html></html>'), isNull);
      expect(
        parseEmbedPage(
          '<script id="__NEXT_DATA__">{"props":{"pageProps":{"status":404}}}</script>',
        ),
        isNull,
      );
    });
    test('graphql fixture through fetchSpotifyPlaylist has albums', () async {
      spotifyDioOverride = Dio()..httpClientAdapter = _Fake();
      final p = (await fetchSpotifyPlaylist('abc'))!;
      expect(p.tracks.every((t) => t.album.isNotEmpty), isTrue);
      expect(p.tracks.first.album, 'Deadbeat');
      expect(p.owner, 'Spotify');
      expect(p.artworkUrl, startsWith('https://i.scdn.co/'));
      expect(p.trackCount, p.tracks.length);
    });
    test('falls back to the embed tracks when graphql fails', () async {
      spotifyDioOverride = Dio()..httpClientAdapter = _Fake(graphqlOk: false);
      final p = (await fetchSpotifyPlaylist('abc'))!;
      expect(p.tracks, hasLength(3));
      expect(p.tracks.first.album, '');
    });
    test('missing embed page gives null', () async {
      spotifyDioOverride = Dio()..httpClientAdapter = _Fake(embedOk: false);
      expect(await fetchSpotifyPlaylist('abc'), isNull);
    });
  });

  group('match scoring (mirrors match.ts)', () {
    test('norm folds case, accents and punctuation', () {
      expect(norm('Beyoncé – Déjà Vu!'), 'beyonce deja vu');
      expect(norm(null), '');
    });
    test('titleSimilarity', () {
      expect(titleSimilarity('Loser', 'loser!'), 1);
      expect(titleSimilarity('', 'x'), 0);
      // jaccard 0.5 * 0.7 + overlap (5 of 10 chars) 0.5 * 0.3
      expect(titleSimilarity('Hello World', 'Hello'), closeTo(0.5, 1e-9));
    });
    test('artistMatch is the share of Spotify artists Saavn lists', () {
      expect(artistMatch(['Tame Impala', 'KAROL G'], 'Tame Impala, Foo'), 0.5);
      expect(artistMatch([], 'x'), 0);
    });
    test('score: perfect, neutral duration, duration penalty', () {
      final t = _t('Loser', ['Tame Impala']);
      expect(
        score(t, {
          'title': 'Loser',
          'primaryArtists': 'Tame Impala',
          'duration': '200',
        }),
        closeTo(1.0, 1e-9),
      );
      // No candidate duration: neutral 0.5 * 0.15.
      expect(
        score(t, {'name': 'Loser', 'music': 'Tame Impala'}),
        closeTo(0.55 + 0.3 + 0.075, 1e-9),
      );
      // 100 s against 200 s: ratio 0.5 -> d 0.5.
      expect(
        score(t, {'title': 'Loser', 'singers': 'Tame Impala', 'duration': 100}),
        closeTo(0.55 + 0.3 + 0.075, 1e-9),
      );
    });
    test('buildQueries cleans annotations and de-dups', () {
      final t = _t('Song (Remastered Version) [Live] feat. X', ['A', 'B', 'C']);
      expect(buildQueries(t), ['Song A B', 'Song A', 'Song']);
      expect(buildQueries(_t('Solo', ['A'])), ['Solo A', 'Solo']);
    });
    test(
      'matchOne stops at the first non-empty query, applies threshold',
      () async {
        final seen = <String>[];
        Future<List<Map<String, Object?>>> search(String q) async {
          seen.add(q);
          return q == 'Loser Tame Impala'
              ? [
                  {
                    'title': 'Other',
                    'primaryArtists': 'Nobody',
                    'duration': '10',
                  },
                  {
                    'title': 'Loser',
                    'primaryArtists': 'Tame Impala',
                    'duration': '200',
                  },
                ]
              : [];
        }

        final m = await matchOne(_t('Loser', ['Tame Impala']), search: search);
        expect(seen, ['Loser Tame Impala']);
        expect(m['matched'], isTrue);
        expect(m['query'], 'Loser Tame Impala');
        expect(m['candidatesConsidered'], 2);
        expect((m['saavn']! as Map)['title'], 'Loser');
      },
    );
    test('matchOne with no hits is unmatched with score 0', () async {
      final m = await matchOne(
        _t('Loser', ['Tame Impala'], isrc: 'X1'),
        search: (_) async => [],
      );
      expect(m['matched'], isFalse);
      expect(m['saavn'], isNull);
      expect(m['score'], 0);
      expect(m['query'], '');
    });
    test('matchOne below threshold keeps the candidate', () async {
      final m = await matchOne(
        _t('Loser', ['Tame Impala']),
        search: (_) async => [
          {'title': 'Zzz', 'primaryArtists': 'Qqq', 'duration': '30'},
        ],
      );
      expect(m['matched'], isFalse);
      expect(m['saavn'], isNotNull);
    });
  });

  group('route', () {
    late LocalRoutes routes;
    late Dio dio;
    setUp(() {
      spotifyDioOverride = Dio()..httpClientAdapter = _Fake(embedOk: false);
      routes = LocalRoutes();
      registerSpotifyRoutes(routes);
      dio = Dio(BaseOptions(baseUrl: 'https://x.test'))
        ..interceptors.add(LocalBackendInterceptor(routes));
    });

    Future<DioException> fail(Map<String, String> q) async {
      try {
        await dio.get<Object>('/spotify/import', queryParameters: q);
      } on DioException catch (e) {
        return e;
      }
      throw StateError('expected failure');
    }

    test('missing url -> 400', () async {
      final e = await fail({});
      expect(e.response!.statusCode, 400);
      expect(e.response!.data['message'], 'Missing required parameter: url');
    });
    test('bad url -> 400', () async {
      final e = await fail({'url': 'nope'});
      expect(e.response!.statusCode, 400);
      expect(
        e.response!.data['message'],
        'Could not extract a Spotify playlist id from the input',
      );
    });
    test('unreadable playlist -> 502', () async {
      final e = await fail({'url': 'spotify:playlist:abcdefghijklmnopqrstuv'});
      expect(e.response!.statusCode, 502);
      expect(jsonEncode(e.response!.data), contains('private, removed'));
    });
  });
}
