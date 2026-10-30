// The two motion helpers Home's and Search's horizontal rows and lazy lists
// share: snapping a row to its cards, and letting a lazy list play its
// entrance once.

import 'package:flutter/material.dart';

import '../widgets/motion.dart';

/// Snaps a horizontal row to whole multiples of [extent] — one card plus the
/// gap after it — so a swipe settles with a card on the gutter.
///
/// `PageScrollPhysics` snaps to the viewport's width, which is a card's only
/// when a card fills the screen. These rows leave the next one peeking.
class SnapPhysics extends ScrollPhysics {
  const SnapPhysics({required this.extent, super.parent});
  final double extent;

  @override
  SnapPhysics applyTo(ScrollPhysics? ancestor) =>
      SnapPhysics(extent: extent, parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    if ((velocity <= 0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final tolerance = toleranceFor(position);
    var page = position.pixels / extent;
    if (velocity < -tolerance.velocity) {
      page -= 0.5;
    } else if (velocity > tolerance.velocity) {
      page += 0.5;
    }
    final target = (page.roundToDouble() * extent).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target == position.pixels) return null;
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      velocity,
      tolerance: tolerance,
    );
  }

  @override
  bool get allowImplicitScrolling => false;
}

/// Lets a lazily built list play its entrance once.
///
/// [FadeSlideIn] plays whenever its element is created, and a sliver list
/// creates a row again each time it scrolls back into range — so a section
/// near the top would fade in a second time on the way back up. The gate
/// admits only what is built in the first frame that asks: the screenful the
/// page opened with.
class EntranceGate {
  bool? _open;

  bool admit() {
    final open = _open;
    if (open != null) return open;
    _open = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _open = false);
    return true;
  }
}

/// [FadeSlideIn] for the [index]th block of a lazily built list, if the
/// [gate] still admits it. Decided once, when the block is first built.
class GatedEntrance extends StatefulWidget {
  const GatedEntrance({
    super.key,
    required this.gate,
    required this.index,
    required this.child,
  });

  final EntranceGate gate;
  final int index;
  final Widget child;

  @override
  State<GatedEntrance> createState() => _GatedEntranceState();
}

class _GatedEntranceState extends State<GatedEntrance> {
  late final bool _play =
      widget.index < FadeSlideIn.maxStaggered && widget.gate.admit();

  @override
  Widget build(BuildContext context) => _play
      ? FadeSlideIn(index: widget.index, child: widget.child)
      : widget.child;
}
