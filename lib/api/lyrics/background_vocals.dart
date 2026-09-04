// Pulls the answering vocal out of a line and hangs it underneath.
//
// Ported from BitChord (https://github.com/kushagrasinghx/BitChord), GPL-3.0.

import '../../data/lyric_line.dart';

/// Splits a trailing bracket off each line into [LyricLine.background].
///
/// Only Apple's TTML says outright which spans are the backing voice
/// (`ttm:role="x-bg"`, read in `ttml_lyrics.dart`). Every other source —
/// LyricsPlus, SimpMusic's rich sync, LRCLIB — writes it into the line as a
/// bracket:
///
/// ```
/// I'm foolishly patient (Foolishly patient)
/// ```
///
/// Which is a bracket doing the job of a second line, and it shows. The words
/// inside it are sung *over* the line that follows, so the cursor moves on
/// with the bracket half-swept and the strip cuts it off mid-phrase. Split
/// out, the bracket keeps its own timings and draws below the lead instead of
/// being dragged through it.
///
/// The parentheses are kept on the text rather than stripped. They are what
/// the source published, and a smaller line under the lead already says "this
/// is the answer" without the punctuation being taken away.
List<LyricLine> withBackgroundVocals(List<LyricLine> lines) =>
    lines.map(_splitTrailingBracket).toList();

LyricLine _splitTrailingBracket(LyricLine line) {
  // A source that marked its own backing vocal has already said everything
  // guessing from punctuation could, and better.
  if (line.background != null || line.isGap) return line;

  final open = _bracketStart(line.text);
  if (open == null) return line;
  final lead = line.text.substring(0, open).trimRight();
  final backing = line.text.substring(open).trim();
  if (lead.isEmpty) return line;
  if (!backing.contains(RegExp(r'[\p{L}\p{N}]', unicode: true))) return line;

  if (line.words.isEmpty) {
    // Line-synced: there is no timing to divide, so the two halves share the
    // line's stamp and simply stack. Both keep the stated end — it is the
    // line's end, and the line is both of them.
    return line.copyWith(
      text: lead,
      background: LyricLine(
        line.timeMs,
        backing,
        sungUntilMs: line.sungUntilMs,
      ),
    );
  }

  // [text] is the words joined by single spaces in every word-synced parser
  // here, so the bracket's character offset is a word boundary — unless the
  // bracket opens mid-word ("wait(ing)"), in which case it isn't one and there
  // is nothing to hand the backing line for timing. Leave those be.
  final split = _indexOfWordStartingAt(line.words, open);
  if (split == null || split <= 0) return line;

  final backingWords = line.words.sublist(split);
  return line.copyWith(
    text: lead,
    words: line.words.sublist(0, split),
    background: LyricLine(
      backingWords.first.startMs,
      backing,
      words: backingWords,
    ),
  );
}

/// Index of the word starting at character [offset] in the joined text, or
/// null if no word starts there.
int? _indexOfWordStartingAt(List<LyricWord> words, int offset) {
  var at = 0;
  for (var index = 0; index < words.length; index++) {
    if (at == offset) return index;
    if (at > offset) return null;
    // The space that joins this word to the next one.
    at += words[index].text.length + 1;
  }
  return null;
}

/// Where the bracket that closes the line opens, or null if the line does not
/// end in one.
///
/// Walked back from the end counting depth, so a nested bracket doesn't split
/// the line at the inner pair. A line that is *entirely* bracketed is already
/// its own backing line and has no lead to hang under, so it is left alone.
int? _bracketStart(String text) {
  if (!text.endsWith(')')) return null;
  var depth = 0;
  for (var index = text.length - 1; index >= 0; index--) {
    final char = text[index];
    if (char == ')') {
      depth++;
    } else if (char == '(') {
      depth--;
      if (depth == 0) return index > 0 ? index : null;
    }
  }
  return null;
}
