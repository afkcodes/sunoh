// JavaScript semantics the TS mappers rely on, kept explicit so the port can
// be audited against them: `undefined` vs `null`, truthiness and `||`.
//
// Why a sentinel: the server serialises with JSON.stringify, which drops
// undefined keys but keeps null ones. dto.dart is tolerant, but "same keys,
// null-vs-missing" is the parity contract, so mappers build their output with
// [clean] and absent upstream fields never reach the JSON.
class _Undefined {
  const _Undefined();
  @override
  String toString() => 'undefined';
}

/// Stand-in for JS `undefined`: "the path did not exist".
const Object undefined = _Undefined();

/// JS truthiness: false for undefined, null, false, 0, NaN and ''.
bool truthy(Object? v) {
  if (v == null || identical(v, undefined)) return false;
  if (v is bool) return v;
  if (v is num) return v != 0 && !v.isNaN;
  if (v is String) return v.isNotEmpty;
  return true;
}

/// JS `a || b || c`: first truthy value, else the last one.
Object? or(List<Object?> xs) {
  for (var i = 0; i < xs.length - 1; i++) {
    if (truthy(xs[i])) return xs[i];
  }
  return xs.last;
}

/// Drops [undefined] entries, mirroring JSON.stringify.
Map<String, Object?> clean(Map<String, Object?> m) => {
  for (final e in m.entries)
    if (!identical(e.value, undefined)) e.key: e.value,
};

/// `undefined` to null for values that leave the mapper layer as plain data.
Object? defined(Object? v) => identical(v, undefined) ? null : v;

/// helpers/dataExtractor.ts. Returns [undefined] when no path resolves, and
/// stops at the first path whose value is not undefined (null counts).
Object? ex(Object? obj, Object keys, {String delimiter = '.'}) {
  final paths = keys is List ? keys.cast<String>() : [keys as String];
  for (final path in paths) {
    final r = _single(obj, path, delimiter);
    if (!identical(r, undefined)) return r;
  }
  return undefined;
}

Object? _single(Object? obj, String path, String delimiter) {
  if (obj is! Map && obj is! List) return undefined;
  Object? cur = obj;
  for (final k in path.split(delimiter)) {
    if (cur is List) {
      final i = int.tryParse(k);
      if (i == null || i < 0 || i >= cur.length) return undefined;
      cur = cur[i];
    } else if (cur is Map) {
      cur = cur.containsKey(k) ? cur[k] : undefined;
    } else {
      return undefined;
    }
  }
  return cur;
}

/// Public flavour of [ex] for callers outside the saavn mappers: missing
/// becomes null.
T? dataExtractor<T>(Object? obj, Object keys, {String delimiter = '.'}) {
  final v = defined(ex(obj, keys, delimiter: delimiter));
  return v is T ? v : null;
}

/// Property read on something that may not be an object (`x?.key`).
Object? prop(Object? o, String key) =>
    o is Map && o.containsKey(key) ? o[key] : undefined;

/// JS string coercion for the places TS passes `any` where a string is used.
String str(Object? v) => (v == null || identical(v, undefined)) ? '' : '$v';
