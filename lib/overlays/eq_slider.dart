// One band's vertical gain slider, the gesture recogniser that makes it
// usable inside a sheet, and the gain-to-height mapping the rack draws with.
//
// Split out of `eq_sheet.dart` because the arena problem below is the
// interesting part and it has nothing to do with the sheet's layout.
//
// The slider draws nothing. The rack paints every band's track, the curve
// through them and the handles in one CustomPainter (`eq_rack.dart`), so a
// preset morphing between curves repaints one layer rather than rebuilding
// ten widget stacks a frame. What is left here is the hit target — and the
// one mapping both halves must agree on, so a handle is drawn exactly where
// the finger that moved it is.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// How far in from the top and bottom of the fader field ±12 dB sits — the
/// prototype's 14, so a handle at full boost is not half off the rack.
const double kEqTravelInset = 14;

/// The y a [gain] is drawn at in a fader field [height] tall, 0 dB in the
/// middle and [min]/[max] [kEqTravelInset] in from either edge.
double eqGainToY(double gain, double height, double min, double max) {
  final travel = height - 2 * kEqTravelInset;
  return kEqTravelInset + (1 - (gain - min) / (max - min)) * travel;
}

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
/// The whole column is the target, not the drawn track — ten of these share a
/// phone's width, so each is about 36 dp across and every pixel of that has
/// to count.
class EqBandSlider extends StatelessWidget {
  const EqBandSlider({
    super.key,
    required this.gain,
    required this.min,
    required this.max,
    required this.onChanged,
    this.enabled = true,
  });

  final double gain;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return const SizedBox.expand();
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        final travel = h - 2 * kEqTravelInset;

        void apply(Offset local) {
          final y = (local.dy - kEqTravelInset).clamp(0.0, travel);
          final t = 1 - y / travel;
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

        return RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: {
            _EagerVerticalDrag:
                GestureRecognizerFactoryWithHandlers<_EagerVerticalDrag>(
                  _EagerVerticalDrag.new,
                  (r) {
                    r.onStart = (d) => apply(d.localPosition);
                    r.onUpdate = (d) => apply(d.localPosition);
                  },
                ),
          },
          child: const SizedBox.expand(),
        );
      },
    );
  }
}
