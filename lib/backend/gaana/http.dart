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

/// The User-Agent gaana.com's own site sends (seen 2026-11-03).
const _userAgent =
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/154.0.0.0 Safari/537.36';

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

/// The headers on every Gaana call, mirroring gaana.com's own requests.
///
/// Why this exact set: with the old Chrome 91 set and none of the
/// `deviceType` family, apiv2.gaana.com answers 200 with no entities (Home's
/// sections, occasions, categories, artist songs), while gaana.com/apiv2
/// answers either way. The site does not send X-Requested-With.
Future<Map<String, String>> getGaanaHeaders([String? languages]) async {
  final headers = {
    'User-Agent': _userAgent,
    'Accept': 'application/json, text/plain, */*',
    'Origin': 'https://gaana.com',
    'Referer': 'https://gaana.com/',
    'deviceType': 'GaanaWebsiteApp',
    'deviceId': 'website',
    'COUNTRY': 'IN',
    'appVersion': 'V6',
    'gaanaAppVersion': 'gaanaAndroid-8.60.2',
    'Content-Type': 'application/x-www-form-urlencoded',
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
  Duration timeout,
) async =>
    await gaanaGate.run(() => _send(method, uri, headers, timeout)) ??
    (throw const GaanaBlocked('cooldown after a 403'));

/// Gaana calls sent in the last minute, oldest first, so a refusal can say
/// how many led up to it. What trips Gaana's block is not known yet.
final _recent = <DateTime>[];
const _recentWindow = Duration(seconds: 60);

int _recordCall() {
  final now = DateTime.now();
  _recent.removeWhere((t) => now.difference(t) >= _recentWindow);
  _recent.add(now);
  return _recent.length;
}

final _notWord = RegExp(r'[^A-Za-z0-9]');
final _digit = RegExp(r'\d');

/// Which call this is, for a log line: the `type` of an apiv2 POST, or the
/// host and first two path segments of a GET. Never the query or the rest of
/// the path, which carry search text, ids and slugs; a segment holding a
/// digit is an id and is left out.
@visibleForTesting
String gaanaCallLabel(Uri uri) {
  final type = uri.queryParameters['type'];
  if (type != null) {
    final word = type.replaceAll(_notWord, '');
    return 'type=${word.length > 32 ? word.substring(0, 32) : word}';
  }
  final segments = uri.pathSegments.take(2).where((s) => !_digit.hasMatch(s));
  return '${uri.host}/${segments.join('/')}';
}

Future<GaanaResult> _send(
  String method,
  Uri uri,
  Map<String, String> headers,
  Duration timeout,
) async {
  final recent = _recordCall();
  final dio = _clients.putIfAbsent(timeout, () {
    final d = upstreamDio(timeout: timeout);
    final test = _testAdapter;
    if (test != null) d.httpClientAdapter = test;
    return d;
  });
  try {
    final res = await dio.requestUri<String>(
      uri,
      options: Options(
        method: method,
        headers: headers,
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    );
    final text = res.data ?? '';
    if (res.statusCode == 403 || res.statusCode == 429) {
      debugPrint(
        '[gaana] refused ${gaanaCallLabel(uri)} (${res.statusCode}); '
        '$recent Gaana calls in the last 60 s',
      );
    }
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
