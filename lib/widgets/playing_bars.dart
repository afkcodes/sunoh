// Animated equalizer bars — used for now-playing indicators (IcWaveSmall) and
// the radio "on air" pulse (LiveBars) in the prototype.

import 'dart:math' as math;
import 'package:flutter/material.dart';

class PlayingBars extends StatefulWidget {
  const PlayingBars({
    super.key,
    required this.color,
    this.size = 14,
    this.count = 5,
    this.animate = true,
  });

  final Color color;
  final double size;
  final int count;
  final bool animate;

  @override
  State<PlayingBars> createState() => _PlayingBarsState();
}

class _PlayingBarsState extends State<PlayingBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final barW = widget.size / (widget.count * 1.8);
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(widget.count, (i) {
              final phase = i * 0.6;
              final base = 0.35 +
                  0.65 *
                      (0.5 +
                          0.5 *
                              math.sin((_c.value * 2 * math.pi) + phase).abs());
              return Container(
                width: barW,
                height: widget.size * base,
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(barW),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
