// Lyrics from SimpMusic's community database, keyed on the YouTube video id.
//
// Ported from BitChord (https://github.com/kushagrasinghx/BitChord), GPL-3.0.
//
// That key is what makes it worth having: every other provider matches on
// title and artist and can hand back a different edit of the same song, which
// drifts out of sync a verse in. This one is looking up the exact track that
// is playing.
//
// Two caveats, both seen in the wild:
//  - the host geoblocks some regions outright, answering 403 with an "access
//    denied from your region" body rather than a network error, so a miss here
//    can be permanent for a given user and the chain must carry on past it;
//  - the rich sync is served HTML-escaped — see [decodeEntities].

import 'dart:convert';

import '../../config/env.dart';
import '../../data/lyric_line.dart';
import 'enhanced_lrc.dart';
import 'lrc_parser.dart';
import 'lyrics_http.dart';

/// Duration slack when the database holds several cuts of one video.
const int _toleranceSeconds = 10;

Future<List<LyricLine>?> fetchSimpMusicLyrics({
  required String videoId,
  required int durationMs,
}) async {
  if (Env.simpMusicLyricsBase.isEmpty || videoId.isEmpty) return null;

  final body = await lyricsGet('${Env.simpMusicLyricsBase}/$videoId');
  if (body == null) return null;

  final tracks = _tracksOf(body);
  if (tracks == null || tracks.isEmpty) return null;

  final seconds = durationMs ~/ 1000;
  Map<String, dynamic>? best;
  var bestDelta = 1 << 30;
  for (final track in tracks) {
    final delta = ((track['duration'] as num?)?.toInt() ?? 0) - seconds;
    final off = delta.abs();
    if (seconds > 0 && off > _toleranceSeconds) continue;
    if (off < bestDelta) {
      best = track;
      bestDelta = off;
    }
  }
  if (best == null) return null;

  // Word timing first; a line-synced answer from here is no better than
  // LRCLIB's, but it is still better than nothing.
  final rich = (best['richSyncLyrics'] as String?)?.trim();
  if (rich != null && rich.isNotEmpty) {
    final lines = parseEnhancedLrc(rich);
    if (lines.isNotEmpty) return lines;
  }
  final synced = (best['syncedLyrics'] as String?)?.trim();
  if (synced != null && synced.isNotEmpty) {
    final lines = parseLrc(synced);
    if (lines.isNotEmpty) return lines;
  }
  return null;
}

List<Map<String, dynamic>>? _tracksOf(String body) {
  try {
    final json = jsonDecode(body);
    if (json is! Map || json['success'] != true) return null;
    final data = json['data'];
    if (data is! List) return null;
    return data.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
  } on Object {
    return null;
  }
}
