// One lyric line with the singing swept across it, word by word.
//
// Two copies of the same text: a dim one always drawn, and a bright one
// clipped to how much of the line has been sung. The clip is measured off the
// text's own layout, so it lands on the right character of the right visual
// row when a long line wraps.
//
// Only the *playing* line is drawn this way. Lines above and below are plain
// [Text] — they are fully sung or not yet started, which is a colour, not an
// animation. That matters: this repaints every frame for as long as the line
// is current, and one such widget on screen is the budget.

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/lyric_line.dart';

/// How wide the wet edge of the fill is.
///
/// Wide enough to read as liquid rather than a cursor, narrow enough that
/// the word being sung is still clearly the word being sung. Roughly a
/// character and a half at the size the playing line is drawn at.
const double _kFeather = 34;

/// How visible an unsung word is, against the sung ones beside it.
const double _kUnsungAlpha = 0.42;

class SweptLyricLine extends StatelessWidget {
  const SweptLyricLine({
    super.key,
    required this.line,
    required this.clock,
    this.textAlign = TextAlign.start,
  });

  final LyricLine line;

  /// Playback position in milliseconds. The painter listens to this directly,
  /// so a frame costs a repaint of this line and nothing else — no rebuild of
  /// the list, and no rebuild of this widget either.
  final ValueListenable<int> clock;

  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    // Taken from the surrounding [DefaultTextStyle] rather than passed in, so
    // this sits *inside* the same animated style every other line uses. That
    // is what makes taking over smooth: the wrapper survives the swap from
    // plain text to this, and goes on animating its size through it, where
    // before the line arrived already at full size and the step showed.
    final style = DefaultTextStyle.of(context).style;
    final bright = style.color ?? const Color(0xFFFFFFFF);

    final backing = line.background;
    final sweep = RepaintBoundary(
      child: CustomPaint(
        painter: _SweepPainter(
          line: line,
          clock: clock,
          style: style,
          dim: bright.withValues(alpha: bright.a * _kUnsungAlpha),
          bright: bright,
          textAlign: textAlign,
          textDirection: Directionality.of(context),
        ),
        // Sized by the same layout the painter uses, so the two can never
        // disagree about where the text sits.
        child: _SweepSize(text: line.text, style: style, textAlign: textAlign),
      ),
    );
    if (backing == null) return sweep;

    // The answering vocal, hung under the lead the way Apple Music does it:
    // smaller and a shade behind, still large enough to read as words of the
    // song rather than a caption.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        sweep,
        const SizedBox(height: 4),
        DefaultTextStyle.merge(
          style: TextStyle(
            fontSize: (style.fontSize ?? 22) * 0.72,
            color: bright.withValues(alpha: bright.a * 0.85),
          ),
          child: SweptLyricLine(
            line: backing,
            clock: clock,
            textAlign: textAlign,
          ),
        ),
      ],
    );
  }
}

/// Reserves exactly the space the line's text needs, without painting it.
class _SweepSize extends StatelessWidget {
  const _SweepSize({
    required this.text,
    required this.style,
    required this.textAlign,
  });

  final String text;
  final TextStyle style;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: style.copyWith(color: const Color(0x00000000)),
    textAlign: textAlign,
  );
}

class _SweepPainter extends CustomPainter {
  _SweepPainter({
    required this.line,
    required this.clock,
    required this.style,
    required this.dim,
    required this.bright,
    required this.textAlign,
    required this.textDirection,
  }) : super(repaint: clock);

  final LyricLine line;
  final ValueListenable<int> clock;
  final TextStyle style;
  final Color dim;
  final Color bright;
  final TextAlign textAlign;
  final TextDirection textDirection;

  /// Laid out once per width and reused for every frame of the line. Laying
  /// text out is the expensive half of drawing it; the sweep only changes
  /// where it is cut.
  TextPainter? _dimPainter;
  TextPainter? _brightPainter;
  double _laidOutFor = -1;

  /// Where each word actually sits, in pixels, once the line is laid out.
  ///
  /// Measured rather than counted. The edge used to be placed with
  /// `getOffsetForCaret` at a character index, which holds for Latin and
  /// falls apart for anything built from grapheme clusters: a Devanagari
  /// consonant and its matras are several characters rendering as one glyph,
  /// and a caret asked for from inside that cluster comes back somewhere
  /// arbitrary. The edge then jumped between nothing and the whole line
  /// frame to frame, which is what the flicker was.
  ///
  /// Word boundaries are the one place every script agrees, so those are the
  /// only offsets asked about, and everything between them is interpolated
  /// across the word's own box.
  List<Rect> _wordBoxes = const [];

  void _layout(double width) {
    if (_laidOutFor == width && _dimPainter != null) return;
    _dimPainter = _paintFor(dim)..layout(maxWidth: width);
    _brightPainter = _paintFor(bright)..layout(maxWidth: width);
    _wordBoxes = _measureWords(_brightPainter!);
    _laidOutFor = width;
  }

