import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:sunoh/backend/local_backend.dart';
import 'package:sunoh/backend/response_cache.dart';

class _Dead implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? s,
    Future<void>? c,
  ) => throw StateError('fell through to the network');
  @override
  void close({bool force = false}) {}
}

void main() {
  late DateTime now;
  late ResponseCache cache;
  late Dio dio;
  var calls = 0;
  Object? failWith;
  Completer<void>? gate;

  const policy = CachePolicy(
    fresh: Duration(minutes: 10),
    stale: Duration(hours: 1),
  );

  Dio build(ResponseCache c) {
    final r = LocalRoutes()
      ..get('/feed', (p, q, b) async {
        calls++;
        await gate?.future;
        if (failWith != null) throw failWith!;
        return LocalReply({'n': calls, 'l': q['lang']}, message: 'm');
      }, cache: policy)
      ..get('/plain', (p, q, b) async => {'n': ++calls});
    return Dio(BaseOptions(baseUrl: 'https://x.test'))
      ..httpClientAdapter = _Dead()
      ..interceptors.add(LocalBackendInterceptor(r, cache: c));
  }

  Future<int> n(Dio d, {String? lang, bool refresh = false}) async {
    final res = await d.get<Map<String, dynamic>>(
      '/feed',
      queryParameters: {'lang': ?lang},
      options: Options(headers: {if (refresh) localRefreshHeader: '1'}),
    );
    return (res.data!['data'] as Map)['n'] as int;
  }

  setUp(() {
    now = DateTime(2026, 1, 1);
    calls = 0;
    failWith = null;
    gate = null;
    cache = ResponseCache(
      openBox: () => throw StateError('no disk'),
      clock: () => now,
    );
    dio = build(cache);
  });

  test('fresh hit does not call the handler again', () async {
    expect(await n(dio), 1);
    now = now.add(const Duration(minutes: 9));
    expect(await n(dio), 1);
    expect(calls, 1);
  });

  test('uncached routes always reach the handler', () async {
    await dio.get<Object>('/plain');
    await dio.get<Object>('/plain');
    expect(calls, 2);
  });

  test(
    'stale copy is served at once and refreshed in the background',
    () async {
      expect(await n(dio), 1);
      now = now.add(const Duration(minutes: 30));
      expect(await n(dio), 1);
      await Future<void>.delayed(Duration.zero);
      expect(calls, 2);
      expect(await n(dio), 2);
      expect(calls, 2);
    },
  );

  test('past the stale window the caller waits for a fetch', () async {
    await n(dio);
    now = now.add(const Duration(hours: 2));
    expect(await n(dio), 2);
  });

  test('failures are not cached and do not evict a stale copy', () async {
    failWith = LocalApiError('boom', code: 502);
    await expectLater(n(dio), throwsA(isA<DioException>()));
    failWith = null;
    expect(await n(dio), 2);
    now = now.add(const Duration(minutes: 30));
    failWith = StateError('upstream down');
    expect(await n(dio), 2); // stale copy survives a failed refresh
    await Future<void>.delayed(Duration.zero);
    failWith = null;
    expect(await n(dio), 2);
  });

  test('concurrent identical requests share one handler call', () async {
    gate = Completer<void>();
    final a = n(dio);
    final b = n(dio);
    await Future<void>.delayed(Duration.zero);
    gate!.complete();
    expect(await Future.wait([a, b]), [1, 1]);
    expect(calls, 1);
  });

  test('query is part of the key', () async {
    expect(await n(dio, lang: 'hindi'), 1);
    expect(await n(dio, lang: 'tamil'), 2);
    expect(await n(dio, lang: 'hindi'), 1);
  });

  test('refresh header skips the fresh copy and replaces it', () async {
    await n(dio);
    expect(await n(dio, refresh: true), 2);
    expect(await n(dio), 2);
  });

  test('keyFor sorts params and query', () {
    expect(
      ResponseCache.keyFor(
        'GET',
        '/a/:x',
        {'b': '1', 'a': '2'},
        {'z': 'é', 'y': ''},
      ),
      ResponseCache.keyFor(
        'GET',
        '/a/:x',
        {'a': '2', 'b': '1'},
        {'y': '', 'z': 'é'},
      ),
    );
  });

  group('persistence', () {
    late Directory tmp;
    late Box<String> box;
    const disk = CachePolicy(fresh: Duration(hours: 1), persist: true);

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('sunoh_cache');
      Hive.init(tmp.path);
      box = await Hive.openBox<String>('t');
    });
    tearDown(() async {
      await Hive.close();
      await tmp.delete(recursive: true);
    });

    ResponseCache fresh({int? max}) => ResponseCache(
      openBox: () async => box,
      clock: () => now,
      maxEntries: max,
    );

    test('a new cache instance reads what the old one wrote', () async {
      var fetches = 0;
      Future<LocalReply> f() async =>
          LocalReply({'v': ++fetches}, message: 'hi', source: 's');
      await fresh().run('k', disk, f);
      final r = await fresh().run('k', disk, f);
      expect(fetches, 1);
      expect((r.data as Map)['v'], 1);
      expect(r.message, 'hi');
      expect(r.source, 's');
    });

    test('a corrupt entry is ignored and removed', () async {
      await box.put('k', '{not json');
      final r = await fresh().run('k', disk, () async => const LocalReply(7));
      expect(r.data, 7);
      expect(box.get('k'), contains('"d":7'));
    });

    test('oldest entries are evicted beyond the cap', () async {
      final c = fresh(max: 2);
      for (final k in ['a', 'b', 'c']) {
        now = now.add(const Duration(seconds: 1));
        await c.run(k, disk, () async => LocalReply(k));
      }
      expect(box.keys.toSet(), {'b', 'c'});
    });
  });
}
