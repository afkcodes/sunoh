// Now-playing indicator — three vertical bars whose heights pulse with
// different periods so the row reads as an animated "equalizer." Mirrors
// the RN PlayingIndicator's behavior (3 bars, independent tweens, grow
// from the bottom).
//
// Previous version used 5 bars + a single shared AnimationController +
// sin(t).abs() math that compressed the visible range to ~30% and only
// hooked the controller to `animate` in initState (so the bars never
// kicked in when `animate` flipped on later — which is the entire point,
// since it flips with the playing state from AppState).

import 'package:flutter/material.dart';

class PlayingBars extends StatefulWidget {
  const PlayingBars({
    super.key,
    required this.color,
    this.size = 14,
    this.animate = true,
  });

  final Color color;
  final double size;
  final bool animate;

  @override
  State<PlayingBars> createState() => _PlayingBarsState();
}

// One bar = one independent controller with its own period. Mirrors RN's
// three withRepeat sequences at 500 / 400 / 600 ms.
class _BarSpec {
  const _BarSpec({
    required this.periodMs,
    required this.min,
    required this.max,
  });
  final int periodMs;
  final double min;
  final double max;
}

const _kBars = <_BarSpec>[
  _BarSpec(periodMs: 500, min: 0.30, max: 0.80),
  _BarSpec(periodMs: 400, min: 0.40, max: 1.00),
  _BarSpec(periodMs: 600, min: 0.20, max: 0.90),
];

class _PlayingBarsState extends State<PlayingBars>
    with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = [
      for (final spec in _kBars)
        AnimationController(
          vsync: this,
          duration: Duration(milliseconds: spec.periodMs),
        ),
    ];
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant PlayingBars old) {
    super.didUpdateWidget(old);
    // The whole point of having this widget hook up at runtime: when the
    // track-row goes from paused → playing, `animate` flips and the bars
    // need to start moving. The previous implementation only honored
    // `animate` in initState, so this didn't happen and the indicator
    // sat static.
    if (old.animate != widget.animate) _syncAnimation();
  }

  void _syncAnimation() {
    for (final c in _controllers) {
      if (widget.animate) {
        c.repeat(reverse: true);
      } else {
        c.stop();
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final barW = (widget.size - 2 * 2) / _kBars.length;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < _kBars.length; i++)
            AnimatedBuilder(
              animation: _controllers[i],
              builder: (context, _) {
                final spec = _kBars[i];
                // Each controller goes 0 → 1 → 0 (reverse: true). Lerp
                // gives min → max → min. Linear easing matches RN; the
                // motion already feels rhythmic from the period mix.
                final frac = spec.min + (spec.max - spec.min) * _controllers[i].value;
                return Container(
                  width: barW,
                  height: widget.size * frac,
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: BorderRadius.circular(barW),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
