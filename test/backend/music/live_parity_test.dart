@Tags(['live'])
library;

// Calls every /music route through the on-device routes and through the
// deployed sunoh-api, and compares response shapes (key sets and value types).
// Run once, not repeatedly: Gaana bans an IP for ~10 minutes after a burst.
//   flutter test --run-skipped -t live test/backend/music/
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunoh/api/dto.dart';
import 'package:sunoh/backend/local_backend.dart';
import 'package:sunoh/backend/music/routes.dart';

import '../saavn/shape_diff.dart';

/// Any request that reaches the network from the local Dio is a bug: every
/// music route must be answered by the interceptor.
class _NoFallthrough implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => throw StateError('local route fell through to the network');

  @override
  void close({bool force = false}) {}
}

/// Counts upstream connections per host. Only the few HttpClient members Dio
/// uses are forwarded; anything else is a loud failure, not a silent no-op.
class _CountingClient implements HttpClient {
  _CountingClient(this._inner, this._counts);
  final HttpClient _inner;
  final Map<String, int> _counts;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    _counts.update(url.host, (n) => n + 1, ifAbsent: () => 1);
    return _inner.openUrl(method, url);
  }

  @override
  Duration? get connectionTimeout => _inner.connectionTimeout;
  @override
  set connectionTimeout(Duration? v) => _inner.connectionTimeout = v;
  @override
  Duration get idleTimeout => _inner.idleTimeout;
  @override
  set idleTimeout(Duration v) => _inner.idleTimeout = v;
  @override
  bool get autoUncompress => _inner.autoUncompress;
  @override
  set autoUncompress(bool v) => _inner.autoUncompress = v;
  @override
  set findProxy(String Function(Uri url)? f) => _inner.findProxy = f;
  @override
  set badCertificateCallback(
    bool Function(X509Certificate cert, String host, int port)? cb,
  ) => _inner.badCertificateCallback = cb;
  @override
  void close({bool force = false}) => _inner.close(force: force);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('HttpClient.${invocation.memberName}');
}

class _CountingOverrides extends HttpOverrides {
  final counts = <String, int>{};
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _CountingClient(super.createHttpClient(context), counts);
}

class Res {
  Res(this.status, this.env);
  final int status;
  final Map<String, dynamic>? env;
  bool get ok => status == 200 && env?['status'] == 'success';
  Object? get data => env?['data'];
}

late Dio local;
late Dio server;
final overrides = _CountingOverrides();

Future<Res> call(Dio d, String path, Map<String, String> q) async {
  try {
    final r = await d.get<Map<String, dynamic>>(path, queryParameters: q);
    return Res(r.statusCode ?? 0, r.data);
  } on DioException catch (e) {
    if (e.type == DioExceptionType.badResponse) {
      final data = e.response?.data;
      return Res(
        e.response?.statusCode ?? 0,
        data is Map<String, dynamic> ? data : null,
      );
    }
    // A local fall-through lands here with the adapter's StateError.
    if (identical(d, local)) {
      fail('local ${path.split('/')[2]} failed: ${e.error}');
    }
    return Res(0, null);
  }
}

Future<Res> serverCall(String path, Map<String, String> q) async {
  try {
    return await call(server, path, q);
  } catch (_) {
    return Res(0, null);
  }
}

/// Shape-compares the local answer with the server's. When the server itself
/// fails the outcome (status + message) must match instead, which is how the
/// known upstream breakages (Saavn radio creation) are accepted.
Future<Res> parity(
  String label,
  String path,
  Map<String, String> q, {
  Set<String> ignore = const {},
  bool message = false,
}) async {
  final ours = await call(local, path, q);
  final theirs = await serverCall(path, q);
  if (!theirs.ok) {
    debugPrint(
      '[music-live] $label: server ${theirs.status} '
      '"${theirs.env?['message']}", local ${ours.status}',
    );
    expect(ours.status, theirs.status == 0 ? ours.status : theirs.status);
    return ours;
  }
  expect(
    ours.ok,
    isTrue,
    reason: '$label local failed: ${ours.env?['message']}',
  );
  final diffs = shapeDiff(theirs.data, ours.data, ignore: ignore);
  expect(
    diffs,
    isEmpty,
    reason: '$label shape differences:\n${diffs.join('\n')}',
  );
  expect(ours.env!['source'], theirs.env!['source'], reason: '$label source');
  if (message) {
    expect(ours.env!['message'], theirs.env!['message'], reason: '$label msg');
  }
  return ours;
}

