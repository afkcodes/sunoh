// How the expanded player arrives and leaves, and how the queue sheet rides
// over it.
//
// Opening grows the player out of the mini player: the page is clipped to
// the mini player's own rectangle and that clip opens to the full screen,
// while the cover (a Hero shared with the mini player's thumbnail) flies from
// the thumbnail to its place. The controls then rise into place one after
// another (`PlayerEntrance`). Closing is the same move run backwards: the
// page shrinks back into the mini player's card while the controls fade out
// and the cover flies into the thumbnail, so the background and the cover
// land at the same moment. (It used to slide the whole page off the bottom of
// the screen; the cover reached the mini player while the background was
// still on its way down, and the close read as two things finishing apart.)
//
// One clock drives all of it. The route's own controller carries the easing
// (pushes and pops animate it on [SunohMotion.arrive], see [_PlayerRoute]),
// and everything that moves — the clip, the page, and the Hero, which is set
// to a linear curve — reads that value straight. An earlier version eased in
// two places, once in the transition and once in the Hero's own default
// curve, and the cover and the page drifted apart on every close.
//
// Dragging the page down is the same close run by hand: the drag sets the
// controller (an iOS-style user gesture, so the Hero flies with the finger
// and the cover shrinks toward the mini player as the page follows it down).
// Let go past a third of the way, or with a downward flick, and it finishes
// from where it is; otherwise it springs back.
//
// PERF: the clip is a rounded rectangle, not a path, and it is dropped the
// moment the animation settles, so a fully open player pays nothing for it.
// The mini player's rectangle is read from its render box each frame of the
// opening only; nothing is measured while the player is open.

import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/tokens.dart';

/// Attached to the mini player card so the player can open out of it.
final GlobalKey miniPlayerKey = GlobalKey(debugLabel: 'mini-player');

/// The mini player's rectangle in global coordinates, or null when it is not
/// on screen (a full-screen route over the shell, say).
Rect? _miniRect() {
  final box = miniPlayerKey.currentContext?.findRenderObject();
  if (box is! RenderBox || !box.attached || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// The page go_router builds for `/player`.
class PlayerPage extends Page<void> {
  const PlayerPage({super.key, required this.child});
  final Widget child;

  @override
  Route<void> createRoute(BuildContext context) => _PlayerRoute(this);
}

/// Dragging the player closed by hand. See [playerDismissOf].
abstract interface class PlayerDismiss {
  /// The drag has started moving downwards.
  void begin();

  /// The finger has moved [dy] pixels (positive is down).
  void update(double dy);

  /// The finger lifted, moving at [velocity] pixels a second.
  void end(double velocity);
}

/// The player route's drag-to-close handle, or null outside the player.
PlayerDismiss? playerDismissOf(BuildContext context) {
  final route = ModalRoute.of(context);
  return route is _PlayerRoute ? route : null;
}

/// True while the player is closing, by hand or not — the open-only motion
/// (the clip, the staggered entrance) stays out of the way then.
bool _isClosing(Route<dynamic>? route, Animation<double> animation) =>
    animation.status == AnimationStatus.reverse ||
    (route is _PlayerRoute && route._dismissing);

class _PlayerRoute extends PageRoute<void> implements PlayerDismiss {
  _PlayerRoute(PlayerPage page) : super(settings: page);

  PlayerPage get _page => settings as PlayerPage;

  /// Set from the first frame of a close until the page is gone, or until a
  /// cancelled drag has sprung back.
  bool _dismissing = false;
  bool _byHand = false;

  @override
  bool get opaque => false;
  @override
  Color? get barrierColor => null;
  @override
  String? get barrierLabel => null;
  @override
  bool get maintainState => true;
  @override
  Duration get transitionDuration => SunohMotion.player;
  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 380);

  @override
  TickerFuture didPush() {
    super.didPush();
    // Eased here, on the controller, rather than in each thing that moves.
    return controller!.animateTo(
      1,
      duration: transitionDuration,
      curve: SunohMotion.arrive,
    );
  }

  @override
  bool didPop(void result) {
    _dismissing = true;
    final popped = super.didPop(result);
    if (!_byHand) _closeFrom(controller!.value);
    return popped;
  }

  /// Run the controller to 0 from [from] on the player's curve, faster the
  /// less there is left to travel.
  void _closeFrom(double from) {
    controller!.animateBack(
      0,
      duration: reverseTransitionDuration * from.clamp(0.35, 1.0),
      curve: SunohMotion.arrive,
    );
  }

  @override
  void begin() {
    if (_byHand || !isCurrent) return;
    _byHand = true;
    _dismissing = true;
    controller!.stop();
    navigator!.didStartUserGesture();
  }

  /// How far the card's top edge travels over a whole close: from the top of
  /// the screen to the top of the mini player. A drag of that many pixels is
  /// a full close, so the edge stays under the finger.
  double get _travel {
    final mini = _miniRect();
    final h = navigator?.context.size?.height ?? 800;
    return (mini?.top ?? h * 0.85).clamp(200.0, h);
  }

  @override
  void update(double dy) {
    if (!_byHand) return;
    controller!.value = (controller!.value - dy / _travel).clamp(0.0, 1.0);
  }

  @override
  void end(double velocity) {
    if (!_byHand) return;
    final c = controller!;
    final v = velocity / _travel;
    final close = v > 1.1 || (c.value < 0.68 && v > -0.6);
    if (close) {
      navigator!.pop();
      _closeFrom(c.value);
    } else {
      c.animateTo(1, duration: SunohMotion.ui, curve: SunohMotion.arrive);
    }
    void finish() {
      _byHand = false;
      if (!close) _dismissing = false;
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
    Animation<double> a,
    Animation<double> b,
  ) => Material(type: MaterialType.transparency, child: _page.child);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => _PlayerTransition(route: this, animation: animation, child: child);
}

class _PlayerTransition extends StatelessWidget {
  const _PlayerTransition({
    required this.route,
    required this.animation,
    required this.child,
  });
  final _PlayerRoute route;
  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        // Straight from the controller: under a finger it tracks the finger,
        // and on its own it is already eased.
        final t = animation.value;
        if (t >= 1) return child!;
        final full = Offset.zero & size;
        final mini =
            _miniRect() ??
            Rect.fromLTWH(8, size.height - 160, size.width - 16, 56);
        // The player as a card between the mini player's rectangle and the
        // whole screen. Its content rides on the card's top edge, so it
        // moves with the finger rather than being cropped in place.
        final card = Rect.lerp(mini, full, t)!;
        Widget page = Transform.translate(
          offset: Offset(0, card.top),
          child: child,
        );
        // Closing, the card dissolves over its last stretch, so it ends as
        // the mini player underneath rather than as a second card on top.
        if (_isClosing(route, animation) && t < 0.35) {
          page = Opacity(opacity: t / 0.35, child: page);
        }
        return ClipRRect(
          clipper: _RevealClip(card, lerpDouble(SunohRadius.card, 0, t)!),
          child: page,
        );
      },
    );
  }
}

