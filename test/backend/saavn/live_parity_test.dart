@Tags(['live'])
library;

// Calls the Dart port and the deployed sunoh-api for the same request and
// compares response shapes (keys and value types, not values). Run with:
//   flutter test --run-skipped -t live test/backend/saavn/
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunoh/backend/local_backend.dart';
import 'package:sunoh/backend/saavn/saavn.dart' as saavn;

import 'shape_diff.dart';

late final Dio server;

String _base() {
  // Read only this key: env.json holds other private endpoints.
  final env = jsonDecode(File('env.json').readAsStringSync()) as Map;
  return env['SUNOH_API_BASE'] as String;
}

Future<Map<String, dynamic>> _serverGet(
  String path,
  Map<String, String> q,
) async {
  final r = await server.get<Map<String, dynamic>>(path, queryParameters: q);
  return r.data!;
}

/// Runs both sides and fails with the shape differences, if any.
Future<void> _parity(
  String label,
  Future<LocalReply> Function() port,
  String path,
  Map<String, String> query, {
  Set<String> ignore = const {},
}) async {
  final ours = await port();
  final theirs = await _serverGet(path, {...query, 'provider': 'saavn'});
  expect(theirs['status'], 'success', reason: '$label: server failed');
  final diffs = shapeDiff(theirs['data'], ours.data, ignore: ignore);
  expect(
    diffs,
    isEmpty,
    reason: '$label shape differences:\n${diffs.join('\n')}',
  );
  expect(ours.source, theirs['source'], reason: '$label source');
}

void main() {
  setUpAll(() {
    server = Dio(
      BaseOptions(
        baseUrl: _base(),
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 60),
      ),
    );
  });

  test('home', () async {
    await _parity(
      'home',
      () => saavn.homeController({}, {}),
      '/music/home',
      {},
    );
  });

  group('search', () {
    for (final (q, type) in [
      ('arijit singh', 'songs'),
      ('kesariya', 'albums'),
      ('arijit', 'artists'),
      ('love', 'playlists'),
      ('arijit', 'all'),
    ]) {
      test('$type "$q"', () async {
        await _parity(
          'search/$type',
          () => saavn.searchController({}, {'q': q, 'type': type}),
          '/music/search',
          {'q': q, 'type': type},
        );
      });
    }
  });

  // Ids come from a live search so the test does not rot with the catalogue.
  Future<List<String>> ids(String q, String type, int n) async {
    final res = await saavn.getSaavnSearchData(q, type, 1, 5) as Map;
    return [
      for (final i in (res['list'] as List).take(n)) (i as Map)['id'] as String,
    ];
  }

  group('entities', () {
    test('album', () async {
      for (final id in await ids('kesariya', 'albums', 2)) {
        await _parity(
          'album',
          () => saavn.albumController({'albumId': id}, {}),
          '/music/album/$id',
          {},
        );
      }
    });
    test('album recommend', () async {
      final id = (await ids('kesariya', 'albums', 1)).first;
      await _parity(
        'album recommend',
        () => saavn.albumRecommendationController({'albumId': id}, {}),
        '/music/album/$id/recommend',
        {},
      );
    });
    test('playlist', () async {
      for (final id in await ids('love', 'playlists', 2)) {
        await _parity(
          'playlist',
          () => saavn.playlistController({'playlistId': id}, {}),
          '/music/playlist/$id',
          {},
        );
      }
    });
    test('song', () async {
      for (final id in await ids('arijit singh', 'songs', 3)) {
        await _parity(
          'song',
          () => saavn.songController({'songId': id}, {}),
          '/music/song/$id',
          {},
        );
      }
    });
    test('artist', () async {
      for (final id in await ids('arijit', 'artists', 2)) {
        await _parity(
          'artist',
          () => saavn.artistController({'artistId': id}, {}),
          '/music/artist/$id',
          {'provider': 'saavn'},
        );
      }
    });
    test('channel', () async {
      await _parity(
        'channel',
        () => saavn.channelController({'channelId': 'bollywood'}, {}),
        '/music/occasions/bollywood',
        {},
      );
    }, skip: false);
  });

  group('radio', () {
    test('song recommend', () async {
      final id = (await ids('arijit singh', 'songs', 1)).first;
      final ours = await saavn.getSaavnSongRecommendData(id);
      final theirs = await _serverGet('/music/song/$id/recommend', {
        'provider': 'saavn',
      });
      final diffs = shapeDiff(theirs['data'], ours);
      expect(diffs, isEmpty, reason: diffs.join('\n'));
    });

    test('featured station then station songs', () async {
      // Only Saavn's own featured stations are seedable; arbitrary names get
      // "No new song found for current radio".
      final featured = await saavn.featuredStationsController({}, {
        'lang': 'hindi',
      });
      final name = ((featured.data as List).first as Map)['title'] as String;
      final created = await saavn.stationController({}, {
        'name': name,
        'language': 'hindi',
      });
      final stationId = (created.data as Map)['stationid'] as String;
      expect(stationId, isNotEmpty);

      final ours = await saavn.stationSongsController(
        {'stationId': stationId},
        {'language': 'hindi'},
      );
      final list = (ours.data as Map)['list'] as List;
      expect(list, isNotEmpty);

      // The server's /music/radio/:id wrapper cannot be compared directly:
      // from the VPS address Saavn answers radio songs with an error (the
      // phone's own connection does not hit that), so compare the mapped song
      // shape against the server's song list from /song/:id/recommend.
      final id = (await ids('arijit singh', 'songs', 1)).first;
      final theirs = await _serverGet('/music/song/$id/recommend', {
        'provider': 'saavn',
      });
      // The radio endpoint ships playCount as a number, /reco as a string:
      // an upstream difference the TS mapper passes through untouched.
      final diffs = shapeDiff(
        (theirs['data'] as Map)['list'],
        list,
        ignore: {'[].playCount'},
      );
      expect(diffs, isEmpty, reason: diffs.join('\n'));
    });

    test('artist and entity station creation', () async {
      final artist = await saavn.artistStationController({}, {
        'artistId': '459320',
        'name': 'Arijit Singh',
      });
      expect((artist.data as Map)['stationid'], isA<String>());
      final entity = await saavn.entityStationController({}, {
        'entityId': 'YiVML4Zo',
        'entityType': 'song',
      });
      expect(entity.data, isA<Map>());
    });

    test('featured stations', () async {
      final ours = await saavn.featuredStationsController({}, {});
      expect(ours.data, isNotNull);
    });
  });

  test('top search', () async {
    final ours = await saavn.getSaavnTopSearchData();
    expect(ours, isNotEmpty);
  });
}
