// In-app update notifier.
//
// Published JSON lives at:
//
//   https://sunoh.online/.well-known/sunoh-updates.json
//
// Shape:
//
//   {
//     "version": "1.0.1",        # required, semver-ish
//     "buildNumber": 2,          # optional, integer
//     "url": "https://github.com/<owner>/<repo>/releases/tag/v1.0.1",
//     "notes": "What's new"      # optional, plain text, ≤ ~280 chars
//   }
//
// The version field is the source of truth — when the published version
// compares greater than the running app's pubspec version, we surface an
// update banner that links to `url`. Compares are lexicographic per
// dotted-int segment so 1.10.0 > 1.9.9 holds (no need for a real semver
// dep).

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

const String _kUpdatesUrl =
    'https://sunoh.online/.well-known/sunoh-updates.json';

class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.url,
    this.buildNumber,
    this.notes,
  });
  final String version;
  final int? buildNumber;
  final String url;
  final String? notes;

  factory UpdateInfo.fromJson(Map<String, dynamic> j) {
    return UpdateInfo(
      version: (j['version'] ?? '').toString().trim(),
      buildNumber: j['buildNumber'] is num
          ? (j['buildNumber'] as num).toInt()
          : int.tryParse('${j['buildNumber'] ?? ''}'),
      url: (j['url'] ?? '').toString().trim(),
      notes: (j['notes'] as String?)?.trim(),
    );
  }

  /// True when this published [version] is strictly newer than [current].
  /// Handles 1.0.0 vs 1.0.1 and 1.10 vs 1.9 correctly via per-segment int
  /// compare. Strings that don't parse as ints fall back to lexicographic
  /// compare for that segment — good enough for `1.0.0-beta1` vs
  /// `1.0.0-beta2` edge cases.
  bool isNewerThan(String current) {
    if (version.isEmpty || current.isEmpty) return false;
    final a = version.split('.');
    final b = current.split('.');
    for (var i = 0; i < a.length && i < b.length; i++) {
      final ai = int.tryParse(a[i]);
      final bi = int.tryParse(b[i]);
      if (ai != null && bi != null) {
        if (ai != bi) return ai > bi;
      } else {
        final cmp = a[i].compareTo(b[i]);
        if (cmp != 0) return cmp > 0;
      }
    }
    return a.length > b.length;
  }
}

class UpdatesClient {
  UpdatesClient({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 6),
              receiveTimeout: const Duration(seconds: 8),
              headers: const {'Accept': 'application/json'},
              responseType: ResponseType.json,
            ));
  final Dio _dio;

  /// Returns the published manifest, or `null` when the lookup fails or
  /// the JSON is missing the required fields. Errors are swallowed —
  /// the update notifier is supposed to be silent when unreachable.
  Future<UpdateInfo?> fetch() async {
    try {
      final res = await _dio.get<dynamic>(_kUpdatesUrl);
      final data = res.data;
      if (data is! Map) return null;
      final info = UpdateInfo.fromJson(data.cast<String, dynamic>());
      if (info.version.isEmpty || info.url.isEmpty) return null;
      return info;
    } catch (e) {
      debugPrint('[updates] fetch failed: $e');
      return null;
    }
  }
}