class _RevealClip extends CustomClipper<RRect> {
  const _RevealClip(this.rect, this.radius);
  final Rect rect;
  final double radius;

  @override
  RRect getClip(Size size) =>
      RRect.fromRectAndRadius(rect, Radius.circular(radius));

  @override
  bool shouldReclip(_RevealClip old) =>
      old.rect != rect || old.radius != radius;
}

/// Rises [child] into place while the player opens, [order] steps after the
/// cover. Shown as-is while the player closes — the whole page is sliding
/// away then, and fading its parts on the way out reads as a glitch.
class PlayerEntrance extends StatefulWidget {
  const PlayerEntrance({super.key, required this.order, required this.child});
  final int order;
  final Widget child;

  @override
  State<PlayerEntrance> createState() => _PlayerEntranceState();
}

class _PlayerEntranceState extends State<PlayerEntrance> {
  ModalRoute<dynamic>? _route;
  Animation<double>? _t;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    final animation = route?.animation;
    if (route == null || animation == null || route == _route) return;
    _route = route;
    // Staggered 50 apart, a third of the way into the opening. The route's
    // value is already eased, so the interval runs on a straight line.
    final start = (0.25 + 0.07 * widget.order).clamp(0.0, 0.9);
    _t = CurvedAnimation(parent: animation, curve: Interval(start, 1));
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    if (t == null) return widget.child;
    return AnimatedBuilder(
      animation: t,
      child: widget.child,
      builder: (_, child) {
        final animation = _route!.animation!;
        if (_isClosing(_route, animation)) {
          // Gone over the first 40% of a close, so only the background and
          // the cover are left by the time the card nears the mini player.
          final o = ((animation.value - 0.6) / 0.4).clamp(0.0, 1.0);
          return Opacity(opacity: o, child: child);
        }
        if (animation.isCompleted) return child!;
        return Opacity(
          opacity: t.value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - t.value)),
            child: child,
          ),
        );
      },
    );
  }
}

/// The queue, as a sheet over the player: it stops short of the player's
/// header, so the song it belongs to stays in view above it.
CustomTransitionPage<void> playerSheetPage(Widget child, GoRouterState state) {
  return CustomTransitionPage(
    key: state.pageKey,
    opaque: false,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: SunohMotion.sheet,
    reverseTransitionDuration: SunohMotion.away,
    child: _SheetFrame(child: child),
    transitionsBuilder: (context, animation, _, child) => SlideTransition(
      position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(
        CurvedAnimation(
          parent: animation,
          curve: SunohMotion.arrive,
          reverseCurve: SunohMotion.leave,
        ),
      ),
      child: child,
    ),
  );
}

/// Positions the sheet below the player's header and lets the top of it be
/// dragged down to close.
class _SheetFrame extends StatefulWidget {
  const _SheetFrame({required this.child});
  final Widget child;

  @override
  State<_SheetFrame> createState() => _SheetFrameState();
}

class _SheetFrameState extends State<_SheetFrame> {
  double _drag = 0;
  bool _dragging = false;

  void _end(DragEndDetails d) {
    if (_drag > 110 || (d.primaryVelocity ?? 0) > 700) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _dragging = false;
      _drag = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top + 64;
    // The list inside wins vertical drags that start on it (it is deeper in
    // the hit test), so only the sheet's header pulls the sheet down.
    return Padding(
      padding: EdgeInsets.only(top: top),
      child: AnimatedContainer(
        duration: _dragging ? Duration.zero : SunohMotion.ui,
        curve: SunohMotion.arrive,
        transform: Matrix4.translationValues(0, _drag, 0),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragUpdate: (d) => setState(() {
            _dragging = true;
            _drag = (_drag + d.delta.dy).clamp(0, double.infinity);
          }),
          onVerticalDragEnd: _end,
          child: Material(type: MaterialType.transparency, child: widget.child),
        ),
      ),
    );
  }
}
