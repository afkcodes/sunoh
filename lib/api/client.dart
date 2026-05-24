// Dio HTTP client for sunoh-api. Single source of truth for the base URL,
// timeouts, and shared interceptors.

import 'package:dio/dio.dart';

class SunohApiEnv {
  static const prod = 'https://api.sunoh.online';
  // Android emulator → 10.0.2.2 maps to the host machine's localhost.
  // On iOS simulator: use 'http://localhost:3600'.
  // On a real device on the same Wi-Fi: use 'http://<host-LAN-ip>:3600'.
  static const localEmulator = 'http://10.0.2.2:3600';
  static const localHost = 'http://localhost:3600';

  // Active base URL. Change this single line when switching environments.
  static const baseUrl = prod;
}

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

  // Minimal request logger (silent in release).
  assert(() {
    dio.interceptors.add(LogInterceptor(
      requestBody: false,
      responseBody: false,
      requestHeader: false,
      responseHeader: false,
      logPrint: (o) {
        // ignore: avoid_print
        print('[sunoh-api] $o');
      },
    ));
    return true;
  }());

  return dio;
}
