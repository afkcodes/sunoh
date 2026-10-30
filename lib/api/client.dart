// Dio HTTP client for sunoh-api. Single source of truth for the base URL,
// timeouts, and shared interceptors.

import 'package:dio/dio.dart';

import '../backend/local_backend.dart';
import '../backend/response_cache.dart';
import '../backend/routes.dart';
import '../config/env.dart';

class SunohApiEnv {
  /// Set by `--dart-define-from-file=env.json` — see lib/config/env.dart.
  ///
  /// Pointing at a local server is a matter of changing env.json rather than
  /// editing this file: `http://10.0.2.2:3600` for an Android emulator (which
  /// maps to the host's localhost), or the host's LAN IP for a real device.
  static const baseUrl = Env.apiBase;
}

// One registry for the app, not one per Dio.
final _localRoutes = buildLocalRoutes();
// Shared too: de-duplication and the memory layer only work across Dios if
// they all use one cache.
final _responseCache = ResponseCache();

Dio buildSunohDio() {
  final dio = Dio(
    BaseOptions(
      baseUrl: SunohApiEnv.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      headers: const {'Accept': 'application/json'},
      // sunoh-api wraps responses in { status, message, data, ... } — we want
      // the raw Map; no automatic type cast surprises.
      responseType: ResponseType.json,
    ),
  );

  // First, so a locally answered route never reaches the network.
  dio.interceptors.add(
    LocalBackendInterceptor(_localRoutes, cache: _responseCache),
  );

  // Minimal request logger (silent in release).
  assert(() {
    dio.interceptors.add(
      LogInterceptor(
        requestBody: false,
        responseBody: false,
        requestHeader: false,
        responseHeader: false,
        logPrint: (o) {
          // ignore: avoid_print
          print('[sunoh-api] $o');
        },
      ),
    );
    return true;
  }());

  return dio;
}
