// Page transitions for the router.
//
// The app's one navigation language. A tab root fades in. Every other page
// slides in over the full width while the page under it drifts a quarter left
// and dims, however it was opened; a tapped cover flies into the page during
// that same slide (widgets/cover_hero.dart). Overlays (the lyrics page here,
// sheets in overlays/sheet.dart) rise from the bottom. The player and the
// queue have their own routes, next to the player (player/player_route.dart).
//
// Timings come from SunohMotion, so a page, a sheet and a tab take the same
// time wherever they are opened from.
//
// Split out of router.dart, which was over the size limit, once the redesign
// gave every page a real transition.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/app_state_provider.dart';
import '../theme/tokens.dart';

// ── Transition pages ────────────────────────────────────────────────────────
CustomTransitionPage<void> fadePage(Widget child, GoRouterState state) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: _Ground(child: child),
    transitionDuration: SunohMotion.tab,
    transitionsBuilder: (c, a, sa, ch) => _Covered(
      by: sa,
      child: FadeTransition(opacity: a, child: ch),
    ),
  );
}

/// A page. It slides in over the whole width while the page under it drifts
/// a quarter of the way left and dims (see [_Covered]), and swiping right
/// anywhere on it drags it back off by hand (see [_SwipeRoute]); Android's
/// back gesture and the back button run the same path on their own.
///
/// One arrival for every page. Pages opened from a cover once faded in place
/// instead, as the prototype's album did, and next to the sliding pages that
/// read as two navigation systems in one app. The cover still flies, riding
/// the same controller as the slide.
Page<void> pushPage(Widget child, GoRouterState state) => _SwipePage(
  key: state.pageKey,
  child: _Ground(child: child),
);

class _SwipePage extends Page<void> {
  const _SwipePage({super.key, required this.child});
  final Widget child;

  @override
  Route<void> createRoute(BuildContext context) => _SwipeRoute(this);
}

/// The detail route. Like the player's, its controller carries the easing —
/// pushes and pops animate it on [SunohMotion.arrive] — and everything that
/// moves reads the value straight: the page, the page under it, and any
/// cover flying between them. A swipe sets the same controller as a user
/// gesture, so the page tracks the finger, the cover flies back with it, and
/// letting go finishes or springs back from wherever it is.
class _SwipeRoute extends PageRoute<void> {
  _SwipeRoute(_SwipePage page) : super(settings: page);

  bool _byHand = false;

  @override
  Color? get barrierColor => null;
  @override
  String? get barrierLabel => null;
  @override
  bool get maintainState => true;
  @override
  Duration get transitionDuration => SunohMotion.screen;
  @override
  Duration get reverseTransitionDuration => SunohMotion.away;

  @override
  TickerFuture didPush() {
    super.didPush();
    return controller!.animateTo(
      1,
      duration: transitionDuration,
      curve: SunohMotion.arrive,
    );
  }

  @override
  bool didPop(void result) {
    final popped = super.didPop(result);
    if (!_byHand) _closeFrom(controller!.value);
    return popped;
  }

  void _closeFrom(double from) => controller!.animateBack(
    0,
    duration: reverseTransitionDuration * from.clamp(0.35, 1.0),
    curve: SunohMotion.arrive,
  );

  double get _width => navigator?.context.size?.width ?? 400;

  void _begin() {
    if (_byHand || !isCurrent || !(navigator?.canPop() ?? false)) return;
    _byHand = true;
    controller!.stop();
    navigator!.didStartUserGesture();
  }

  void _update(double dx) {
    if (!_byHand) return;
    controller!.value = (controller!.value - dx / _width).clamp(0.0, 1.0);
  }