/// Wall time and upstream request counts of one local call.
Future<Res> measured(String label, String path, Map<String, String> q) async {
  overrides.counts.clear();
  final sw = Stopwatch()..start();
  final r = await call(local, path, q);
  sw.stop();
  final total = overrides.counts.values.fold<int>(0, (a, b) => a + b);
  debugPrint(
    '[music-live] MEASURE $label: ${sw.elapsedMilliseconds} ms, '
    '$total upstream requests ${Map.of(overrides.counts)}',
  );
  return r;
}

Map<String, dynamic> asMap(Object? v) => Map<String, dynamic>.from(v as Map);

String firstId(Object? data) {
  final list = (data is Map ? data['list'] : data) as List;
  return '${(list.first as Map)['id']}';
}

void main() {
  // Gaana's WAF bans a burst of ~60 requests for ~10 minutes. Every test is
  // spaced out; the two Gaana-heavy ones (home, search) are each alone.
  setUp(() => Future<void>.delayed(const Duration(seconds: 10)));

  late String songId, albumId, playlistId, artistId;

  setUpAll(() async {
    HttpOverrides.global = overrides;
    // Read only the one key; env.json holds other private endpoints.
    final env = jsonDecode(File('env.json').readAsStringSync()) as Map;
    final base = (env['SUNOH_API_BASE'] as String).replaceAll(
      RegExp(r'/+$'),
      '',
    );
    server = Dio(
      BaseOptions(
        baseUrl: base,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 60),
      ),
    );
    final routes = LocalRoutes();
    registerMusicRoutes(routes);
    local = Dio(BaseOptions(baseUrl: 'http://local.invalid'))
      ..httpClientAdapter = _NoFallthrough()
      ..interceptors.add(LocalBackendInterceptor(routes));

    // Saavn ids for the by-id routes, taken from Saavn search (cheap, and it
    // keeps the test free of hard-coded ids that rot).
    Future<String> pick(String type, String q) async {
      final r = await call(local, '/music/search', {
        'q': q,
        'type': type,
        'provider': 'saavn',
      });
      return firstId(r.data);
    }

    songId = await pick('songs', 'kesariya');
    albumId = await pick('albums', 'brahmastra');
    playlistId = await pick('playlists', 'arijit singh hits');
    artistId = await pick('artists', 'arijit singh');
  });

  tearDownAll(() => HttpOverrides.global = null);

  test('languages', () async {
    await parity('languages', '/music/languages', {}, message: true);
  });

  test('home (unified) - timed', () async {
    final ours = await measured('/music/home', '/music/home', {});
    expect(ours.ok, isTrue);
    final theirs = await serverCall('/music/home', {});
    expect(theirs.ok, isTrue);
    final diffs = shapeDiff(theirs.data, ours.data);
    expect(diffs, isEmpty, reason: diffs.join('\n'));
    // The DTO the app builds from it must parse.
    for (final s in ours.data as List) {
      HomeSection.fromJson(asMap(s));
    }
    expect(ours.env!['source'], 'unified');
  });

  test('home provider=saavn', () async {
    await parity('home saavn', '/music/home', {'provider': 'saavn'});
  });

  test('search (unified, with query) - timed', () async {
    final ours = await measured(
      '/music/search?q=arijit singh',
      '/music/search',
      {'q': 'arijit singh'},
    );
    expect(ours.ok, isTrue);
    final theirs = await serverCall('/music/search', {'q': 'arijit singh'});
    expect(theirs.ok, isTrue);
    final diffs = shapeDiff(theirs.data, ours.data);
    expect(diffs, isEmpty, reason: diffs.join('\n'));
    expect(ours.env!['source'], 'unified');
  });

  test('search (no query = trending)', () async {
    await measured('/music/search (trending)', '/music/search', {});
    await parity('trending', '/music/search', {});
  });

  test('search typed', () async {
    await parity('search songs', '/music/search', {
      'q': 'kesariya',
      'type': 'songs',
    });
    await parity('search saavn', '/music/search', {
      'q': 'kesariya',
      'provider': 'saavn',
    });
  });

  test('album saavn', () async {
    await parity('album saavn', '/music/album/$albumId', {});
  });

  test('album gaana (server blocked: local parses)', () async {
    final r = await call(local, '/music/album/the-life-of-a-girl-the-encore', {
      'provider': 'gaana',
    });
    expect(r.ok, isTrue, reason: '${r.env?['message']}');
    final d = AlbumDetail.fromJson(asMap(r.data));
    expect(d.title, isNotEmpty);
    expect(d.songs, isNotEmpty);
  });

  test('playlist saavn', () async {
    await parity('playlist saavn', '/music/playlist/$playlistId', {});
  });

  test('playlist gaana (server blocked: local parses)', () async {
    final r = await call(local, '/music/playlist/gaana-dj-hindi-top-50-1', {
      'provider': 'gaana',
    });
    expect(r.ok, isTrue, reason: '${r.env?['message']}');
    final d = PlaylistDetail.fromJson(asMap(r.data));
    expect(d.title, isNotEmpty);
    expect(d.songs, isNotEmpty);
  });

  test('song saavn', () async {
    await parity('song saavn', '/music/song/$songId', {});
  });

  test('song gaana (with the Saavn sections hook)', () async {
    final ours = await parity('song gaana', '/music/song/parvati-JbDj9vrB3n', {
      'provider': 'gaana',
    });
    final sections = [
      for (final s in asMap(ours.data)['sections'] as List) asMap(s)['heading'],
    ];
    debugPrint('[music-live] gaana song sections: $sections');
    expect(sections, contains('More from Artist'));
  });

  test('song stream', () async {
    await parity('stream gaana', '/music/song/parvati-JbDj9vrB3n/stream', {
      'provider': 'gaana',
    });
    final ours = await call(local, '/music/song/$songId/stream', {});
    final theirs = await serverCall('/music/song/$songId/stream', {});
    expect(ours.status, 400);
    expect(theirs.status, 400);
  });

  test('recommend', () async {
    await parity('recommend songId', '/music/recommend', {'songId': songId});
    await parity('recommend q', '/music/recommend', {'q': 'kesariya'});
    final ours = await call(local, '/music/recommend', {});
    expect(ours.status, 400);
    expect(
      ours.env!['message'],
      'Could not identify a song for recommendations',
    );
  });

  test('occasions', () async {
    final r = await parity('occasions', '/music/occasions', {
      'provider': 'gaana',
    });
    expect(r.ok, isTrue);
    final first = (r.data as List).first as Map;
    final slug = '${first['url'] ?? first['slug'] ?? first['id']}';
    await parity('occasion detail', '/music/occasions/$slug', {
      'provider': 'gaana',
    });
    final bad = await call(local, '/music/occasions', {});
    expect(bad.status, 400);
  });

  test('artist (saavn id, then a gaana slug)', () async {
    await parity('artist saavn id', '/music/artist/$artistId', {});
    await parity('artist provider=saavn', '/music/artist/$artistId', {
      'provider': 'saavn',
    });
  });

  test('artist (gaana slug via name pivot)', () async {
    await parity('artist gaana slug', '/music/artist/arijit-singh', {});
  });

  test('radio session + play', () async {
    // Saavn song/artist station creation is broken upstream (empty ids); the
    // outcome must still match the server's.
    await parity('radio song', '/music/radio/session', {
      'id': songId,
      'type': 'song',
    });
    await parity('radio artist', '/music/radio/session', {
      'id': artistId,
      'type': 'artist',
      'name': 'Arijit Singh',
    });
    final featured = await parity('radio featured', '/music/radio/session', {
      'type': 'featured',
      'name': 'Arijit Singh',
    });
    if (featured.ok) {
      final sid = (featured.data as Map)['stationId'] as String;
      await parity('radio play saavn', '/music/radio/$sid', {'count': '10'});
    }
    final g = await parity('radio gaana session', '/music/radio/session', {
      'id': 'x',
      'type': 'featured',
      'provider': 'gaana',
    });
    expect((g.data as Map)['stationId'], 'gaana_x');
    final bad = await call(local, '/music/radio/nonsense', {});
    expect(bad.status, 400);
  });
}
