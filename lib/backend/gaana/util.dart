// Gaana-specific JS-semantics helpers for walking decoded Gaana JSON. The
// generic ones (capitalizeFirstLetter, isValidTitle, promiseAllLimit) live in
// lib/backend/common.dart.

/// JS truthiness. The TS mappers lean on `a || b` chains where a `0`, `''` or
/// `false` from Gaana must fall through exactly as it did on the server.
bool truthy(Object? v) =>
    v != null && v != false && v != 0 && v != '' && !(v is double && v.isNaN);

/// `a || b`.
Object? or(Object? a, Object? b) => truthy(a) ? a : b;

/// Optional chaining on a decoded-JSON value: `v?.[key]`.
Object? get(Object? v, String key) => v is Map ? v[key] : null;

/// `v?.[index]`.
Object? at(Object? v, int index) =>
    v is List && index >= 0 && index < v.length ? v[index] : null;

/// `.length` of an array or string; null when it has none (JS `undefined`).
int? lengthOf(Object? v) =>
    v is List ? v.length : (v is String ? v.length : null);

/// `v?.toString()` for decoded JSON. Whole doubles print as JS would ("5").
String? jsString(Object? v) {
  if (v == null) return null;
  if (v is double && v == v.truncateToDouble() && v.abs() < 1e21) {
    return v.toInt().toString();
  }
  return v.toString();
}