  void _end(double velocity) {
    if (!_byHand) return;
    final c = controller!;
    final v = velocity / _width;
    final close = v > 1.0 || (c.value < 0.6 && v > -0.5);
    if (close) {
      navigator!.pop();
      _closeFrom(c.value);
    } else {
      c.animateTo(1, duration: SunohMotion.ui, curve: SunohMotion.arrive);
    }
    void finish() {
      _byHand = false;
      navigator?.didStopUserGesture();
    }

    if (!c.isAnimating) return finish();
    late final AnimationStatusListener listener;
    listener = (status) {
      if (status.isAnimating) return;
      c.removeStatusListener(listener);
      finish();
    };
    c.addStatusListener(listener);
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => _BackSwipe(route: this, child: (settings as _SwipePage).child);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => _Covered(
    by: secondaryAnimation,
    child: AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final t = animation.value;
        if (t >= 1) return child!;
        final w = MediaQuery.sizeOf(context).width;
        return Transform.translate(
          offset: Offset((1 - t) * w, 0),
          child: Stack(
            clipBehavior: Clip.none,
            fit: StackFit.passthrough,
            children: [
              // The page's leading edge, as a short gradient rather than a
              // blurred shadow: a 48px blur on a full-screen layer was the
              // costliest thing on every frame of the slide.
              Positioned(
                left: -16,
                top: 0,
                bottom: 0,
                width: 16,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withValues(alpha: 0),
                        Colors.black.withValues(alpha: 0.35),
                      ],
                    ),
                  ),
                ),
              ),
              child!,
            ],
          ),
        );
      },
    ),
  );
}

/// Reports rightward drags on a detail page to its route. A horizontal list
/// inside the page sits deeper in the hit test and wins its own drags, so a
/// carousel still scrolls; a drag anywhere else swipes the page back.
class _BackSwipe extends StatefulWidget {
  const _BackSwipe({required this.route, required this.child});
  final _SwipeRoute route;
  final Widget child;

  @override
  State<_BackSwipe> createState() => _BackSwipeState();
}

class _BackSwipeState extends State<_BackSwipe> {
  bool _dragging = false;

  void _update(DragUpdateDetails d) {
    if (!_dragging) {
      if (d.delta.dx <= 0) return;
      _dragging = true;
      widget.route._begin();
    }
    widget.route._update(d.delta.dx);
  }

  void _end(double velocity) {
    if (!_dragging) return;
    _dragging = false;
    widget.route._end(velocity);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onHorizontalDragUpdate: _update,
    onHorizontalDragEnd: (d) => _end(d.primaryVelocity ?? 0),
    onHorizontalDragCancel: () => _end(0),
    child: widget.child,
  );
}

CustomTransitionPage<void> slideUpPage(Widget child, GoRouterState state) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: Material(type: MaterialType.transparency, child: child),
    opaque: false,
    transitionDuration: SunohMotion.sheet,
    reverseTransitionDuration: SunohMotion.away,
    transitionsBuilder: (c, a, sa, ch) => SlideTransition(
      position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(
        CurvedAnimation(
          parent: a,
          curve: SunohMotion.arrive,
          reverseCurve: SunohMotion.leave,
        ),
      ),
      child: ch,
    ),
  );
}

/// The page's own ground. A page that slides the full width has to be
/// opaque or the one under it shows through; most screens draw on the
/// shell's colour rather than their own.
class _Ground extends ConsumerWidget {
  const _Ground({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ColoredBox(
    color: ref.watch(appStateProvider.select((s) => s.colors.bg)),
    child: child,
  );
}

/// What happens to a page while another slides in over it: it drifts left a
/// quarter of the width and darkens by half. Costs nothing at rest.
class _Covered extends StatelessWidget {
  const _Covered({required this.by, required this.child});
  final Animation<double> by;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: by,
      child: child,
      builder: (context, child) {
        // Straight from the route above, whose controller is already eased.
        final e = by.value;
        if (e == 0) return child!;
        return Transform.translate(
          offset: Offset(-0.26 * MediaQuery.sizeOf(context).width * e, 0),
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              child!,
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.5 * e),
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
