// The sunoh-api backend, answered on the phone.
//
// Why this layer exists: the upstream services (Gaana refuses albumDetail and
// playlistDetail from the VPS's address, others rate-limit it) are happy with
// the user's own connection, and there is then no server to run or pay for.
// Rather than rewrite the DTO layer, this interceptor answers each sunoh-api
// route locally and returns exactly the JSON envelope the server returns
// today, so lib/api/sunoh_api.dart, stream_resolver.dart, dto.dart and
// everything above them are unchanged.
//
// Migration path: a route with no local handler, or whose handler throws
// anything unexpected, falls through to the real server via `handler.next`.
// Routes move over one at a time and the server can be switched off once the
// last one has.
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'response_cache.dart';

/// A route handler. [body] is whatever the request carried (usually a Map).
/// Return a [LocalReply] or any plain JSON-compatible value.
typedef LocalHandler =
    Future<Object?> Function(
      Map<String, String> params,
      Map<String, String> query,
      Object? body,
    );

/// A handler result that sets the envelope's `message` and `source`.
class LocalReply {
  const LocalReply(
    this.data, {
    this.message = 'OK',
    this.source = 'api',
    this.partial = false,
  });

  final Object? data;

  /// True when a provider was skipped (Gaana blocked), so the answer is
  /// served but must not be cached as if it were the full one.
  final bool partial;
  final String message;
  final String source;
}

/// Thrown by a handler to produce the server's failure envelope (HTTP 400 by
/// default), so callers see exactly what a server-side failure looked like.
class LocalApiError implements Exception {
  LocalApiError(this.message, {this.code = 400, this.error});

  final String message;
  final int code;
  final Object? error;

  @override
  String toString() => 'LocalApiError($code): $message';
}

class _Route {
  _Route(this.method, this.pattern, this.handler, [this.cache])
    : segments = _split(pattern),
      literals = _split(pattern).where((s) => !s.startsWith(':')).length;

  final String method;
  final String pattern;
  final List<String> segments;

  /// Count of literal segments; the tie-break when several routes match.
  final int literals;
  final LocalHandler handler;
  final CachePolicy? cache;
}

class _Match {
  _Match(this.route, this.params);
  final _Route route;
  final Map<String, String> params;
}

List<String> _split(String path) =>
    path.split('/').where((s) => s.isNotEmpty).toList();

/// Method + path-segment routing table. One instance serves the whole app.
class LocalRoutes {
  final List<_Route> _routes = [];

  /// [cache] opts the route into the response cache (response_cache.dart);
  /// without it every request reaches the handler.
  void get(String pattern, LocalHandler h, {CachePolicy? cache}) =>
      _routes.add(_Route('GET', pattern, h, cache));

  void post(String pattern, LocalHandler h) =>
      _routes.add(_Route('POST', pattern, h));

  /// Literal segments win over `:param` ones: the route with the most
  /// literals among those that match is chosen, which makes
  /// `/music/radio/session` beat `/music/radio/:id` whatever the
  /// registration order.
  _Match? _match(String method, String path) {
    final parts = _split(path);
    _Match? best;
    for (final r in _routes) {
      if (r.method != method || r.segments.length != parts.length) continue;
      final params = <String, String>{};
      var ok = true;
      for (var i = 0; i < parts.length; i++) {
        final s = r.segments[i];
        if (s.startsWith(':')) {
          params[s.substring(1)] = _decode(parts[i]);
        } else if (s != parts[i]) {
          ok = false;
          break;
        }
      }
      if (ok && (best == null || r.literals > best.route.literals)) {
        best = _Match(r, params);
      }
    }
    return best;
  }

  static String _decode(String s) {
    try {
      return Uri.decodeComponent(s);
    } on FormatException {
      return s;
    }
  }
}

/// Answers matched routes from [LocalRoutes]; everything else goes to the
/// network untouched.
class LocalBackendInterceptor extends Interceptor {
  LocalBackendInterceptor(this._routes, {ResponseCache? cache})
    : _cache = cache ?? ResponseCache();

  final LocalRoutes _routes;
  final ResponseCache _cache;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final match = _routes._match(options.method, _relativePath(options));
    if (match == null) return handler.next(options);

    try {
      final query = {
        for (final e in options.uri.queryParameters.entries) e.key: e.value,
        for (final e in options.queryParameters.entries) e.key: '${e.value}',
      };
      Future<LocalReply> run() async {
        final out = await match.route.handler(
          match.params,
          query,
          options.data,
        );
        return out is LocalReply ? out : LocalReply(out);
      }

      final policy = match.route.cache;
      final reply = policy == null
          ? await run()
          : await _cache.run(
              ResponseCache.keyFor(
                options.method,
                match.route.pattern,
                match.params,
                query,
              ),
              policy,
              run,
              refresh: options.headers[localRefreshHeader] != null,
            );
      handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: {
            'status': 'success',
            'message': reply.message,
            'data': reply.data,
            'error': null,
            'source': reply.source,
          },
        ),
      );
    } on LocalApiError catch (e) {
      handler.reject(
        DioException.badResponse(
          statusCode: e.code,
          requestOptions: options,
          response: Response<Map<String, dynamic>>(
            requestOptions: options,
            statusCode: e.code,
            data: {
              'status': 'failed',
              'message': e.message,
              'data': null,
              'error': e.error ?? e.message,
            },
          ),
        ),
      );
    } catch (e) {
      // Log the pattern, never the concrete path: it carries ids.
      debugPrint(
        '[local-api] ${options.method} ${match.route.pattern} failed on '
        'device (${e.runtimeType}); asking the server',
      );
      handler.next(options);
    }
  }

  /// Path relative to the base URL, query stripped. `options.path` may be
  /// relative ('/music/home') or absolute; a base-URL path prefix is removed.
  String _relativePath(RequestOptions o) {
    var path = o.path;
    if (path.contains('://')) path = Uri.parse(path).path;
    final base = o.baseUrl.isEmpty ? '' : Uri.parse(o.baseUrl).path;
    final prefix = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    if (prefix.isNotEmpty && path.startsWith('$prefix/')) {
      path = path.substring(prefix.length);
    }
    final q = path.indexOf('?');
    return q < 0 ? path : path.substring(0, q);
  }
}
