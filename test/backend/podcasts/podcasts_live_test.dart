@Tags(['live'])
library;

// Parity against the deployed server. Run with:
//   flutter test --run-skipped -t live test/backend/podcasts/
// Only the PodcastIndex key/secret and SUNOH_API_BASE are read from env.json,
// and none is printed.
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunoh/backend/local_backend.dart';
import 'package:sunoh/backend/podcasts/podcast_index_client.dart';
import 'package:sunoh/backend/podcasts/routes.dart';

/// Any request reaching the network means the local handler fell through.
class _NoNetwork implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? s,
    Future<void>? c,
  ) => throw StateError('local handler fell through to server');

  @override
  void close({bool force = false}) {}
}

/// Recursive shape: maps keep keys, lists merge their elements.
Object? shape(Object? v) {
  if (v is Map) return {for (final e in v.entries) '${e.key}': shape(e.value)};
  if (v is List) return [v.map(shape).fold<Object?>(null, _merge)];
  if (v == null) return 'null';
  if (v is num) return 'num';
  return v.runtimeType.toString();
}

Object? _merge(Object? a, Object? b) {
  if (a == null) return b;
  if (a is Map && b is Map) {
    return {
      for (final k in {...a.keys, ...b.keys})
        k: a.containsKey(k) && b.containsKey(k)
            ? _merge(a[k], b[k])
            : (a[k] ?? b[k]),
    };
  }
  if (a is List && b is List) {
    return [a.isEmpty ? (b.isEmpty ? null : b.first) : a.first];
  }
  return a == 'null' ? b : a;
}

/// Differences in key sets and leaf types; 'null' matches anything.
void diff(Object? a, Object? b, String path, List<String> out) {
  if (a is Map && b is Map) {
    for (final k in {...a.keys, ...b.keys}) {
      if (!a.containsKey(k)) {
        out.add('$path.$k only on server');
      } else if (!b.containsKey(k)) {
        out.add('$path.$k only local');
      } else {
        diff(a[k], b[k], '$path.$k', out);
      }
    }
  } else if (a is List && b is List) {
    if (a.first != null && b.first != null) {
      diff(a.first, b.first, '$path[]', out);
    }
  } else if (a != b && a != 'null' && b != 'null') {
    out.add(
      '$path type ${a.runtimeType == String ? a : 'obj'} vs ${b.runtimeType == String ? b : 'obj'}',
    );
  }
}

void main() {
  final env =
      jsonDecode(File('env.json').readAsStringSync()) as Map<String, dynamic>;
  final base = env['SUNOH_API_BASE'] as String;

  final routes = LocalRoutes();
  registerPodcastRoutes(
    routes,
    client: PodcastIndexClient(
      key: env['PODCASTINDEX_KEY'] as String? ?? '',
      secret: env['PODCASTINDEX_SECRET'] as String? ?? '',
    ),
  );
  final local = Dio(BaseOptions(baseUrl: base))
    ..httpClientAdapter = _NoNetwork()
    ..interceptors.add(LocalBackendInterceptor(routes));
  final server = Dio(BaseOptions(baseUrl: base));

  Future<Map> call(Dio d, String path, Map<String, dynamic> q) async {
    final r = await d.get<Map>(path, queryParameters: q);
    return r.data!;
  }

  Future<void> compare(String path, [Map<String, dynamic> q = const {}]) async {
    final l = await call(local, path, q);
    final s = await call(server, path, q);
    expect(l['status'], s['status']);
    expect(l['message'], s['message'], reason: 'message');
    expect(l['source'], s['source'], reason: 'source');
    final d = <String>[];
    diff(shape(s), shape(l), '', d);
    debugPrint('PARITY $path: ${d.isEmpty ? 'match' : d.join('; ')}');
    // Optional keys legitimately differ with data; a type clash never does.
    expect(d.where((e) => e.contains(' type ')), isEmpty);
  }

  const timeout = Timeout(Duration(minutes: 2));
  final tests = <String, Future<void> Function()>{
    'home': () => compare('/podcasts/home', {'country': 'IN'}),
    'search': () =>
        compare('/podcasts/search', {'q': 'history', 'country': 'IN'}),
    'categories': () => compare('/podcasts/categories', {'country': 'IN'}),
    'by-category': () =>
        compare('/podcasts/by-category/News', {'max': 5, 'country': 'IN'}),
    'show': () => compare('/podcasts/920666', {'max': 5, 'country': 'IN'}),
    'episodes': () =>
        compare('/podcasts/920666/episodes', {'max': 5, 'country': 'IN'}),
  };
  tests.forEach((n, f) => test(n, f, timeout: timeout));

  test('episode by guid', () async {
    final eps = await call(server, '/podcasts/920666/episodes', {'max': 1});
    final e = (eps['data']['list'] as List).first as Map;
    // The guid is not in the mapped JSON; look it up via the numeric id.
    await compare('/podcasts/episode/none', {'id': e['id']});
  }, timeout: timeout);
}
