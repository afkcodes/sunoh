// The lyric parsers, which are pure functions over text and the only part of
// the multi-source lookup that can be tested without a network.
//
// What is worth pinning down here is the awkward half of each format: where a
// *word* ends when the format only writes syllables, and where the answering
// vocal ends when the format only writes a bracket. Both are what the sweep
// rides on, and both are wrong in obvious, visible ways when they break.

import 'package:flutter_test/flutter_test.dart';
import 'package:sunoh/api/lyrics/background_vocals.dart';
import 'package:sunoh/api/lyrics/enhanced_lrc.dart';
import 'package:sunoh/api/lyrics/lrc_parser.dart';
import 'package:sunoh/api/lyrics/lyric_gaps.dart';
import 'package:sunoh/api/lyrics/ttml_lyrics.dart';
import 'package:sunoh/data/lyric_line.dart';

/// The parsers mark instrumental stretches with blank lines, so the sung lines
/// are the ones worth asserting on.
List<LyricLine> sung(List<LyricLine> lines) =>
    lines.where((l) => !l.isGap).toList();

String ttmlDoc(String body) =>
    '<tt xmlns="http://www.w3.org/ns/ttml" '
    'xmlns:ttm="http://www.w3.org/ns/ttml#metadata">'
    '<body><div>$body</div></body></tt>';

