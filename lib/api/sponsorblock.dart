// SponsorBlock — community-submitted segment data used to skip the parts of
// a YouTube track that aren't the music: sponsor reads, self-promo, intros,
// outros, and non-music talking sections.
//
// Privacy: we deliberately use the hash-prefix endpoint rather than
// `?videoID=`. It takes only the first four hex characters of
// sha256(videoId) and returns every video sharing that prefix (~120 per
// request), so the server never learns which track is being played. We pick
// ours out of the response locally. The extra payload is small and it keeps
// listening history off a third-party server.

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

/// A segment worth skipping.
class SkipSegment {
  const SkipSegment({
    required this.start,
    required this.end,
    required this.category,
    required this.uuid,
  });

  final Duration start;
  final Duration end;
  final String category;

  /// Stable id from the API. Used to remember which segments we've already
  /// acted on so a manual seek back into one isn't fought by the skipper.
  final String uuid;

  Duration get length => end - start;

  @override
  String toString() =>
      '$category ${start.inSeconds}s->${end.inSeconds}s';
}

/// Categories enabled by default.
///
/// Tuned for a music player: these are the ones that are reliably *not the
/// song*. `filler` and `preview` are deliberately excluded — on music
/// uploads they're often applied to parts of the track itself, and a player
/// that clips the music is worse than one that plays a five-second intro.
const kDefaultSponsorBlockCategories = <String>{
  'sponsor',
  'selfpromo',
  'interaction',
  'intro',
  'outro',
  'music_offtopic',
};

class SponsorBlockClient {
  SponsorBlockClient(this._dio);
  final Dio _dio;

  static const _kBase = 'https://sponsor.ajay.app/api/skipSegments';

  /// Segments for [videoId], or an empty list when there are none (by far
  /// the common case) or the lookup fails. Never throws: missing segment
  /// data must never stop a track from playing.
  Future<List<SkipSegment>> segmentsFor(
    String videoId, {
    Set<String> categories = kDefaultSponsorBlockCategories,
  }) async {
    if (videoId.isEmpty || categories.isEmpty) return const [];
    final prefix =
        sha256.convert(utf8.encode(videoId)).toString().substring(0, 4);
    try {
      final res = await _dio.get<List<dynamic>>(
        '$_kBase/$prefix',
        queryParameters: {'categories': jsonEncode(categories.toList())},
        options: Options(
          responseType: ResponseType.json,
          // 404 = nothing for this prefix, which is normal.
          validateStatus: (s) => s != null && s < 500,
          headers: const {'Accept': 'application/json'},
        ),
      );
      final body = res.data;
      if (body == null) return const [];

      for (final entry in body) {
        if (entry is! Map) continue;
        if (entry['videoID'] != videoId) continue;
        return _parseSegments(entry['segments'], categories);
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  List<SkipSegment> _parseSegments(Object? raw, Set<String> categories) {
    if (raw is! List) return const [];
    final out = <SkipSegment>[];
    for (final s in raw) {
      if (s is! Map) continue;

      // `actionType` can be skip / mute / poi / full. Only `skip` describes
      // a range to jump over; `full` marks the entire upload as one
      // category and skipping it would skip the song.
      if ((s['actionType'] ?? 'skip') != 'skip') continue;

      // Negative votes mean the community disputed it. Acting on those is
      // how a player ends up cutting into the actual music.
      final votes = (s['votes'] as num?)?.toInt() ?? 0;
      if (votes < 0) continue;

      final category = (s['category'] ?? '').toString();
      if (!categories.contains(category)) continue;

      final bounds = s['segment'];
      if (bounds is! List || bounds.length < 2) continue;
      final startSec = (bounds[0] as num?)?.toDouble();
      final endSec = (bounds[1] as num?)?.toDouble();
      if (startSec == null || endSec == null || endSec <= startSec) continue;

      out.add(SkipSegment(
        start: Duration(milliseconds: (startSec * 1000).round()),
        end: Duration(milliseconds: (endSec * 1000).round()),
        category: category,
        uuid: (s['UUID'] ?? '').toString(),
      ));
    }
    out.sort((a, b) => a.start.compareTo(b.start));
    return out;
  }
}
