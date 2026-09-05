// One band's vertical gain slider, and the gesture recogniser that makes it
// usable inside a sheet.
//
// Split out of `eq_sheet.dart` because the arena problem below is the
// interesting part and it has nothing to do with the sheet's layout.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';

/// A vertical drag that refuses to lose the gesture arena.
///
/// This is why the band sliders were nearly impossible to move, and why the
/// sheet slid away underneath them. A modal bottom sheet drags to dismiss, a
/// `ListView` scrolls, and this slider wants the same downward swipe. The
/// original asked with `GestureDetector.onPanUpdate`, and a *pan* recogniser
/// must rule out horizontal movement before it can claim anything — so anything
/// recognising a plain vertical drag got there first. The finger moved, the
/// sheet moved, the band did not.
///
/// Accepting on rejection takes the gesture the moment the arena tries to hand
/// it elsewhere. Safe because this recogniser exists only inside one band
/// column: a drag that starts on a band is a band adjustment by definition.
///
/// The sheet's own layout does the other half of the job — the rack no longer
/// lives inside anything scrollable, so most of the time there is no contest
/// left to win. This stays as the guarantee.
class _EagerVerticalDrag extends VerticalDragGestureRecognizer {
  @override
  void rejectGesture(int pointer) => acceptGesture(pointer);
}

/// A single band's gain slider: drag anywhere in the column to set it.
///
/// The whole column is the target, not the 4 px track — ten of these share a
/// phone's width, so each is about 32 dp across and every pixel of that has to
/// count. The visible track stays thin because a fat one would read as ten
/// scrollbars.
class EqBandSlider extends StatelessWidget {
  const EqBandSlider({
    super.key,
    required this.gain,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.colors,
    required this.accent,
    this.enabled = true,
  });

  final double gain;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final SunohColors colors;
  final Color accent;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        final w = constraints.maxWidth;

        // Gain to a y offset from the top. 0 dB sits in the middle.
        double gainToY(double g) => (1 - (g - min) / (max - min)) * h;

        void apply(Offset local) {
          final t = 1 - (local.dy.clamp(0.0, h) / h);
          // Whole dB, so the travel has twenty-four detents rather than a
          // continuum nobody can hit twice.
          final value = (min + t * (max - min)).roundToDouble();
          // Only on a real change, which does two jobs: it gives the haptic
          // something to click against, and it stops a drag calling
          // `notifyListeners` on `AppState` sixty times a second — every
          // watcher was rebuilding per frame for a value that moves at most
          // twenty-four times across the whole column.
          if (value == gain) return;
          HapticFeedback.selectionClick();
          onChanged(value);
        }

        final centreY = gainToY(0);
        final thumbY = gainToY(gain);
        final fillTop = thumbY < centreY ? thumbY : centreY;
        final fillHeight = (thumbY - centreY).abs();
        final active = gain.abs() > 0.05;

        return RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: enabled
              ? {
                  _EagerVerticalDrag:
                      GestureRecognizerFactoryWithHandlers<_EagerVerticalDrag>(
                        _EagerVerticalDrag.new,
                        (r) {
                          r.onStart = (d) => apply(d.localPosition);
                          r.onUpdate = (d) => apply(d.localPosition);
                        },
                      ),
                }
              : const {},
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Unfilled track.
              Container(
                width: 3,
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Fill from the 0 dB line out to the current gain, so a cut
              // reads as clearly downward as a boost reads upward. A bar
              // growing from the bottom would make -12 dB look like "a little"
              // rather than "as far down as it goes".
              Positioned(
                top: fillTop,
                child: Container(
                  width: 3,
                  height: fillHeight.clamp(0, h),
                  decoration: BoxDecoration(
                    color: active ? accent : c.fgMute,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Thumb. Wide enough to look grabbable at a glance; the actual
              // target is the entire column regardless.
              Positioned(
                top: (thumbY - 7).clamp(0.0, h - 14),
                child: Container(
                  width: (w * 0.62).clamp(16.0, 26.0),
                  height: 14,
                  decoration: BoxDecoration(
                    color: active ? accent : c.fg,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: c.bgSoft, width: 1.5),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
