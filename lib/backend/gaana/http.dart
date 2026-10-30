// Gaana transport: the gaanaFetch POST helper, its headers and the `__ul`
// language cookie (src/gaana/controller.ts), over lib/backend/upstream.dart.
//
// Deliberately NOT ported from src/helpers/http.ts: its retry loop. The server
// retried a JSON-parse failure three times with one second waits, so every
// Gaana refusal cost ~3 s before the user saw an error. Here there is one
// attempt, and a non-JSON reply is an immediate error carrying the message the
// server would eventually have sent.
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../common.dart' show capitalizeFirstLetter;
import '../upstream.dart';
import 'request_gate.dart';

const gaanaBaseUrl = 'https://gaana.com/apiv2';

const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, '
    'like Gecko) Chrome/91.0.4472.124 Safari/537.36';

/// Gaana's firewall refused this connection (403 "Access Denied"), or the gate
/// is in its cooldown after such a refusal and skipped the call.
///
/// Why an exception and not a [GaanaResult] error: every other Gaana failure
/// becomes a LocalApiError (the server's 400 envelope), which ends the request.
/// A ban is about THIS phone's IP, not the route, and the sunoh-api server can
/// usually still reach Gaana, so the interceptor must see a non-LocalApiError
/// and fall through to it. The type name shows in the fall-through log.
class GaanaBlocked implements Exception {
  const GaanaBlocked([this.reason = 'blocked by Gaana (403)']);

  final String reason;

  @override
  String toString() => 'GaanaBlocked($reason)';
}

/// `{data, error, message}` as src/helpers/http.ts resolved it: failures are
/// values, not exceptions, and each controller picks its own fallback text.
class GaanaResult {
  const GaanaResult({this.data, this.error, this.message = ''});

  final dynamic data;
  final String? error;
  final String message;
}

Future<Map<String, String>> getGaanaHeaders([String? languages]) async {
  final headers = {
    'User-Agent': _userAgent,
    'Accept': 'application/json, text/plain, */*',
    'X-Requested-With': 'XMLHttpRequest',
    'Origin': 'https://gaana.com',
    'Referer': 'https://gaana.com/',
  };
  if (languages != null && languages.isNotEmpty) {
    final formatted = languages
        .split(',')
        .map((l) => capitalizeFirstLetter(l.trim()))
        .join(',');
    // Gaana personalises the home feed from this cookie, not a query param.
    headers['Cookie'] = '__ul=${Uri.encodeComponent(formatted)}';
  }
  return headers;
}

/// POST to the apiv2 endpoint with [params] as the query and an empty body.
Future<GaanaResult> gaanaFetch(
  Map<String, Object?> params, {
  String? languages,
  Duration timeout = const Duration(seconds: 30),
}) async => _request(
  'POST',
  Uri.parse(gaanaBaseUrl).replace(
    queryParameters: {for (final e in params.entries) e.key: '${e.value}'},
  ),
  {...await getGaanaHeaders(languages), 'Content-Length': '0'},
  timeout,
);

/// Plain GET (occasion and section URLs on apiv2.gaana.com).
Future<GaanaResult> fetchGet(
  String url, {
  String? languages,
  Duration timeout = const Duration(seconds: 30),
}) async =>
    _request('GET', Uri.parse(url), await getGaanaHeaders(languages), timeout);

/// The search call: same endpoint but a `{}` JSON body instead of
/// Content-Length 0, as the server sent it.
Future<GaanaResult> gaanaSearchPost(String keyword, String? languages) async =>
    _request(
      'POST',
      Uri.parse(
        gaanaBaseUrl,
      ).replace(queryParameters: {'keyword': keyword, 'type': 'search'}),
      await getGaanaHeaders(languages),
      const Duration(seconds: 30),
      body: const <String, Object?>{},
    );

// One keep-alive client per timeout: a home load fires ~20 requests and each
// would otherwise pay its own TLS handshake.
final _clients = <Duration, Dio>{};

/// Test seam: every client built after this uses [a] instead of the network.
@visibleForTesting
void useGaanaAdapter(HttpClientAdapter? a) {
  _clients.clear();
  _testAdapter = a;
}

HttpClientAdapter? _testAdapter;

/// Every Gaana call goes through the gate (request_gate.dart); a null from it
/// means "in cooldown", answered without touching the network.
Future<GaanaResult> _request(
  String method,
  Uri uri,
  Map<String, String> headers,
  Duration timeout, {
  Object? body,
}) async =>
    await gaanaGate.run(
      () => _send(method, uri, headers, timeout, body: body),
    ) ??
    (throw const GaanaBlocked('cooldown after a 403'));

Future<GaanaResult> _send(
  String method,
  Uri uri,
  Map<String, String> headers,
  Duration timeout, {
  Object? body,
}) async {
  final dio = _clients.putIfAbsent(timeout, () {
    final d = upstreamDio(timeout: timeout);
    final test = _testAdapter;
    if (test != null) d.httpClientAdapter = test;
    return d;
  });
  try {
    final res = await dio.requestUri<String>(
      uri,
      data: body,
      options: Options(
        method: method,
        headers: headers,
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    );
    final text = res.data ?? '';
    if (res.statusCode == 403 && text.contains('Access Denied')) {
      gaanaGate.tripped();
      throw const GaanaBlocked();
    }
    Object? parsed;
    if (text.isNotEmpty) {
      try {
        parsed = jsonDecode(text);
      } on FormatException {
        // Gaana's refusal page. No retry: it will not change in a second.
        return const GaanaResult(
          error: 'Unexpected end of JSON input',
          message: 'Unexpected end of JSON input',
        );
      }
    }
    final code = res.statusCode ?? 0;
    if (code < 200 || code >= 300) {
      final msg = res.statusMessage ?? '';
      return GaanaResult(error: 'HTTP Error $code: $msg', message: msg);
    }
    return GaanaResult(data: parsed);
  } on DioException catch (e) {
    final isTimeout =
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout;
    final msg = isTimeout
        ? 'Request timed out after ${timeout.inMilliseconds}ms'
        : '${e.error ?? e.message ?? 'Request failed'}';
    return GaanaResult(error: msg, message: msg);
  }
}