  List<Rect> _measureWords(TextPainter painter) {
    final boxes = <Rect>[];
    var offset = 0;
    for (final word in line.words) {
      // Walked forward rather than searched from the start, so a word
      // repeated in the line matches its own occurrence.
      final found = line.text.indexOf(word.text, offset);
      final start = found >= 0 ? found : offset;
      final end = start + word.text.length;
      offset = end;

      final selection = painter.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: end),
      );
      if (selection.isEmpty) {
        // Nothing measurable — carry the previous word's edge so the sweep
        // holds still over it rather than jumping to zero.
        boxes.add(boxes.isEmpty ? Rect.zero : boxes.last);
        continue;
      }
      // A word that wraps returns a box per row; its span is the first row's
      // left to the last row's right, and the row it belongs to is the first.
      final first = selection.first.toRect();
      final last = selection.last.toRect();
      boxes.add(Rect.fromLTRB(first.left, first.top, last.right, first.bottom));
    }
    return boxes;
  }

  TextPainter _paintFor(Color color) => TextPainter(
    text: TextSpan(
      text: line.text,
      style: style.copyWith(color: color),
    ),
    textAlign: textAlign,
    textDirection: textDirection,
  );

  @override
  void paint(Canvas canvas, Size size) {
    _layout(size.width);
    final dimPainter = _dimPainter!;
    final brightPainter = _brightPainter!;
    dimPainter.paint(canvas, Offset.zero);

    final position = clock.value;
    // Sung and done with: all of it is lit, with no layer and no mask. Checked
    // first because the lines either side of the playing one sit in this state
    // for minutes at a time.
    if (position >= line.endMs) {
      brightPainter.paint(canvas, Offset.zero);
      return;
    }
    if (position <= line.timeMs) return;

    final edge = _edge(position);
    if (edge == null) return;

    // One layer for the whole line: the bright copy goes down in full, then
    // the parts that haven't been sung are erased out of it. Masking beats
    // clipping here because a clip has a hard edge, and a hard edge is what
    // makes a sweep look like a wipe instead of a fill.
    final bounds = Offset.zero & size;
    canvas.saveLayer(bounds, Paint());
    brightPainter.paint(canvas, Offset.zero);
    _eraseUnsung(canvas, brightPainter, edge, size);
    canvas.restore();
  }

  /// Where the sweep has got to, in pixels: how far across, and the top of the
  /// row it is on. Null before the line has started.
  Offset? _edge(int positionMs) {
    final progress = line.wordProgress(positionMs);
    if (progress == null || _wordBoxes.isEmpty) return null;
    final (index, through) = progress;
    if (index >= _wordBoxes.length) return null;

    final box = _wordBoxes[index];
    // Interpolated across the word's own measured span, so the edge creeps
    // through it at the speed it is being sung whatever the script.
    return Offset(box.left + through * box.width, box.top);
  }

  /// Cuts the unsung remainder back out of the bright copy.
  ///
  /// Rows already sung are left alone, rows not yet reached are erased whole,
  /// and the row being sung is erased through a gradient — so the boundary is
  /// a soft edge that runs ahead of the voice and fills in behind it rather
  /// than a line stepping from letter to letter.
  void _eraseUnsung(
    Canvas canvas,
    TextPainter painter,
    Offset edge,
    Size size,
  ) {
    final dx = edge.dx;

    // `dstIn` keeps the destination in proportion to the *source's alpha*, so
    // what is drawn here erases rather than paints. Which makes the paint's
    // own colour load-bearing in a way it usually isn't: a Paint defaults to
    // opaque black, and opaque anything under dstIn means "keep all of this"
    // — the exact opposite of erasing. Hence the explicit alphas below.
    final erase = Paint()..blendMode = BlendMode.dstIn;
    var top = 0.0;
    for (final metric in painter.computeLineMetrics()) {
      final bottom = top + metric.height;
      final row = Rect.fromLTRB(0, top, size.width, bottom);

      // The edge's dy is the top of the row it is on: a row whose bottom it
      // has passed has been sung in full and keeps every pixel.
      if (edge.dy >= bottom - 0.5) {
        top = bottom;
        continue;
      }
      if (edge.dy < top - 0.5) {
        // Not reached yet — erase the row outright. A fully transparent
        // source clears everything under it.
        //
        // This is where a wrapped line went wrong: leaving the default opaque
        // colour here kept the row instead of clearing it, so the second row
        // of a two-row line was painted bright before a word of it had been
        // sung — and then appeared to "restart" in grey once the sweep
        // actually reached it.
        canvas.drawRect(
          row,
          erase
            ..shader = null
            ..color = const Color(0x00000000),
        );
        top = bottom;
        continue;
      }
      // Opaque, because the paint's alpha still modulates a shader's output —
      // a leftover transparent colour here would erase the whole row.
      canvas.drawRect(
        row,
        erase
          ..color = const Color(0xFFFFFFFF)
          ..shader = _edgeShader(row, dx),
      );
      top = bottom;
    }
  }

  /// Opaque behind the voice, clear ahead of it, and a soft ramp between the
  /// two. Alpha only — this is a mask, so it changes what shows through rather
  /// than what colour it is.
  Shader _edgeShader(Rect row, double dx) {
    final start = (dx - _kFeather).clamp(0.0, row.width);
    final end = dx.clamp(start + 0.01, row.width == 0 ? 0.01 : row.width);
    return ui.Gradient.linear(
      Offset(start, row.top),
      Offset(end, row.top),
      const [Color(0xFFFFFFFF), Color(0x00FFFFFF)],
    );
  }

  @override
  bool shouldRepaint(_SweepPainter old) =>
      old.line != line ||
      old.style != style ||
      old.dim != dim ||
      old.bright != bright;
}
