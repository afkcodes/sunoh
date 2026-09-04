// Syllable-timed lyrics from LyricsPlus, the open backend behind the YouLy+
// extension.
//
// Ported from BitChord (https://github.com/kushagrasinghx/BitChord), GPL-3.0.
//
// It aggregates Apple Music, QQ Music and Musixmatch, and its v2 response is
// the finest-grained of the sources here — Apple's own syllable splits, not
// just word boundaries.
//
// The catch is hosting: it runs on volunteer mirrors, and at any given moment
// most of them are rate-limited, out of credit or simply gone. The extension's
// answer, copied here, is to ask all of them at once and take the first real
// answer. The winner is remembered so the next track goes straight to a host
// that was up a minute ago instead of paying for the race again.

import 'dart:async';
import 'dart:convert';

import '../../config/env.dart';
import '../../data/lyric_line.dart';
import 'lyric_gaps.dart';
import 'lyrics_http.dart';

/// The mirror that last answered with something. Kept across lookups.
String? _lastGood;

Future<List<LyricLine>?> fetchLyricsPlus({
  required String title,
  required String artist,
  required int durationMs,
  String? album,
}) async {
  final mirrors = Env.lyricsPlusMirrors
      .split(',')
      .map((m) => m.trim())
      .where((m) => m.isNotEmpty)
      .toList();
  if (mirrors.isEmpty) return null;

  final good = _lastGood;
  final hosts = good != null && mirrors.contains(good)
      ? [good, ...mirrors.where((m) => m != good)]
      : mirrors;

  // Take the first mirror to answer with something *usable* rather than the
  // first to answer at all — a mirror that 404s this track shouldn't beat one
  // that has it. Every host is asked at once; the completer takes whichever
  // clears that bar first, and the losers are left to finish into nothing.
  final winner = Completer<List<LyricLine>?>();
  var outstanding = hosts.length;
  for (final host in hosts) {
    unawaited(
      _fetch(host, title, artist, durationMs, album).then((lines) {
        if (winner.isCompleted) return;
        if (lines != null && lines.isNotEmpty) {
          _lastGood = host;
          winner.complete(lines);
          return;
        }
        if (--outstanding == 0) winner.complete(null);
      }),
    );
  }
  return winner.future;
}

Future<List<LyricLine>?> _fetch(
  String host,
  String title,
  String artist,
  int durationMs,
  String? album,
) async {
  final seconds = durationMs ~/ 1000;
  final url = Uri.parse('$host/v2/lyrics/get').replace(
    queryParameters: {
      'title': title,
      'artist': artist,
      if (seconds > 0) 'duration': '$seconds',
      if (album != null && album.isNotEmpty) 'album': album,
    },
  );

  final body = await lyricsGet(url.toString());
  if (body == null) return null;
  try {
    final json = jsonDecode(body);
    if (json is! Map) return null;
    final raw = json['lyrics'];
    if (raw is! List) return null;
    final lines = _parse(raw);
    return lines.isEmpty ? null : lines;
  } on Object {
    return null;
  }
}

List<LyricLine> _parse(List<dynamic> rows) {
  final out = <LyricLine>[];
  for (final row in rows) {
    if (row is! Map) continue;
    final start = (row['time'] as num?)?.toInt();
    if (start == null) continue;

    final words = _mergeSyllables(row['syllabus']);
    if (words.isNotEmpty) {
      final first = words.first.startMs;
      out.add(
        LyricLine(
          start < first ? start : first,
          words.map((w) => w.text).join(' '),
          words: words,
        ),
      );
      continue;
    }
    // Some sources behind it are only line-synced; still worth showing. The
    // line's duration is the only end it gets, and without one an interlude
    // can't be told from a slowly sung line.
    final text = (row['text'] as String?)?.trim();
    if (text == null || text.isEmpty) continue;
    final duration = (row['duration'] as num?)?.toInt();
    out.add(
      LyricLine(
        start,
        text,
        sungUntilMs: duration != null && duration > 0 ? start + duration : null,
      ),
    );
  }
  out.sort((a, b) => a.timeMs.compareTo(b.timeMs));
  return withInstrumentalGaps(out);
}

/// Glues syllables back into words.
///
/// The API's own spacing is the word boundary — it emits `"e"` then
/// `"nough "`, and the trailing space is the only thing saying those are one
/// word. Splitting on the syllable instead would render "e nough".
List<LyricWord> _mergeSyllables(Object? raw) {
  if (raw is! List) return const <LyricWord>[];
  final words = <LyricWord>[];
  final current = StringBuffer();
  var start = 0;
  var end = 0;

  for (final entry in raw) {
    if (entry is! Map) continue;
    final text = entry['text'] as String?;
    if (text == null || text.trim().isEmpty) continue;
    final time = (entry['time'] as num?)?.toInt();
    if (time == null) continue;

    if (current.isEmpty) start = time;
    current.write(text.trim());
    end = time + ((entry['duration'] as num?)?.toInt() ?? 0);
    if (text[text.length - 1].trim().isEmpty) {
      words.add(LyricWord(start, end, current.toString()));
      current.clear();
    }
  }
  if (current.isNotEmpty) words.add(LyricWord(start, end, current.toString()));
  return words;
}
