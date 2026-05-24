// Draggable progress scrubber. Ported from player.jsx Scrubber.

import 'package:flutter/material.dart';

class Scrubber extends StatefulWidget {
  const Scrubber({
    super.key,
    required this.value,
    required this.max,
    required this.accent,
    required this.fg,
    this.onChanged,
    this.compact = false,
  });

  final int value;
  final int max;
  final Color accent;
  final Color fg;
  final ValueChanged<int>? onChanged;
  final bool compact;

  @override
  State<Scrubber> createState() => _ScrubberState();
}

class _ScrubberState extends State<Scrubber> {
  bool _dragging = false;

  void _emit(double localX, double width) {
    if (widget.onChanged == null) return;
    final pct = (localX / width).clamp(0.0, 1.0);
    widget.onChanged!((pct * widget.max).round());
  }

  @override
  Widget build(BuildContext context) {
    final pct = widget.max == 0 ? 0.0 : (widget.value / widget.max).clamp(0.0, 1.0);
    final trackH = widget.compact ? 2.0 : (_dragging ? 6.0 : 4.0);
    final interactive = widget.onChanged != null;

    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final bar = SizedBox(
        height: widget.compact ? 2 : 26,
        child: Stack(
          alignment: Alignment.centerLeft,
          clipBehavior: Clip.none,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: trackH,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            FractionallySizedBox(
              widthFactor: pct,
              child: Container(
                height: trackH,
                decoration: BoxDecoration(
                  color: widget.compact ? widget.accent : widget.fg,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            if (!widget.compact)
              Positioned(
                left: (pct * w) - 6,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 4, offset: const Offset(0, 1)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );

      if (!interactive) return bar;

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (d) {
          setState(() => _dragging = true);
          _emit(d.localPosition.dx, w);
        },
        onHorizontalDragUpdate: (d) => _emit(d.localPosition.dx, w),
        onHorizontalDragEnd: (_) => setState(() => _dragging = false),
        onTapDown: (d) => _emit(d.localPosition.dx, w),
        child: bar,
      );
    });
  }
}
