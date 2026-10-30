import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunoh/backend/local_backend.dart';

/// Answers anything that falls through, recording the paths it saw.
class _FakeServer implements HttpClientAdapter {
  final seen = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seen.add(options.path);
    return ResponseBody.fromString(
      '{"status":"success","data":"server"}',
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late LocalRoutes routes;
  late _FakeServer server;
  late Dio dio;

  setUp(() {
    routes = LocalRoutes();
    server = _FakeServer();
    dio = Dio(BaseOptions(baseUrl: 'https://x.test/api'))
      ..httpClientAdapter = server
      ..interceptors.add(LocalBackendInterceptor(routes));
  });

  test('params are decoded and query is stringified', () async {
    routes.get(
      '/music/album/:id',
      (p, q, b) async => {'id': p['id'], 'n': q['n']},
    );
    final r = await dio.get('/music/album/a%20b', queryParameters: {'n': 3});
    expect(r.statusCode, 200);
    expect(r.data, {
      'status': 'success',
      'message': 'OK',
      'data': {'id': 'a b', 'n': '3'},
      'error': null,
      'source': 'api',
    });
    expect(server.seen, isEmpty);
  });

  test('literal segments beat params regardless of order', () async {
    routes.get('/p/:id', (p, q, b) async => 'param');
    routes.get('/p/categories', (p, q, b) async => 'literal');
    final r = await dio.get('/p/categories');
    expect(r.data['data'], 'literal');
    expect((await dio.get('/p/zzz')).data['data'], 'param');
  });

  test('LocalReply sets message and source; POST body is passed', () async {
    routes.post(
      '/echo',
      (p, q, b) async => LocalReply(b, message: 'hi', source: 'saavn'),
    );
    final r = await dio.post('/echo', data: {'a': 1});
    expect(r.data['message'], 'hi');
    expect(r.data['source'], 'saavn');
    expect(r.data['data'], {'a': 1});
  });

  test('absolute URL with base prefix still matches', () async {
    routes.get('/music/home', (p, q, b) async => 1);
    final r = await dio.get('https://x.test/api/music/home');
    expect(r.data['data'], 1);
  });

  test('LocalApiError becomes a 400 failed envelope', () async {
    routes.get('/bad', (p, q, b) async => throw LocalApiError('nope'));
    try {
      await dio.get('/bad');
      fail('should throw');
    } on DioException catch (e) {
      expect(e.type, DioExceptionType.badResponse);
      expect(e.response?.statusCode, 400);
      expect(e.response?.data['status'], 'failed');
      expect(e.response?.data['message'], 'nope');
      expect(e.response?.data['data'], isNull);
    }
  });

  test('unexpected exception falls through to the server', () async {
    routes.get('/boom', (p, q, b) async => throw StateError('x'));
    final r = await dio.get('/boom');
    expect(r.data['data'], 'server');
    expect(server.seen, ['/boom']);
  });

  test('unmatched route and wrong method fall through', () async {
    routes.post('/only-post', (p, q, b) async => 1);
    expect((await dio.get('/only-post')).data['data'], 'server');
    expect((await dio.get('/nothing')).data['data'], 'server');
    expect(server.seen.length, 2);
  });
}
