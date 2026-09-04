// Word-timed lyrics from BetterLyrics — the backend behind the YouTube Music
// browser extension of the same name.
//
// Ported from BitChord (https://github.com/kushagrasinghx/BitChord), GPL-3.0.
//
// One keyless call keyed on title, artist and duration, answering with Apple
// Music's own TTML. That combination is why it leads the chain: no track-id
// lookup, no token to scrape, no login, and the timing is per-syllable.
//
// Note this is the extension's original host. The project's newer Cloudflare
// API puts the same endpoint behind a Turnstile challenge, which a native
// client has no way to answer.

import 'dart:convert';

import '../../config/env.dart';
import '../../data/lyric_line.dart';
import 'lyrics_http.dart';
import 'ttml_lyrics.dart';

Future<List<LyricLine>?> fetchBetterLyrics({
  required String title,
  required String artist,
  required int durationMs,
  String? album,
}) async {
  if (Env.betterLyricsBase.isEmpty) return null;
  final seconds = durationMs ~/ 1000;
  final url = Uri.parse(Env.betterLyricsBase).replace(
    queryParameters: {
      's': title,
      'a': artist,
      if (seconds > 0) 'd': '$seconds',
      if (album != null && album.isNotEmpty) 'al': album,
    },
  );

  final body = await lyricsGet(url.toString());
  if (body == null) return null;
  final ttml = _ttmlOf(body);
  if (ttml == null || ttml.isEmpty) return null;

  final lines = parseTtml(ttml);
  return lines.isEmpty ? null : lines;
}

String? _ttmlOf(String body) {
  try {
    final json = jsonDecode(body);
    return json is Map ? json['ttml'] as String? : null;
  } on Object {
    return null;
  }
}
