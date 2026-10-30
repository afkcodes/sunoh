// Small helpers the unified /music controllers share.
import '../gaana/gaana.dart' as gaana;
import '../local_backend.dart';

/// A route controller as the provider ports expose them.
typedef Ctl =
    Future<LocalReply> Function(
      Map<String, String> params,
      Map<String, String> query,
    );

/// A decoded-JSON object. Values are mutable copies, never shared with the
/// provider ports' own results.
typedef Rec = Map<String, Object?>;

/// The server tags every unified answer with this source.
const unifiedSource = 'unified';

LocalReply unified(Object? data, String message, {bool partial = false}) =>
    LocalReply(data, message: message, source: unifiedSource, partial: partial);

/// First non-empty string, mirroring the TS `a || b || c` over query values.
String? firstNonEmpty(Iterable<String?> values) {
  for (final v in values) {
    if (v != null && v.isNotEmpty) return v;
  }
  return null;
}

/// The failure text the TS controllers send: `error.message || fallback`.
String errorMessage(Object e, String fallback) {
  final String m;
  if (e is LocalApiError) {
    m = e.message;
  } else if (e is StateError) {
    m = e.message;
  } else if (e is gaana.GaanaException) {
    m = e.message;
  } else {
    m = '$e';
  }
  return m.isNotEmpty ? m : fallback;
}

/// Runs [body], turning anything it throws into the unified failure envelope.
Future<LocalReply> unifiedGuard(
  String fallback,
  Future<LocalReply> Function() body,
) async {
  try {
    return await body();
  } on LocalApiError {
    rethrow;
  } on gaana.GaanaBlocked {
    rethrow;
  } catch (e) {
    throw LocalApiError(errorMessage(e, fallback), error: '$e');
  }
}

/// `Promise.allSettled` for one future: the value, or null when it failed.
/// The merge code treats a failed provider as an empty one. [onBlocked] runs
/// when the failure was a Gaana firewall block, so the caller can tell a
/// blocked half from an ordinary failure.
Future<T?> settle<T>(Future<T> f, {void Function()? onBlocked}) async {
  try {
    return await f;
  } on gaana.GaanaBlocked {
    onBlocked?.call();
    return null;
  } catch (_) {
    return null;
  }
}
