// LRCLIB client — free synced-lyrics database (https://lrclib.net).
//
// We use two endpoints:
//   * `GET /api/get?track_name=&artist_name=&album_name=&duration=` — exact
//     match by track + artist (+ duration). Returns 404 when the catalog
//     doesn't have the song. Cheapest call, used first.
//   * `GET /api/search?track_name=&artist_name=` — fuzzy fallback when the
//     exact lookup misses (e.g. transliterated titles, different artist
//     ordering). Returns an array; we pick the best duration match.
//
// The response carries:
//   - `plainLyrics: String?`      — text only, no timing
//   - `syncedLyrics: String?`     — standard LRC `[mm:ss.xx]line`
//   - `instrumental: bool`        — explicit "no lyrics, instrumental" flag
//
// Network errors / 404s collapse into [LyricsLookupResult.notFound] so
// the UI can render a single "no lyrics" state without exception handling
// at the call site.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class LrcLibClient {
  LrcLibClient({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: 'https://lrclib.net',
              connectTimeout: const Duration(seconds: 6),
              receiveTimeout: const Duration(seconds: 8),
              headers: const {
                // LRCLIB asks integrators to identify themselves so they can
                // troubleshoot traffic spikes. Polite and they recommend it
                // in the docs.
                'User-Agent': 'sunoh/1.0 (https://sunoh.online)',
                'Accept': 'application/json',
              },
              responseType: ResponseType.json,
            ));

  final Dio _dio;

  /// Look up lyrics for one track. Tries the exact endpoint first, falls
  /// back to fuzzy search if it 404s.
  Future<LyricsLookupResult> fetch({
    required String trackName,
    required String artistName,
    String? albumName,
    int? durationSec,
  }) async {
    if (trackName.trim().isEmpty || artistName.trim().isEmpty) {
      return LyricsLookupResult.notFound;
    }
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/api/get',
        queryParameters: {
          'track_name': trackName,
          'artist_name': artistName,
          if (albumName != null && albumName.isNotEmpty)
            'album_name': albumName,
          if (durationSec != null && durationSec > 0) 'duration': durationSec,
        },
      );
      final body = res.data;
      if (body != null) return LyricsLookupResult.fromJson(body);
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) {
        debugPrint('[lrclib] exact-get error: $e');
      }
    }
    // Fuzzy fallback.
    try {
      final res = await _dio.get<List<dynamic>>(
        '/api/search',
        queryParameters: {
          'track_name': trackName,
          'artist_name': artistName,
        },
      );
      final list = res.data;
      if (list == null || list.isEmpty) return LyricsLookupResult.notFound;
      // Pick the entry whose duration is closest to ours (or first if no
      // duration to compare against). LRCLIB search ranks by relevance
      // already, so closeness-in-duration is mostly a tiebreaker for
      // covers / live versions / radio edits.
      Map<String, dynamic> best = (list.first as Map).cast<String, dynamic>();
      if (durationSec != null && durationSec > 0) {
        int bestDelta = (durationSec - _intOr(best['duration'], 0)).abs();
        for (final raw in list) {
          if (raw is! Map) continue;
          final m = raw.cast<String, dynamic>();
          final delta = (durationSec - _intOr(m['duration'], 0)).abs();
          if (delta < bestDelta) {
            best = m;
            bestDelta = delta;
          }
        }
      }
      return LyricsLookupResult.fromJson(best);
    } on DioException catch (e) {
      debugPrint('[lrclib] search error: $e');
      return LyricsLookupResult.notFound;
    }
  }
}

int _intOr(Object? v, int fallback) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

class LyricsLookupResult {
  const LyricsLookupResult({
    required this.found,
    required this.instrumental,
    this.plainLyrics,
    this.syncedLyrics,
  });

  /// Sentinel for "lookup completed but the catalog has nothing for us."
  /// UI renders this the same as a network error — a "no lyrics" state —
  /// since the user-visible outcome is identical.
  static const LyricsLookupResult notFound = LyricsLookupResult(
    found: false,
    instrumental: false,
  );

  final bool found;
  final bool instrumental;
  final String? plainLyrics;
  final String? syncedLyrics;

  bool get hasSynced =>
      syncedLyrics != null && syncedLyrics!.trim().isNotEmpty;
  bool get hasPlain =>
      plainLyrics != null && plainLyrics!.trim().isNotEmpty;

  factory LyricsLookupResult.fromJson(Map<String, dynamic> j) {
    return LyricsLookupResult(
      found: true,
      instrumental: j['instrumental'] == true,
      plainLyrics: (j['plainLyrics'] as String?)?.trim(),
      syncedLyrics: (j['syncedLyrics'] as String?)?.trim(),
    );
  }
}
