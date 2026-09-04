// Apple Music's word-timed lyric format.
//
// Ported from BitChord (https://github.com/kushagrasinghx/BitChord), GPL-3.0.
//
// A document is one `<p>` per sung line, each holding one `<span>` per
// syllable with its own begin/end:
//
// ```xml
// <p begin="27.395" end="28.960" ttm:agent="v1">
//   <span begin="27.395" end="27.549">I</span>
//   <span begin="27.549" end="27.740">been</span>
// </p>
// ```
//
// Syllables of one word are written as adjacent spans with no whitespace
// between them ("e" + "nough"), so whitespace — not the span boundary — is
// what separates words. That is the whole trick to reading this format.

import 'package:xml/xml.dart';

import '../../data/lyric_line.dart';
import 'lyric_gaps.dart';

/// Roles that are not this line at all: translations and romanisations are
/// alternate renderings of the same words and would double the line up.
const Set<String> _skippedRoles = {'x-translation', 'x-roman'};

/// The answering vocal. It is this line, sung by a second voice over the lead
/// and often past the *next* line's stamp, so it is collected apart and
/// carried as [LyricLine.background].
const String _backgroundRole = 'x-bg';

/// Parses Apple TTML. Empty for anything unparseable — every caller treats an
/// empty result as a miss and falls through to the next source.
List<LyricLine> parseTtml(String ttml) {
  try {
    // Lyrics arrive from a third-party host. XmlDocument resolves no external
    // entities and fetches nothing, so a hostile document can waste our time
    // but cannot make us go anywhere.
    final document = XmlDocument.parse(ttml);
    final lines = <LyricLine>[];
    for (final paragraph in document.findAllElements('p')) {
      final line = _lineFrom(paragraph);
      if (line != null) lines.add(line);
    }
    lines.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return withInstrumentalGaps(lines);
  } on Object {
    return const <LyricLine>[];
  }
}

LyricLine? _lineFrom(XmlElement paragraph) {
  final pieces = <_Piece>[];
  final backingPieces = <_Piece>[];
  _collect(paragraph, pieces, backingPieces);

  final words = _mergeIntoWords(pieces);
  final backingWords = _mergeIntoWords(backingPieces);
  final backing = backingWords.isEmpty
      ? null
      : LyricLine(
          backingWords.first.startMs,
          backingWords.map((w) => w.text).join(' '),
          words: backingWords,
        );

  if (words.isEmpty) {
    // Line-synced TTML: a <p> with a stamp and bare text, no spans. The text
    // is the whole paragraph, backing vocal included, so there is nothing here
    // to hang underneath — the bracket in the text is all the separation the
    // document gave.
    final text = paragraph.innerText.trim();
    final begin = ttmlTime(paragraph.getAttribute('begin'));
    if (begin == null || text.isEmpty) return null;
    // The paragraph's own end is the only thing that says when the singing
    // stops, so carry it — a break can't be found without it.
    final end = ttmlTime(paragraph.getAttribute('end'));
    return LyricLine(
      begin,
      text,
      sungUntilMs: end != null && end > begin ? end : null,
    );
  }

  // Prefer the paragraph's own stamp: Apple sets it a hair before the first
  // syllable on lines that open with a soft consonant, and that lead-in is
  // when the line should appear.
  final begin =
      ttmlTime(paragraph.getAttribute('begin')) ?? words.first.startMs;
  return LyricLine(
    begin < words.first.startMs ? begin : words.first.startMs,
    words.map((w) => w.text).join(' '),
    words: words,
    background: backing,
  );
}

