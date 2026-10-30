@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunoh/api/dto.dart';
import 'package:sunoh/backend/gaana/gaana.dart' as gaana;
import 'package:sunoh/backend/local_backend.dart';

// Shape = key sets and value types, recursively. Lists collapse to the merge
// of all their elements (lengths and values are volatile). null matches
// anything: optional fields are legitimately null for some entities.
Object? shape(Object? v) {
  if (v == null) return 'null';
  if (v is Map) {
    return {for (final e in v.entries) '${e.key}': shape(e.value)};
  }
  if (v is List) {
    Object? merged = 'null';
    for (final e in v) {
      merged = _merge(merged, shape(e));
    }
    return [merged];
  }
  if (v is num) return 'num';
  return v.runtimeType.toString();
}

Object? _merge(Object? a, Object? b) {
  if (a == 'null') return b;
  if (b == 'null') return a;
  if (a is Map && b is Map) {
    return {
      for (final k in {...a.keys, ...b.keys})
        k: a.containsKey(k) && b.containsKey(k)
            ? _merge(a[k], b[k])
            : (a[k] ?? b[k]),
    };
  }
  if (a is List && b is List) return [_merge(a.first, b.first)];
  return a == b ? a : 'mixed';
}

String? diff(Object? a, Object? b, String path, {Set<String> skip = const {}}) {
  if (skip.contains(path)) return null;
  if (a == 'null' || b == 'null' || a == 'mixed' || b == 'mixed') return null;
  if (a is Map && b is Map) {
    final ka = a.keys.toSet();
    final kb = b.keys.toSet();
    if (ka.difference(kb).isNotEmpty || kb.difference(ka).isNotEmpty) {
      return '$path keys: local-only ${ka.difference(kb)} '
          'server-only ${kb.difference(ka)}';
    }
    for (final k in ka) {
      final d = diff(a[k], b[k], '$path.$k', skip: skip);
      if (d != null) return d;
    }
    return null;
  }
  if (a is List && b is List) {
    if (a.isEmpty || b.isEmpty) return null;
    return diff(a.first, b.first, '$path[]', skip: skip);
  }
  if (a.runtimeType != b.runtimeType) return '$path type: $a vs $b';
  return null;
}

late final String _base;
final _server = Dio(BaseOptions(receiveTimeout: const Duration(seconds: 40)));

/// The deployed server's `data`, or null when it fails (its VPS address is
/// refused by Gaana for several calls, which is the reason for the port).
Future<Object?> serverData(
  String path, [
  Map<String, String> q = const {},
]) async {
  try {
    final res = await _server.get<Map<String, dynamic>>(
      '$_base/music$path',
      queryParameters: {'provider': 'gaana', ...q},
    );
    return res.data!['data'];
  } on DioException catch (e) {
    // ignore: avoid_print
    print(
      '[gaana-live] server ${e.response?.statusCode} for ${path.split('/').take(2).join('/')}',
    );
    return null;
  }
}

/// Local result as the app would see it after the JSON envelope round trip.
Object? roundTrip(LocalReply r) => jsonDecode(jsonEncode(r.data));

void expectParity(
  Object? local,
  Object? server, {
  Set<String> skip = const {},
}) {
  expect(diff(shape(local), shape(server), r'$', skip: skip), isNull);
}

Map<String, dynamic> asMap(Object? v) => Map<String, dynamic>.from(v as Map);

