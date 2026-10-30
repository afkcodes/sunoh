@Tags(['live'])
library;

// Imports public playlists through the on-device port and through the deployed
// sunoh-api, then compares JSON shape and counts. Run with:
//   flutter test --run-skipped -t live test/backend/spotify/
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunoh/backend/local_backend.dart';
import 'package:sunoh/backend/spotify/routes.dart';
import 'package:sunoh/backend/spotify/scraper.dart';

import '../saavn/shape_diff.dart';

// Spotify editorial playlists (verified to exist when written).
const _topHits = 'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M';
const _hotHitsHindi =
    'https://open.spotify.com/playlist/37i9dQZF1DX0XUfTFmNBRM';
// A public 350-track playlist: past the embed page's 100-track cap.
const _big = 'https://open.spotify.com/playlist/5nnoP6eYxjMJnIRZ7eXOiF';

String _base() {
  // Read only this key: env.json holds other private endpoints.
  final env = jsonDecode(File('env.json').readAsStringSync()) as Map;
  return env['SUNOH_API_BASE'] as String;
}

Future<Map<String, dynamic>> _import(Dio dio, String url) async {
  final r = await dio.get<Map<String, dynamic>>(
    '/spotify/import',
    queryParameters: {'url': url},
    options: Options(receiveTimeout: const Duration(seconds: 180)),
  );
  return r.data!;
}

String _counts(String who, Map<String, dynamic> env, Duration took) {
  final d = env['data'] as Map;
  final s = d['summary'] as Map;
  return '$who: ${s['total']} tracks, ${s['matched']} matched, '
      '${(d['items'] as List).length} items, ${took.inMilliseconds} ms';
}

void main() {
  late Dio local;
  late Dio server;

  setUpAll(() {
    spotifyDioOverride = null;
    final routes = LocalRoutes();
    registerSpotifyRoutes(routes);
    local = Dio(BaseOptions(baseUrl: _base()))
      ..interceptors.add(LocalBackendInterceptor(routes));
    server = Dio(
      BaseOptions(
        baseUrl: _base(),
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 180),
      ),
    );
  });

  for (final (label, url) in [
    ('top hits', _topHits),
    ('hot hits hindi', _hotHitsHindi),
  ]) {
    test('parity: $label', () async {
      final sw = Stopwatch()..start();
      final ours = await _import(local, url);
      final localTime = sw.elapsed;
      // ignore: avoid_print
      print(_counts('device', ours, localTime));
      expect(ours['source'], 'spotify');
      expect(ours['status'], 'success');

      sw.reset();
      Map<String, dynamic> theirs;
      try {
        theirs = await _import(server, url);
      } on DioException catch (e) {
        // ignore: avoid_print
        print('server: unavailable (${e.response?.statusCode ?? e.type})');
        return;
      }
      // ignore: avoid_print
      print(_counts('server', theirs, sw.elapsed));
      expect(theirs['status'], 'success');
      expect(ours['source'], theirs['source']);
      final diffs = shapeDiff(
        theirs['data'],
        ours['data'],
        // The browser scraper's selector finds no description today; the port
        // reads the real one. The DTO treats it as optional, so a superset is
        // fine.
        ignore: {'source.description'},
      );
      expect(diffs, isEmpty, reason: diffs.join('\n'));
    }, timeout: const Timeout(Duration(minutes: 5)));
  }

  test('past 100 tracks on device', () async {
    final sw = Stopwatch()..start();
    final ours = await _import(local, _big);
    // ignore: avoid_print
    print(_counts('device big', ours, sw.elapsed));
    expect((ours['data'] as Map)['summary']['total'], greaterThan(100));
    expect(sw.elapsed, lessThan(const Duration(seconds: 120)));
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('bad inputs give the server envelopes', () async {
    for (final (url, code) in [
      ('not a playlist', 400),
      ('spotify:playlist:0000000000000000000000', 502),
    ]) {
      Future<int?> status(Dio d) async {
        try {
          await d.get<Object>('/spotify/import', queryParameters: {'url': url});
          return 200;
        } on DioException catch (e) {
          return e.response?.statusCode;
        }
      }

      expect(await status(local), code);
      // The browser scraper reads Spotify's generic "Your Library" page for a
      // missing playlist and answers 200 with zero tracks, so only the 400
      // case is comparable; the port's 502 is the contract controller.ts states.
      if (code == 400) expect(await status(server), code);
    }
  });
}
