// One line of text that scrolls when it does not fit.
//
// The player's title is one line at a large size, so a long Bollywood title
// ("Tujhe Kitna Chahne Lage (From "Kabir Singh")") would otherwise end in an
// ellipsis at the most informative part. Only an overflowing title animates;
// one that fits is plain Text with no controller running.
//
// How it moves: it holds at the start long enough to read the beginning, then
// scrolls left at a steady reading pace into a second copy of the title that
// follows a gap behind the first, and lands exactly where it started — so the
// loop has no jump back. The edges fade out over a few pixels rather than
// cutting letters in half; the left fade only appears while the text is
// moving, so the title's first letter is never dimmed at rest.
//
// The first version clipped the text to the visible width and then moved the
// clipped box, so the end of the title never appeared — the tail scrolled in
// as empty space and snapped back. The clip now sits outside the movement.
//
// PERF: the text is measured once per (text, style, width), not on every
// build. The scroll is one Transform under a RepaintBoundary; the edge fade
// is a ShaderMask on a single line, only while the title overflows.

import 'package:flutter/material.dart';

/// Pixels per second while scrolling — slow enough to read along.
const double _kSpeed = 32;

/// Space between the end of the title and the start of its repeat.
const double _kGap = 48;

/// Pause at the start of every pass.
const Duration _kHold = Duration(milliseconds: 1800);

/// Width of the soft edge on either side.
const double _kFade = 14;

class MarqueeText extends StatelessWidget {
  const MarqueeText(this.text, {super.key, required this.style});
  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => _Marquee(
        // A new key per text restarts from the beginning on a track change
        // instead of continuing mid-scroll.
        key: ValueKey(text),
        text: text,
        style: style,
        width: box.maxWidth,
        scale: MediaQuery.textScalerOf(context),
      ),
    );
  }
}

class _Marquee extends StatefulWidget {
  const _Marquee({
    super.key,
    required this.text,
    required this.style,
    required this.width,
    required this.scale,
  });
  final String text;
  final TextStyle style;
  final double width;
  final TextScaler scale;

  @override
  State<_Marquee> createState() => _MarqueeState();
}

class _MarqueeState extends State<_Marquee>
    with SingleTickerProviderStateMixin {
  AnimationController? _c;

  /// Distance of one full pass: the title plus the gap. Zero when it fits.
  double _travel = 0;

  /// Share of each cycle spent holding at the start.
  double _holdShare = 0;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  @override
  void didUpdateWidget(_Marquee old) {
    super.didUpdateWidget(old);
    if (old.width != widget.width ||
        old.style != widget.style ||
        old.scale != widget.scale) {
      _measure();
    }
  }

  void _measure() {
    final tp = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      textScaler: widget.scale,
    )..layout();
    final textWidth = tp.width;
    tp.dispose();

    if (textWidth <= widget.width) {
      _travel = 0;
      _c?.stop();
      return;
    }
    _travel = textWidth + _kGap;
    final scrollMs = (_travel / _kSpeed * 1000).round();
    final total = _kHold.inMilliseconds + scrollMs;
    _holdShare = _kHold.inMilliseconds / total;
    _c ??= AnimationController(vsync: this);
    _c!
      ..duration = Duration(milliseconds: total)
      ..repeat();
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  /// How far the text has moved, 0 at rest at the start of each pass.
  double _offset(double t) {
    if (t <= _holdShare) return 0;
    final p = (t - _holdShare) / (1 - _holdShare);
    // Eased in and out so it starts and stops softly; [_kSpeed] sets the
    // average pace.
    return Curves.easeInOutSine.transform(p) * _travel;
  }

  @override
  Widget build(BuildContext context) {
    final text = Text(
      widget.text,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.visible,
      style: widget.style,
    );
    final c = _c;
    if (_travel <= 0 || c == null) {
      return Text(
        widget.text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: widget.style,
      );
    }
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: c,
        builder: (_, child) {
          final x = _offset(c.value);
          return ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) => _edges(rect, moving: x > 0),
            // The clip is the visible line; the movement happens inside it,
            // so the whole title — and its repeat — passes through.
            child: ClipRect(
              child: UnconstrainedBox(
                alignment: Alignment.centerLeft,
                constrainedAxis: Axis.vertical,
                clipBehavior: Clip.hardEdge,
                child: Transform.translate(offset: Offset(-x, 0), child: child),
              ),
            ),
          );
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            text,
            const SizedBox(width: _kGap),
            text,
          ],
        ),
      ),
    );
  }

  /// Opaque in the middle, fading to nothing over [_kFade] at the right
  /// edge — and at the left edge too while the title is moving.
  Shader _edges(Rect rect, {required bool moving}) {
    final w = rect.width;
    final f = (_kFade / w).clamp(0.0, 0.5);
    return LinearGradient(
      colors: [
        moving ? const Color(0x00000000) : const Color(0xFF000000),
        const Color(0xFF000000),
        const Color(0xFF000000),
        const Color(0x00000000),
      ],
      stops: [0, f, 1 - f, 1],
    ).createShader(rect);
  }
}
