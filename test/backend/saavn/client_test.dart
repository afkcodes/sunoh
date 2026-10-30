import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunoh/backend/local_backend.dart';
import 'package:sunoh/backend/saavn/client.dart';
import 'package:sunoh/backend/saavn/saavn.dart' as saavn;

/// Replays canned (status, body) pairs and records each request.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.replies);
  final List<(int, String)> replies;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final (code, body) =
        replies[(requests.length - 1).clamp(0, replies.length - 1)];
    return ResponseBody.fromString(
      body,
      code,
      statusMessage: code == 200 ? 'OK' : 'Err',
    );
  }

  @override
  void close({bool force = false}) {}
}

_Adapter _install(List<(int, String)> replies) {
  final a = _Adapter(replies);
  saavnDioForTesting = Dio()..httpClientAdapter = a;
  saavnRetryDelay = Duration.zero;
  return a;
}

void main() {
  tearDown(() => saavnDioForTesting = null);

  test('adds language defaults and the regional cookie', () async {
    final a = _install([(200, '{"a":1}')]);
    final r = await saavnFetch({
      '__call': 'x',
      'language': null,
    }, lang: 'Tamil, English');
    expect(r.data, {'a': 1});
    final q = a.requests.single.uri.queryParameters;
    expect(q['language'], 'tamil');
    expect(q['languages'], 'tamil,english');
    expect(q['__call'], 'x');
    expect(a.requests.single.headers['cookie'], contains('L=tamil%2Cenglish'));
  });

  test('retries 5xx then succeeds; 4xx is final', () async {
    var a = _install([(503, 'x'), (200, '{"ok":true}')]);
    expect((await saavnFetch({'__call': 'x'})).data, {'ok': true});
    expect(a.requests.length, 2);

    a = _install([(404, '{}')]);
    final r = await saavnFetch({'__call': 'x'});
    expect(r.error, isNotNull);
    expect(r.code, 404);
    expect(a.requests.length, 1);
  });

  test(
    'controller turns an upstream failure into the failure envelope',
    () async {
      _install([(404, '{}')]);
      await expectLater(
        saavn.songController({'songId': 'x'}, {}),
        throwsA(isA<LocalApiError>().having((e) => e.code, 'code', 404)),
      );
    },
  );

  test('station songs surface the upstream error text', () async {
    _install([(200, '{"error":"No new song found for current radio."}')]);
    await expectLater(
      saavn.stationSongsController({'stationId': 's'}, {}),
      throwsA(
        isA<LocalApiError>().having(
          (e) => e.message,
          'message',
          'Saavn API returned an error: No new song found for current radio.',
        ),
      ),
    );
  });
}
