// Structural JSON comparison for parity tests: same key sets and value types
// at every path, ignoring values. Reusable by other backend modules.
//
// Arrays are collapsed: every element contributes to one shared `[]` path, so
// two lists match when the union of their element shapes matches, not when
// they have the same length or order. Live feeds reorder and resize between
// two calls a second apart; their shape does not.

/// Paths (`a.b[].c`) mapped to the set of value types seen there.
Map<String, Set<String>> shapeOf(Object? json) {
  final out = <String, Set<String>>{};
  void walk(Object? v, String path) {
    out.putIfAbsent(path, () => <String>{}).add(_type(v));
    if (v is Map) {
      for (final e in v.entries) {
        walk(e.value, path.isEmpty ? '${e.key}' : '$path.${e.key}');
      }
    } else if (v is List) {
      for (final e in v) {
        walk(e, '$path[]');
      }
    }
  }

  walk(json, '');
  return out;
}

String _type(Object? v) => switch (v) {
  null => 'null',
  bool() => 'bool',
  num() => 'num',
  String() => 'string',
  List() => 'list',
  Map() => 'object',
  _ => v.runtimeType.toString(),
};

/// Differences between [expected] (the server) and [actual] (the port) as
/// readable lines; empty means the shapes match.
///
/// A path that is merely `null` on one side and absent from the other's
/// sampled items is not reported when [lenientNull] is set, since optional
/// fields appear or not depending on which items a feed happened to return.
/// Paths under any [ignore] prefix are skipped.
List<String> shapeDiff(
  Object? expected,
  Object? actual, {
  Set<String> ignore = const {},
  bool lenientNull = true,
}) {
  final a = shapeOf(expected);
  final b = shapeOf(actual);
  bool skipped(String p) => ignore.any(p.startsWith);
  final diffs = <String>[];
  for (final path in {...a.keys, ...b.keys}) {
    if (skipped(path)) continue;
    final ta = a[path];
    final tb = b[path];
    if (ta == null || tb == null) {
      final present = ta ?? tb!;
      // Item-sampling artefact: a field that only ever held null.
      if (lenientNull && present.every((t) => t == 'null')) continue;
      diffs.add(
        '${ta == null ? 'only in port' : 'missing in port'}: '
        '${path.isEmpty ? '<root>' : path} ($present)',
      );
      continue;
    }
    bool eq(Set<String> x, Set<String> y) => lenientNull
        ? _noNull(x).difference(_noNull(y)).isEmpty &&
              _noNull(y).difference(_noNull(x)).isEmpty
        : x.length == y.length && x.containsAll(y);
    if (!eq(ta, tb)) {
      diffs.add(
        'type differs at ${path.isEmpty ? '<root>' : path}: server $ta vs port $tb',
      );
    }
  }
  diffs.sort();
  return diffs;
}

Set<String> _noNull(Set<String> s) => s.difference({'null'});