void main() {
  group('TTML', () {
    test('adjacent spans with no space between them are one word', () {
      // "e" + "nough" is how Apple writes a two-syllable word. Split on the
      // span boundary it renders "e nough" and the sweep stutters across it.
      final lines = sung(
        parseTtml(
          ttmlDoc(
            '<p begin="27.395" end="28.960">'
            '<span begin="27.395" end="27.549">I </span>'
            '<span begin="27.549" end="27.740">been </span>'
            '<span begin="27.740" end="28.000">e</span>'
            '<span begin="28.000" end="28.300">nough</span>'
            '</p>',
          ),
        ),
      );

      expect(lines, hasLength(1));
      expect(lines.single.text, 'I been enough');
      expect(lines.single.words.map((w) => w.text), ['I', 'been', 'enough']);
      // The merged word runs from the first syllable's start to the last
      // one's end, not from either one alone.
      expect(lines.single.words.last.startMs, 27740);
      expect(lines.single.words.last.endMs, 28300);
    });

    test('the paragraph stamp wins when it precedes the first syllable', () {
      final lines = sung(
        parseTtml(
          ttmlDoc(
            '<p begin="10.000" end="11.000">'
            '<span begin="10.200" end="11.000">Late</span></p>',
          ),
        ),
      );
      expect(lines.single.timeMs, 10000);
    });

    test('a background span becomes its own line, not part of the lead', () {
      final lines = sung(
        parseTtml(
          ttmlDoc(
            '<p begin="10.0" end="12.0">'
            '<span begin="10.0" end="10.5">Hey </span>'
            '<span ttm:role="x-bg" begin="10.6" end="11.0">'
            '<span begin="10.6" end="11.0">(ooh) </span></span>'
            '</p>',
          ),
        ),
      );

      final line = lines.single;
      expect(line.text, 'Hey');
      expect(line.background, isNotNull);
      expect(line.background!.text, '(ooh)');
      expect(line.background!.timeMs, 10600);
      // The line is still being sung while the backing voice holds the note,
      // which is what stops a gap being found in the middle of it.
      expect(line.endMs, 11000);
    });

    test('translations and romanisations are dropped, not doubled up', () {
      final lines = sung(
        parseTtml(
          ttmlDoc(
            '<p begin="1.0" end="2.0">'
            '<span begin="1.0" end="2.0">Hola</span>'
            '<span ttm:role="x-translation" begin="1.0" end="2.0">Hello</span>'
            '</p>',
          ),
        ),
      );
      expect(lines.single.text, 'Hola');
    });

    test('a line-synced paragraph keeps its stated end', () {
      final lines = sung(
        parseTtml(ttmlDoc('<p begin="5.0" end="9.0">No spans here</p>')),
      );
      expect(lines.single.text, 'No spans here');
      expect(lines.single.isWordSynced, isFalse);
      expect(lines.single.hasKnownEnd, isTrue);
      expect(lines.single.sungUntilMs, 9000);
    });

    test('clock values in every shape TTML allows', () {
      expect(ttmlTime('27.395'), 27395);
      expect(ttmlTime('1:05.20'), 65200);
      expect(ttmlTime('1:02:03.4'), 3723400);
      expect(ttmlTime('900ms'), 900);
      expect(ttmlTime('12s'), 12000);
      expect(ttmlTime(''), isNull);
      expect(ttmlTime(null), isNull);
    });

    test('malformed XML is a miss, not a crash', () {
      expect(parseTtml('<p begin="1.0">unclosed'), isEmpty);
      expect(parseTtml(''), isEmpty);
    });
  });

  group('enhanced LRC', () {
    test('each word runs until the next one starts', () {
      final lines = sung(
        parseEnhancedLrc(
          '[00:27.39]<00:27.39>I <00:27.54>been <00:27.74>tryna\n'
          '[00:30.00]<00:30.00>Next',
        ),
      );

      expect(lines, hasLength(2));
      final first = lines.first;
      expect(first.text, 'I been tryna');
      expect(first.words[0].startMs, 27390);
      expect(first.words[0].endMs, 27540);
      expect(first.words[1].endMs, 27740);
      // The last word of a line runs until the next line begins — nothing else
      // states when it stops.
      expect(first.words[2].endMs, 30000);
    });

    test('the closing word gets a beat rather than a zero-length sweep', () {
      final lines = sung(parseEnhancedLrc('[00:10.00]<00:10.00>End'));
      expect(lines.single.words.single.endMs, greaterThan(10000));
    });

    test('HTML entities are decoded, not sung literally', () {
      final lines = sung(
        parseEnhancedLrc('[00:01.00]<00:01.00>don&#x27;t <00:02.00>stop'),
      );
      expect(lines.single.text, "don't stop");
    });

    test('&amp; decodes once, not twice', () {
      expect(decodeEntities('&amp;#x27;'), '&#x27;');
    });

    test('a file with no word stamps is left for the plain parser', () {
      expect(parseEnhancedLrc('[00:01.00]just a line'), isEmpty);
    });
  });

  group('LRC', () {
    test('timestamps keep their sub-second precision', () {
      final lines = sung(parseLrc('[00:12.34]Hello\n[01:02]World'));
      expect(lines.map((l) => l.timeMs), [12340, 62000]);
    });

    test('word runs of an A2 line are read as words', () {
      final lines = sung(
        parseLrc('[00:01.00]<00:01.00>one <00:02.00>two<00:03.00>'),
      );
      expect(lines.single.isWordSynced, isTrue);
      expect(lines.single.words.map((w) => w.text), ['one', 'two']);
      // The trailing bare stamp names no word; it exists only to end the last
      // one.
      expect(lines.single.words.last.endMs, 3000);
      // The text keeps the file's own spacing rather than being rebuilt from
      // the words.
      expect(lines.single.text, 'one two');
    });

    test('a plain line stays line-synced', () {
      final lines = sung(parseLrc('[00:01.00]nothing timed here'));
      expect(lines.single.isWordSynced, isFalse);
    });

    test('a short blank is a verse break, a long one is instrumental', () {
      final short = parseLrc('[00:00.00]A\n[00:01.00]\n[00:02.00]B');
      expect(short.where((l) => l.isGap), isEmpty);

      final long = parseLrc('[00:00.00]A\n[00:01.00]\n[00:10.00]B');
      expect(long.where((l) => l.isGap), hasLength(1));
    });

    test('a late first line gets an intro break', () {
      final lines = parseLrc('[00:30.00]First words');
      expect(lines.first.isGap, isTrue);
      expect(lines.first.timeMs, 0);
    });

    test('plain text is spread across the duration in milliseconds', () {
      final lines = plainLyricsAsLines('one\ntwo', totalSec: 10);
      expect(lines.first.timeMs, 0);
      expect(lines.last.timeMs, 5000);
    });
  });

  group('background vocals', () {
    test('a trailing bracket is split off a line-synced line', () {
      final split = withBackgroundVocals([
        const LyricLine(0, "I'm patient (Foolishly patient)", sungUntilMs: 900),
      ]);
      expect(split.single.text, "I'm patient");
      expect(split.single.background!.text, '(Foolishly patient)');
      // Both halves are the same line, so both keep its end.
      expect(split.single.background!.sungUntilMs, 900);
    });

    test('a word-synced line hands its bracket the matching words', () {
      final split = withBackgroundVocals([
        const LyricLine(
          0,
          'Hey (ooh)',
          words: [LyricWord(0, 100, 'Hey'), LyricWord(200, 400, '(ooh)')],
        ),
      ]);
      expect(split.single.text, 'Hey');
      expect(split.single.words.map((w) => w.text), ['Hey']);
      expect(split.single.background!.words.map((w) => w.text), ['(ooh)']);
      expect(split.single.background!.timeMs, 200);
    });

    test('a line that is entirely a bracket has no lead to hang under', () {
      final split = withBackgroundVocals([const LyricLine(0, '(ooh ooh)')]);
      expect(split.single.text, '(ooh ooh)');
      expect(split.single.background, isNull);
    });

    test('a bracket opening mid-word is not a word boundary', () {
      final split = withBackgroundVocals([
        const LyricLine(
          0,
          'wait(ing)',
          words: [LyricWord(0, 100, 'wait(ing)')],
        ),
      ]);
      expect(split.single.background, isNull);
    });

    test('a source that marked its own backing vocal is left alone', () {
      const marked = LyricLine(
        0,
        'Hey (ooh)',
        background: LyricLine(50, '(already split)'),
      );
      expect(
        withBackgroundVocals([marked]).single.background!.text,
        '(already split)',
      );
    });
  });

  group('instrumental gaps', () {
    test('a break is only drawn where the line before it stated an end', () {
      // Line-synced with no end: the ten seconds to the next stamp is this
      // line's own slot, not silence.
      final unknown = withInstrumentalGaps(const [
        LyricLine(0, 'sung slowly'),
        LyricLine(10000, 'next'),
      ]);
      expect(unknown.where((l) => l.isGap), isEmpty);

      final known = withInstrumentalGaps(const [
        LyricLine(0, 'sung quickly', sungUntilMs: 1000),
        LyricLine(10000, 'next'),
      ]);
      expect(known.where((l) => l.isGap), hasLength(1));
      // It appears when the vocal stops, not when the next line was due.
      expect(known.firstWhere((l) => l.isGap).timeMs, 1000);
    });

    test('a gap never shares a stamp with the line it follows', () {
      // A marker on the same stamp could never be reached — the cursor takes
      // the last line whose stamp has passed.
      final lines = withInstrumentalGaps(const [
        LyricLine(5000, 'x', sungUntilMs: 5000),
        LyricLine(20000, 'y'),
      ]);
      expect(lines.where((l) => l.isGap && l.timeMs == 5000), isEmpty);
    });
  });

  group('word progress', () {
    // The sweep used to place its edge with a caret at a character index,
    // which holds for Latin and breaks for any script built from grapheme
    // clusters — a Devanagari consonant plus its matras is several characters
    // rendering as one glyph, and a caret from inside one comes back
    // somewhere arbitrary. Timing is now answered in words, and the painter
    // measures where those words actually are.
    const hindi = LyricLine(
      0,
      'हर पल तुझे',
      words: [
        LyricWord(0, 500, 'हर'),
        LyricWord(500, 1000, 'पल'),
        LyricWord(1000, 1500, 'तुझे'),
      ],
    );

    test('names the word being sung, whatever it is made of', () {
      expect(hindi.wordProgress(250)?.$1, 0);
      expect(hindi.wordProgress(750)?.$1, 1);
      expect(hindi.wordProgress(1250)?.$1, 2);
    });

    test('reports how far through that word, not through the string', () {
      // Half way through the second word, regardless of how many code units
      // any of these words happen to occupy.
      final (index, through) = hindi.wordProgress(750)!;
      expect(index, 1);
      expect(through, closeTo(0.5, 0.001));
    });

    test('is null once the line is finished', () {
      expect(hindi.wordProgress(1500), isNull);
      expect(hindi.wordProgress(9000), isNull);
    });

    test('a word not yet started reports no progress into it', () {
      const gap = LyricLine(
        0,
        'a b',
        words: [LyricWord(0, 100, 'a'), LyricWord(900, 1000, 'b')],
      );
      // Between the two words: the second is next, and untouched.
      expect(gap.wordProgress(500), (1, 0.0));
    });
  });

  group('reveal', () {
    test('the sweep interpolates across the word being sung', () {
      const line = LyricLine(
        0,
        'ab cd',
        words: [LyricWord(0, 1000, 'ab'), LyricWord(1000, 2000, 'cd')],
      );
      expect(line.revealedChars(0), 0);
      expect(line.revealedChars(500), 1.0);
      expect(line.revealedChars(1500), 4.0);
      expect(line.revealedChars(9000), 5.0);
    });

    test('a line-synced line reveals whole or not at all', () {
      const line = LyricLine(1000, 'whole line');
      expect(line.revealedChars(999), 0);
      expect(line.revealedChars(1000), 10);
    });

    test('a word repeated in the line lines up with its own occurrence', () {
      const line = LyricLine(
        0,
        'go go go',
        words: [
          LyricWord(0, 100, 'go'),
          LyricWord(100, 200, 'go'),
          LyricWord(200, 300, 'go'),
        ],
      );
      // Mid-way through the third "go" is character 6 + half of 2.
      expect(line.revealedChars(250), 7.0);
    });
  });
}
