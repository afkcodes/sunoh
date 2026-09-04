// LRC parser — the standard `[mm:ss.xx]line` format LRCLIB and Musixmatch
// return, plus the `<mm:ss.xx>` word runs an "enhanced" A2 file carries.
//
// Moved here from `lib/audio/lrc_parser.dart` when lyrics grew from one
// source to six: it is a lyric parser, not part of playback.
//
// Supports:
//   * `[mm:ss]`, `[mm:ss.xx]`, `[mm:ss.xxx]` timestamps
//   * Multiple timestamps on one line (a line shared across several beats)
//   * ID-tag lines like `[ti:Title]` / `[ar:Artist]` — skipped silently
//   * Blank lines, kept as the instrumental gaps LRC intends them to be
//
// Timestamps used to be floored to whole seconds, because AppState's position
// tick only moved once a second. They are milliseconds now — see
// `lib/data/lyric_line.dart` for why word timing forced that.

import '../../data/lyric_line.dart';
import 'lyric_gaps.dart';

final RegExp _stamp = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]');
final RegExp _wordStamp = RegExp(r'<(\d{1,3}):(\d{2})[.:](\d{2,3})>');

List<LyricLine> parseLrc(String raw) {
  final all = <LyricLine>[];
  for (final rawLine in raw.split('\n')) {
    final line = rawLine.replaceAll('\r', '');
    final matches = _stamp.allMatches(line).toList();
    if (matches.isEmpty) continue;

    // Everything after the last leading stamp is the line's own body, word
    // runs included.
    final body = line.substring(matches.last.end);
    // Stripped rather than rebuilt from the word runs below: the spacing and
    // punctuation between two words belong to the line, and re-joining the
    // words with single spaces would quietly rewrite a line that never had
    // them.
    final text = body.replaceAll(_wordStamp, '').trim();
    final words = _parseWordRuns(body);

    for (final m in matches) {
      all.add(
        LyricLine(
          _msOf(m.group(1)!, m.group(2)!, m.group(3)),
          text,
          words: words,
        ),
      );
    }
  }
  all.sort((a, b) => a.timeMs.compareTo(b.timeMs));

  // A blank line in an LRC file is a gap marker, but only a long one is worth
  // drawing — a bare stamp a second after the line before it is just how some
  // writers close a verse.
  final kept = <LyricLine>[];
  for (var i = 0; i < all.length; i++) {
    final line = all[i];
    if (!line.isGap) {
      kept.add(line);
      continue;
    }
    // A trailing stamp closes off the last line — that's the outro.
    if (i + 1 >= all.length) {
      kept.add(line);
      continue;
    }
    if (all[i + 1].timeMs - line.timeMs >= kMinGapMs) kept.add(line);
  }

  // Nothing stands for the intro — LRC files start at the first sung word — so
  // give the run-up its own break when it's long enough.
  if (kept.isEmpty) return kept;
  final first = kept.first;
  if (!first.isGap && first.timeMs >= kMinGapMs) {
    return [const LyricLine(0, ''), ...kept];
  }
  return kept;
}

/// The `<mm:ss.xx>` runs of an "enhanced" A2 line, as words.
///
/// Each run ends where the next one starts, which is why an A2 line often
/// closes with a bare stamp naming no word: it exists only to state where the
/// previous one stopped. A run with no text is therefore a terminator rather
/// than a word.
///
/// Empty for a plain line, which is what keeps [LyricLine.isWordSynced]
/// honest — a line-synced source stays line-synced through this.
List<LyricWord> _parseWordRuns(String body) {
  final marks = _wordStamp.allMatches(body).toList();
  if (marks.isEmpty) return const <LyricWord>[];

  final starts = <int>[];
  final texts = <String>[];
  for (var i = 0; i < marks.length; i++) {
    final until = i + 1 < marks.length ? marks[i + 1].start : body.length;
    starts.add(
      _msOf(marks[i].group(1)!, marks[i].group(2)!, marks[i].group(3)),
    );
    texts.add(body.substring(marks[i].end, until));
  }

  final words = <LyricWord>[];
  for (var i = 0; i < starts.length; i++) {
    if (texts[i].trim().isEmpty) continue;
    // The next run's stamp is this word's end — including when that run is the
    // closing terminator, which is the only thing that gives the last word of
    // a line an end at all.
    final end = i + 1 < starts.length ? starts[i + 1] : starts[i];
    words.add(
      LyricWord(starts[i], end < starts[i] ? starts[i] : end, texts[i].trim()),
    );
  }
  return words;
}

int _msOf(String minutes, String seconds, String? fraction) {
  final fractionMs = switch (fraction?.length) {
    1 => int.parse(fraction!) * 100,
    2 => int.parse(fraction!) * 10,
    3 => int.parse(fraction!),
    _ => 0,
  };
  return int.parse(minutes) * 60000 + int.parse(seconds) * 1000 + fractionMs;
}

/// Build a synthetic [LyricLine] list from plain text (no timing info).
///
/// Spreads the text evenly across an estimated duration so a static fallback
/// render still looks like lyrics instead of a wall of text. Highlighting off
/// this is a guess and the UI says so — it is only reached when no source had
/// anything synced.
List<LyricLine> plainLyricsAsLines(String raw, {int totalSec = 180}) {
  final lines = raw.split('\n').map((l) => l.trim()).toList();
  // Drop trailing blanks but keep interior ones for verse spacing.
  while (lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }
  if (lines.isEmpty) return const [];
  final spacing = (totalSec / lines.length).clamp(2.0, 8.0);
  return [
    for (var i = 0; i < lines.length; i++)
      LyricLine((i * spacing * 1000).round(), lines[i]),
  ];
}
