// PodcastIndex.org HTTP client, ported from sunoh-api src/podcast/client.ts.
//
// Auth is a plain SHA-1 of key + secret + unix seconds (lowercase hex), NOT
// an HMAC despite what some PodcastIndex examples call it. The key and secret
// are compile-time dart-defines; they ship inside the APK, which is the cost
// of dropping the server (PodcastIndex keys are free and rate-limited, not
// billing credentials). Neither is ever logged.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../../config/env.dart';
import '../local_backend.dart';
import '../upstream.dart';

const _baseUrl = 'https://api.podcastindex.org/api/1.0';
const _userAgent = 'sunoh-api/1.0 (+https://sunoh.online)';

/// The four headers PodcastIndex requires. [unixSeconds] is a parameter so
/// tests can pin the clock.
Map<String, String> podcastAuthHeaders(
  String key,
  String secret,
  int unixSeconds,
) {
  final t = '$unixSeconds';
  return {
    'User-Agent': _userAgent,
    'X-Auth-Date': t,
    'X-Auth-Key': key,
    'Authorization': sha1.convert(utf8.encode('$key$secret$t')).toString(),
  };
}

/// Query string the way the server built it: null and empty values dropped.
Map<String, String> cleanParams(Map<String, Object?> params) => {
  for (final e in params.entries)
    if (e.value != null && '${e.value}'.isNotEmpty) e.key: '${e.value}',
};

/// Outcome of one upstream call; mirrors the server's PodcastIndexResult.
class PiResult {
  const PiResult({required this.ok, this.data, this.error});
  final bool ok;
  final Map<String, dynamic>? data;
  final String? error;
}

class PodcastIndexClient {
  PodcastIndexClient({
    Dio? dio,
    String? key,
    String? secret,
    int Function()? now,
  }) : _dio = dio ?? upstreamDio(),
       _key = key ?? Env.podcastIndexKey,
       _secret = secret ?? Env.podcastIndexSecret,
       _now = now ?? (() => DateTime.now().millisecondsSinceEpoch ~/ 1000);

  final Dio _dio;
  final String _key;
  final String _secret;
  final int Function() _now;

  bool get configured => _key.isNotEmpty && _secret.isNotEmpty;

  /// Throws the clear failure the server gave (503) instead of letting
  /// PodcastIndex answer 401.
  void ensureConfigured() {
    if (configured) return;
    throw LocalApiError(
      'Podcasts backend not configured (PODCASTINDEX_KEY / '
      'PODCASTINDEX_SECRET missing from env.json at build time).',
      code: 503,
    );
  }

  Future<PiResult> get(
    String path, [
    Map<String, Object?> params = const {},
  ]) async {
    ensureConfigured();
    try {
      final res = await _dio.get<String>(
        '$_baseUrl$path',
        queryParameters: cleanParams(params),
        options: Options(
          headers: podcastAuthHeaders(_key, _secret, _now()),
          responseType: ResponseType.plain,
          validateStatus: (_) => true,
        ),
      );
      final status = res.statusCode ?? 0;
      final body = res.data ?? '';
      Object? parsed;
      try {
        parsed = body.isEmpty ? null : jsonDecode(body);
      } on FormatException {
        final cut = body.length > 200 ? body.substring(0, 200) : body;
        return PiResult(
          ok: false,
          error: 'Non-JSON response (status $status): $cut',
        );
      }
      final map = parsed is Map<String, dynamic> ? parsed : null;
      if (status < 200 || status >= 300) {
        final desc = map?['description'] ?? map?['message'] ?? 'HTTP $status';
        return PiResult(ok: false, error: '$desc', data: map);
      }
      return PiResult(ok: true, data: map);
    } on DioException catch (e) {
      return PiResult(ok: false, error: 'network: ${e.message ?? e.type}');
    }
  }
}
