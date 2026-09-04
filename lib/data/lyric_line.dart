// One line of a song, with as much timing as whichever source had it.
//
// Ported from BitChord (https://github.com/kushagrasinghx/BitChord), GPL-3.0,
// along with the multi-source lookup in `lib/api/lyrics/`. The model is the
// part that matters: every provider parses into this, so the UI never learns
// where a line came from.
//
// Times are milliseconds. They used to be seconds, which was enough while
// LRCLIB was the only source — a whole line lights up and second resolution
// is invisible. Word timing is not: a syllable lasts ~150 ms, so a clock that
// only moves once a second cannot follow one.

/// One word of a line, with the stretch of the song it is sung over.
///
/// Apple's TTML splits long words into syllables; those are merged back into
/// whole words on the way in, so [startMs] is the first syllable's start and
/// [endMs] the last one's end. Whole words are what the sweep needs — a
/// highlight that ran across "e" and "nough" separately reads as a stutter.
class LyricWord {
  const LyricWord(this.startMs, this.endMs, this.text);

  final int startMs;
  final int endMs;
  final String text;
}

/// One line. [timeMs] is when it starts; an empty [text] is an instrumental
/// stretch, the way an LRC file marks one with a bare timestamp.
///
/// [words] is populated only by the sources that carry word timing. LRCLIB's
/// plain sync has none, so a line from there highlights whole — see
/// [isWordSynced].
///
/// [sungUntilMs] is the line's own end where a line-synced source states one,
/// which is what lets an interlude be told apart from a slowly sung line.
///
/// [background] is the answering vocal — the "(ooh)" or the echoed half-phrase
/// a second voice sings over the lead. It is a line in its own right, with its
/// own stamp and its own words, because that is what it is: it starts partway
/// through the line it answers and routinely runs past the *next* line's
/// stamp. Run into [text] it drags the sweep along with it, and the cursor —
/// which takes the last line whose stamp has passed — moves on before the
/// bracket has been sung, so the tail of the line gets skipped. Kept apart it
/// draws underneath the lead on its own clock. Never nested: a background
/// line's own [background] is always null.
class LyricLine {
  const LyricLine(
    this.timeMs,
    this.text, {
    this.words = const <LyricWord>[],
    this.sungUntilMs,
    this.background,
  });

  final int timeMs;
  final String text;
  final List<LyricWord> words;
  final int? sungUntilMs;
  final LyricLine? background;

  bool get isGap => text.isEmpty;

  bool get isWordSynced => words.isNotEmpty;

  /// Whether anything actually said when the singing *stops*, rather than only
  /// when it starts. Word timings carry it, and so does a source that stamps
  /// the line's own end.
  ///
  /// The distance to the next line's stamp is *not* evidence of an end: that
  /// distance is the line's own slot, and on a line-synced source it is
  /// routinely ten seconds for a line sung over all ten of them.
  bool get hasKnownEnd => words.isNotEmpty || sungUntilMs != null;

  /// When the last word finishes — or the line's own end where the source gave
  /// one, or [timeMs] when nothing did. Check [hasKnownEnd] before reading a
  /// silence out of this.
  ///
  /// The answering vocal counts: it is still this line being sung, and it
  /// regularly holds a note past the lead's last word. Measured without it, a
  /// break would be found in the middle of a line that is still going.
  int get endMs {
    final lead = words.isNotEmpty ? words.last.endMs : sungUntilMs ?? timeMs;
    final backing = background?.endMs;
    return backing != null && backing > lead ? backing : lead;
  }

  LyricLine copyWith({
    String? text,
    List<LyricWord>? words,
    LyricLine? background,
  }) => LyricLine(
    timeMs,
    text ?? this.text,
    words: words ?? this.words,
    sungUntilMs: sungUntilMs,
    background: background ?? this.background,
  );

  /// Which word is being sung, and how far through it, or null once the line
  /// is done.
  ///
  /// The timing half of the sweep, kept apart from the drawing half. Where the
  /// edge lands on screen is a question about glyphs, and the answer differs
  /// per script — see the painter, which measures the word's own box rather
  /// than counting characters, because a Devanagari cluster is several
  /// characters wide and none of the positions inside it are real.
  (int index, double through)? wordProgress(int positionMs) {
    for (var index = 0; index < words.length; index++) {
      final word = words[index];
      if (positionMs < word.startMs) return (index, 0);
      if (positionMs < word.endMs) {
        final span = (word.endMs - word.startMs).clamp(1, 1 << 30);
        return (index, (positionMs - word.startMs) / span);
      }
    }
    return null;
  }

  /// How far through the line the singing has got, as a fractional index into
  /// [text]. The sweep reveals up to this character.
  ///
  /// Within a word it interpolates across that word's own span, so a held note
  /// draws slowly and a rattled-off one snaps. Whitespace between two words is
  /// credited to the gap between them: it fills as the singer moves on rather
  /// than jumping ahead to the next word's first letter.
  double revealedChars(int positionMs) {
    if (words.isEmpty) {
      return positionMs >= timeMs ? text.length.toDouble() : 0;
    }
    var offset = 0;
    for (var index = 0; index < words.length; index++) {
      final word = words[index];
      // Where this word sits in [text]. Found by walking forward rather than
      // searching from the start, so a word repeated in the line still lines
      // up with its own occurrence.
      final found = text.indexOf(word.text, offset);
      final start = found >= 0 ? found : offset;
      final end = start + word.text.length;

      if (positionMs < word.startMs) return start.toDouble();
      if (positionMs < word.endMs) {
        final span = (word.endMs - word.startMs).clamp(1, 1 << 30);
        final through = (positionMs - word.startMs) / span;
        return start + through * word.text.length;
      }
      // Past this word: the trailing space fills over the pause before the
      // next one, so the highlight keeps creeping instead of resting on the
      // word's last letter.
      final next = index + 1 < words.length ? words[index + 1] : null;
      if (next != null && positionMs < next.startMs) {
        final gapFound = text.indexOf(next.text, end);
        final gapStart = gapFound >= 0 ? gapFound : end;
        final pause = (next.startMs - word.endMs).clamp(1, 1 << 30);
        final through = (positionMs - word.endMs) / pause;
        return end + through * (gapStart - end);
      }
      offset = end;
    }
    return text.length.toDouble();
  }
}
