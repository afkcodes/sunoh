// A plain Dio for calling upstream services (Saavn, Gaana, PodcastIndex...).
// Deliberately NOT built by buildSunohDio(): that one carries the local
// backend interceptor, and an upstream call routed through it would be
// matched against our own routes. Upstreams also tend to refuse non-browser
// User-Agents, hence the desktop Chrome default.
import 'package:dio/dio.dart';

const _chromeUa =
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/124.0.0.0 Safari/537.36';

Dio upstreamDio({
  Map<String, String> headers = const {},
  Duration timeout = const Duration(seconds: 15),
}) => Dio(
  BaseOptions(
    connectTimeout: timeout,
    receiveTimeout: timeout,
    headers: {'User-Agent': _chromeUa, ...headers},
  ),
);