void main() {
  // Gaana's WAF answers a burst of ~60 requests in a few seconds with 403
  // "Access Denied" for about ten minutes. One home load alone is ~20 requests,
  // so the suite paces itself to look like a person, not a crawler.
  setUp(() => Future<void>.delayed(const Duration(seconds: 10)));

  setUpAll(() {
    // Read only the one key; env.json holds other values that must not leak.
    final env = jsonDecode(File('env.json').readAsStringSync()) as Map;
    _base = (env['SUNOH_API_BASE'] as String).replaceAll(RegExp(r'/+$'), '');
  });

  const songs = ['parvati-JbDj9vrB3n', 'the-fate-of-ophelia-LWBPdQJkKz'];

  group('albumDetail / playlistDetail (blocked from the old server)', () {
    test('album parses as AlbumDetail and has playable songs', () async {
      final sw = Stopwatch()..start();
      final r = await gaana.albumController({
        'albumId': 'the-life-of-a-girl-the-encore',
      }, {});
      sw.stop();
      // ignore: avoid_print
      print('[gaana-live] albumDetail ${sw.elapsedMilliseconds} ms');
      final data = roundTrip(r) as Map;
      final detail = AlbumDetail.fromJson(asMap(data));
      expect(detail.id, isNotEmpty);
      expect(detail.title, isNotEmpty);
      expect(detail.songs, isNotEmpty);
      expect(
        (data['album'] as Map).keys,
        containsAll([
          'id',
          'title',
          'type',
          'image',
          'artists',
          'songs',
          'source',
        ]),
      );
      expect(data['sections'], isA<List>());
    });

    test('playlist parses as PlaylistDetail', () async {
      final sw = Stopwatch()..start();
      final r = await gaana.playlistController({
        'playlistId': 'gaana-dj-hindi-top-50-1',
      }, {});
      sw.stop();
      // ignore: avoid_print
      print('[gaana-live] playlistDetail ${sw.elapsedMilliseconds} ms');
      final data = roundTrip(r) as Map;
      final detail = PlaylistDetail.fromJson(asMap(data));
      expect(detail.title, isNotEmpty);
      expect(detail.songs.length, greaterThan(10));
    });
  });

  group('parity with the deployed server', () {
    test('search', () async {
      for (final q in ['arijit singh', 'kesariya']) {
        final local = roundTrip(await gaana.searchController({}, {'q': q}));
        expectParity(local, await serverData('/search', {'q': q}));
      }
    });

    test('getGaanaSearchData and trending', () async {
      final s = await gaana.getGaanaSearchData('arijit singh');
      expect(s, isNotEmpty);
      final t = await gaana.getGaanaTrendingSearchData();
      expect(t, isNotEmpty);
    });

    test('songDetail', () async {
      for (final id in songs) {
        final local = roundTrip(await gaana.songController({'songId': id}, {}));
        // Saavn-sourced sections need the Saavn port, which is wired later.
        final server = asMap(await serverData('/song/$id'))..remove('sections');
        final l = asMap(local)..remove('sections');
        expectParity(l, server);
        expect(l['mediaUrls'] as List, isNotEmpty);
      }
    });

    test('song stream URLs decrypt to https', () async {
      final r = await gaana.songStreamController({'songId': songs.first}, {});
      final urls = roundTrip(r) as List;
      expect(urls, isNotEmpty);
      for (final u in urls) {
        expect((u as Map)['link'], startsWith('https://'));
      }
      expectParity(urls, await serverData('/song/${songs.first}/stream'));
    });

    test('home', () async {
      final local = roundTrip(await gaana.homeController({}, {}));
      expect(local, isNotEmpty);
      expectParity(local, await serverData('/home'));
    });

    test('search with a language cookie', () async {
      // Home fans out ~20 requests; Gaana's WAF bans bursts, so the cookie
      // path is checked on a single cheap call instead.
      final local = roundTrip(
        await gaana.searchController({}, {'q': 'kesariya', 'lang': 'tamil'}),
      );
      expect(local, isNotEmpty);
    });

    test('collection, occasions, album-list, radio stations', () async {
      final home = await gaana.gaanaFetch({'type': 'home'});
      final keys = [
        for (final s in (home.data['home'] as List))
          if (s['seokey_url'] != null) s['seokey_url'] as String,
      ];
      expect(keys, isNotEmpty);
      for (final key in keys.take(2)) {
        final local = roundTrip(
          await gaana.collectionController({'seokey': key}, {}),
        );
        expectParity(local, await serverData('/collection/$key'));
      }

      final occ = roundTrip(await gaana.occasionController({}, {}));
      expectParity(occ, await serverData('/occasions'));

      final al = roundTrip(await gaana.albumListController({}, {}));
      expectParity(al, await serverData('/album-list'));

      final radio = roundTrip(await gaana.radioStationsController({}, {}));
      expect(radio, isA<List>());
    });

    test('occasion detail and items', () async {
      final occ = roundTrip(await gaana.occasionController({}, {})) as List;
      final first = asMap(occ.first);
      final slug = first['url'] as String;
      final detail = roundTrip(
        await gaana.occasionDetailController({'slug': slug}, {}),
      );
      expectParity(detail, await serverData('/occasions/$slug'));
      final items = roundTrip(
        await gaana.occasionItemsController({'id': '${first['id']}'}, {}),
      );
      expect(items, isA<List>());
    });

    test('artist', () async {
      final song = asMap(await serverData('/song/${songs.first}'));
      final artistId = ((song['artists'] as List).first as Map)['id'] as String;
      final local = roundTrip(
        await gaana.artistController({'artistId': artistId}, {}),
      );
      // /music/artist is the unified controller on the server (a different
      // shape that never reaches this one), so there is nothing to compare;
      // check the DTO parser accepts the gaana-nested shape instead.
      final detail = ArtistDetail.fromJson(asMap(local));
      expect(detail.name, isNotEmpty);
    });

    test('radio detail enriches tracks with streams', () async {
      final stations = await gaana.getGaanaRadioStations();
      if (stations.isEmpty) return;
      final id = (stations.first['data'] as List).first['id'] as String;
      final r = roundTrip(
        await gaana.radioDetailController({'radioId': id}, {}),
      );
      expect(r, isA<List>());
    });
  });
}
