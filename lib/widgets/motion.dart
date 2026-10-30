// Small motion primitives shared by every screen: press feedback and a
// staggered entrance.
//
// Both are deliberately cheap. A press is one AnimatedScale and one
// AnimatedOpacity on the widget being pressed; an entrance is a single
// controller per item that runs once and then sits idle — nothing animates
// while a list scrolls.

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Shrinks and dims its child a touch while a finger is on it, so a tap on a
/// cover or a row lands visibly before whatever it opens has arrived.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.97,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// How far it shrinks. Rows use a shallower press than covers; at 0.97 a
  /// full-width row visibly jumps at its edges.
  final double scale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onTapDown: widget.onTap == null ? null : (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: SunohMotion.press,
        curve: SunohMotion.ease,
        child: AnimatedOpacity(
          opacity: _down ? 0.85 : 1,
          duration: SunohMotion.press,
          curve: SunohMotion.ease,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Fades its child up into place once, [index] steps after its siblings.
///
/// For the first screenful of a page only — callers pass the item's position
/// and anything past [maxStaggered] arrives without a delay, so a long list
/// never waits on its own entrance. Rebuilding does not replay it; only a new
/// element (a new page, a new tab's first build) does.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.index = 0,
    this.delay = Duration.zero,
  });

  final Widget child;
  final int index;
  final Duration delay;

  static const int maxStaggered = 10;
  static const Duration step = Duration(milliseconds: 45);

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _c,
    curve: SunohMotion.arrive,
  );

  @override
  void initState() {
    super.initState();
    final i = widget.index.clamp(0, FadeSlideIn.maxStaggered);
    Future.delayed(widget.delay + FadeSlideIn.step * i, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (_, child) => Opacity(
        opacity: _t.value,
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - _t.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}
