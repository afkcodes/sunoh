// Port of saavnFetch (src/saavn/controller.ts) over the TS fetchGet
// (src/helpers/http.ts): same cookie, same language params, same
// retry-on-5xx behaviour, and the same "never throws, returns {data, code,
// error, message}" contract the controllers are written against.
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../upstream.dart';
import 'config.dart';
import 'extract.dart';

/// Mirrors the TS `ResponseResult`: a failed call is a value, not a throw.
class SaavnResponse {
  const SaavnResponse({
    required this.data,
    required this.code,
    required this.message,
    required this.error,
  });

  final Object? data;
  final int code;
  final String message;
  final String? error;
}

Dio? _dio;

/// Tests swap the transport; production uses the shared upstream Dio.
@visibleForTesting
set saavnDioForTesting(Dio? dio) => _dio = dio;

Dio get _client => _dio ??= upstreamDio();

/// Delay between retries; the TS uses 1000 ms. Tests shorten it.
@visibleForTesting
Duration saavnRetryDelay = const Duration(seconds: 1);

const _retries = 3;

// Saavn gates regional catalogue on this cookie. It is the web player's own
// anonymous cookie (the geo is a public Bengaluru address), not a login.
String _cookie(String formattedLangs) =>
    'B=b7984e01db109802c47c5178fac7badc; CT=MjA2Mjg5ODMw; _pl=web6dot0-; '
    'DL=english; L=${Uri.encodeComponent(formattedLangs)}; '
    'geo=49.207.50.17%2CIN%2CKarnataka%2CBengaluru%2C562130; '
    'mm_latlong=12.9753%2C77.591; CH=G03%2CA07%2CO00%2CL03.; '
    'gdpr_acceptance=true';

/// URLSearchParams.append stringification: undefined/null become the words,
/// integral numbers drop the ".0".
String _qs(Object? v) {
  if (v == null || identical(v, undefined)) return 'undefined';
  if (v is double && v == v.truncateToDouble()) return v.toInt().toString();
  return '$v';
}

/// GET api.php with [params]. [lang] is the comma list from `?lang=`.
Future<SaavnResponse> saavnFetch(
  Map<String, Object?> params, {
  String? lang,
}) async {
  final languages = truthy(lang) ? lang! : 'hindi,english';
  final langList = languages.split(',').map((l) => l.trim().toLowerCase());
  final formattedLangs = langList.join(',');
  final primaryLang = langList.first.isEmpty ? 'hindi' : langList.first;

  final merged = {...params};
  if (!truthy(merged['language'])) merged['language'] = primaryLang;
  if (!truthy(merged['languages'])) merged['languages'] = formattedLangs;
  final query = {for (final e in merged.entries) e.key: _qs(e.value)};

  for (var attempt = 0; attempt <= _retries; attempt++) {
    try {
      final res = await _client.get<String>(
        saavnBaseUrl,
        queryParameters: query,
        options: Options(
          headers: {'cookie': _cookie(formattedLangs)},
          // Saavn answers JSON with a text/html content type; decode here.
          responseType: ResponseType.plain,
          validateStatus: (_) => true,
        ),
      );
      final code = res.statusCode ?? 0;
      final message = res.statusMessage ?? (code == 200 ? 'OK' : '');
      final body = res.data ?? '';
      final Object? data;
      try {
        data = body.trim().isEmpty ? null : jsonDecode(body);
      } on FormatException {
        throw const _Transient('Unexpected end of JSON input');
      }
      if (code < 200 || code >= 300) {
        // 4xx is final; 5xx is worth another go (matches TS).
        if (code < 500 || attempt == _retries) {
          return SaavnResponse(
            data: null,
            code: code,
            message: message,
            error: 'HTTP Error $code: $message',
          );
        }
        await Future<void>.delayed(saavnRetryDelay);
        continue;
      }
      return SaavnResponse(
        data: data,
        code: code,
        message: message,
        error: null,
      );
    } on _Transient catch (e) {
      if (attempt == _retries) return _failure(e.message);
    } on DioException catch (e) {
      if (attempt == _retries) return _failure(e.message ?? e.type.name);
    }
    await Future<void>.delayed(saavnRetryDelay);
  }
  return _failure('Unexpected error occurred');
}

SaavnResponse _failure(String message) =>
    SaavnResponse(data: null, code: 0, message: message, error: message);

class _Transient implements Exception {
  const _Transient(this.message);
  final String message;
}
