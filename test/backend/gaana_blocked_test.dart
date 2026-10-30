// A Gaana firewall ban must send the route to the server, not fail it.
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunoh/backend/gaana/http.dart';
import 'package:sunoh/backend/gaana/request_gate.dart';
import 'package:sunoh/backend/local_backend.dart';
import 'package:sunoh/backend/music/routes.dart';
import 'package:sunoh/backend/response_cache.dart';
import 'package:sunoh/backend/saavn/client.dart';

class _Counting implements HttpClientAdapter {
  _Counting(this.reply);
  final ResponseBody Function(RequestOptions) reply;
  final seen = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? s,
    Future<void>? c,
  ) async {
    seen.add(o.uri.path);
    return reply(o);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _denied(RequestOptions _) =>
    ResponseBody.fromString('<html>Access Denied</html>', 403);

ResponseBody _json(String body) => ResponseBody.fromString(
  body,
  200,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);

void main() {
  late _Counting gaana;
  late _Counting server;
  late Dio dio;
  var t = DateTime(2026);

  Dio build(ResponseCache cache) {
    final routes = LocalRoutes();
    registerMusicRoutes(routes);
    return Dio(BaseOptions(baseUrl: 'https://x.test'))
      ..httpClientAdapter = server
      ..interceptors.add(LocalBackendInterceptor(routes, cache: cache));
  }

  setUp(() {
    t = DateTime(2026);
    gaanaGate = GaanaGate(clock: () => t);
    gaana = _Counting(_denied);
    server = _Counting((_) => _json('{"status":"success","data":"server"}'));
    useGaanaAdapter(gaana);
    saavnDioForTesting = Dio()
      ..httpClientAdapter = _Counting((_) => _json('{"results":[],"total":0}'));
    dio = build(
      ResponseCache(openBox: () async => throw StateError('no disk')),
    );
  });

  tearDown(() {
    useGaanaAdapter(null);
    saavnDioForTesting = null;
    gaanaGate = GaanaGate();
  });

  test('a 403 on a Gaana song falls through to the server', () async {
    final r = await dio.get<Map<String, dynamic>>(
      '/music/song/abc',
      queryParameters: {'provider': 'gaana'},
    );
    expect(r.data!['data'], 'server');
    expect(gaana.seen, hasLength(1));
    expect(server.seen, ['/music/song/abc']);
  });

  test('during the cooldown the server answers without Gaana', () async {
    await dio.get<Map<String, dynamic>>(
      '/music/song/abc',
      queryParameters: {'provider': 'gaana'},
    );
    final r = await dio.get<Map<String, dynamic>>(
      '/music/song/abc/stream',
      queryParameters: {'provider': 'gaana'},
    );
    expect(r.data!['data'], 'server');
    expect(gaana.seen, hasLength(1), reason: 'cooldown skips the network');
    expect(server.seen, hasLength(2));
  });

  test('search keeps the Saavn half when only Gaana is blocked', () async {
    final r = await dio.get<Map<String, dynamic>>(
      '/music/search',
      queryParameters: {'q': 'x', 'type': 'songs'},
    );
    expect(r.data!['source'], 'unified');
    expect(server.seen, isEmpty);
  });

  test('search falls through when Saavn has nothing either', () async {
    saavnDioForTesting = Dio()
      ..httpClientAdapter = _Counting((_) => ResponseBody.fromString('x', 500));
    saavnRetryDelay = Duration.zero;
    addTearDown(() => saavnRetryDelay = const Duration(seconds: 1));
    final r = await dio.get<Map<String, dynamic>>(
      '/music/search',
      queryParameters: {'q': 'x', 'type': 'songs'},
    );
    expect(r.data!['data'], 'server');
  });

  test('a partial reply is not cached', () async {
    final cache = ResponseCache(openBox: () async => throw StateError('x'));
    const policy = CachePolicy(fresh: Duration(minutes: 5));
    var calls = 0;
    Future<LocalReply> fetch() async =>
        LocalReply(++calls, partial: calls == 1);
    expect((await cache.run('k', policy, fetch)).data, 1);
    expect((await cache.run('k', policy, fetch)).data, 2);
    expect((await cache.run('k', policy, fetch)).data, 2, reason: 'full: kept');
  });

  test('a non-blocking Gaana error is still the 400 envelope', () async {
    gaana = _Counting((_) => ResponseBody.fromString('<html>oops</html>', 200));
    useGaanaAdapter(gaana);
    await expectLater(
      dio.get<Map<String, dynamic>>(
        '/music/song/abc',
        queryParameters: {'provider': 'gaana'},
      ),
      throwsA(
        isA<DioException>().having((e) => e.response?.statusCode, 'code', 400),
      ),
    );
    expect(server.seen, isEmpty);
  });
}