/// Flattens a paragraph into timed spans and the whitespace between them.
///
/// Nested spans (Apple wraps background vocals, and occasionally whole
/// phrases, in an outer timed span) recurse to their leaves, so only the
/// innermost timings — the ones actually per-syllable — survive.
///
/// Spans marked [_backgroundRole] and everything under them go to [backing]
/// instead of [out], which is what keeps the two voices apart.
void _collect(XmlNode node, List<_Piece> out, List<_Piece> backing) {
  for (final child in node.children) {
    if (child is XmlElement) {
      final role = child.getAttribute('ttm:role') ?? '';
      if (_skippedRoles.contains(role)) continue;
      // Inside a backing span every leaf is backing, so the sink switches for
      // the whole of that subtree — whether the span holds its own syllables
      // or is a single timed leaf.
      final sink = role == _backgroundRole ? backing : out;
      final begin = ttmlTime(child.getAttribute('begin'));
      final end = ttmlTime(child.getAttribute('end'));
      if (begin != null && end != null && !_hasTimedChild(child)) {
        sink.add(_Piece(child.innerText, begin, end));
      } else {
        _collect(child, sink, backing);
      }
    } else if (child is XmlText) {
      if (child.value.isNotEmpty) out.add(_Piece(child.value, null, null));
    }
  }
}

bool _hasTimedChild(XmlElement element) {
  for (final child in element.children.whereType<XmlElement>()) {
    if ((child.getAttribute('begin') ?? '').isNotEmpty) return true;
    if (_hasTimedChild(child)) return true;
  }
  return false;
}

/// Glues syllables back into words. A word ends at the first whitespace after
/// it — whether that whitespace is a text node between two spans or part of a
/// span's own text — and its span runs from the first syllable's start to the
/// last one's end.
List<LyricWord> _mergeIntoWords(List<_Piece> pieces) {
  final words = <LyricWord>[];
  final current = StringBuffer();
  var start = 0;
  var end = 0;
  // Untimed text is punctuation hanging off a span, or a line that was never
  // word-timed at all. Either way it can't carry a word of its own — a word
  // needs a span to get its timing from.
  var timed = false;

  void flush() {
    final text = current.toString().trim();
    current.clear();
    if (text.isNotEmpty && timed) words.add(LyricWord(start, end, text));
    timed = false;
  }

  for (final piece in pieces) {
    if (piece.start == null || piece.end == null) {
      if (piece.text.trim().isEmpty) {
        flush();
      } else if (timed) {
        // Trailing punctuation belongs to the word it follows; anything before
        // the first span has no timing to join.
        current.write(piece.text);
      }
      continue;
    }
    if (piece.text.trim().isEmpty) continue;
    // Leading whitespace closes off whatever came before it.
    if (_startsWithSpace(piece.text)) flush();
    if (current.isEmpty) start = piece.start!;
    current.write(piece.text.trim());
    end = piece.end!;
    timed = true;
    if (_endsWithSpace(piece.text)) flush();
  }
  flush();
  return words;
}

bool _startsWithSpace(String s) => s.isNotEmpty && s[0].trim().isEmpty;
bool _endsWithSpace(String s) => s.isNotEmpty && s[s.length - 1].trim().isEmpty;

/// TTML clock values: `27.395`, `1:05.20`, `1:02:03.4`, or a plain number with
/// an `s`/`ms` unit. Returned in milliseconds.
int? ttmlTime(String? value) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty) return null;
  if (raw.endsWith('ms')) {
    return double.tryParse(raw.substring(0, raw.length - 2))?.round();
  }
  final stripped = raw.endsWith('s') ? raw.substring(0, raw.length - 1) : raw;
  final parts = stripped.split(':');
  final numbers = <double>[];
  for (final part in parts) {
    final n = double.tryParse(part);
    if (n == null) return null;
    numbers.add(n);
  }
  final seconds = switch (numbers.length) {
    1 => numbers[0],
    2 => numbers[0] * 60 + numbers[1],
    3 => numbers[0] * 3600 + numbers[1] * 60 + numbers[2],
    _ => null,
  };
  return seconds == null ? null : (seconds * 1000).round();
}

/// A span with timings, or the bare text between two of them.
class _Piece {
  const _Piece(this.text, this.start, this.end);
  final String text;
  final int? start;
  final int? end;
}
