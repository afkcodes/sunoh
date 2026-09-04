// Instrumental breaks, marked the way an LRC file marks them: a blank line.
//
// Ported from BitChord (https://github.com/kushagrasinghx/BitChord), GPL-3.0.

import '../../data/lyric_line.dart';

/// Shorter instrumental breaks aren't worth interrupting the line for.
const int kMinGapMs = 4000;

/// Marks the instrumental stretches with blank lines.
///
/// A break is only drawn where the line before it says when its singing
/// stopped — see [LyricLine.hasKnownEnd]. Given that, the note appears the
/// moment the vocal ends rather than several seconds later once the next line
/// was due, which is the whole advantage over a stamp-to-stamp guess. Without
/// it there is nothing to measure silence against: the distance to the next
/// stamp is the line's own slot, and treating that as a break puts a note
/// after every single line of a line-synced source.
List<LyricLine> withInstrumentalGaps(List<LyricLine> lines) {
  if (lines.isEmpty) return lines;
  final out = <LyricLine>[];
  // Nothing stands for the intro, so give the run-up its own break.
  if (lines.first.timeMs >= kMinGapMs) out.add(const LyricLine(0, ''));

  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    out.add(line);
    if (index + 1 >= lines.length) continue;
    if (!line.hasKnownEnd) continue;

    final silence = lines[index + 1].timeMs - line.endMs;
    // A marker sharing its line's stamp could never be reached: the cursor
    // takes the last line whose stamp has passed, so the note would sit on top
    // of the line it belongs to and the words would never light up.
    if (silence >= kMinGapMs && line.endMs > line.timeMs) {
      out.add(LyricLine(line.endMs, ''));
    }
  }
  return out;
}
