// The player's cover, swipeable: drag it sideways and the previous or next
// sleeve slides in from the edge; let go past a third of the way (or with a
// flick) and it settles there and the track changes.
//
// The centre cover is a Hero shared with the mini player's thumbnail, which
// is what makes the player appear to open out of the mini player.
//
// A skip only lands once the engine has actually moved on. The strip holds at
// the neighbour's position until the current track's id changes, and only
// then snaps back to centre — showing the new song in the middle. Snapping
// back immediately put the old cover in the centre for the moment the engine
// took to switch, which read as the swipe bouncing.
//
// PERF: the strip is three images under one Transform driven by a single
// controller; the drag itself is a setState of one double.

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../api/dto.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/cover_hero.dart';
import '../widgets/ui.dart';

/// Shared with the mini player's thumbnail.
const String kPlayerArtHeroTag = 'sunoh-player-art';

/// Linear on purpose: the player route's controller already carries the
/// easing (player_route.dart), and the clip and the page read it straight.
/// Left to its default, a Hero adds its own `fastOutSlowIn` on top and the
/// cover runs on a different clock from the page around it.
const Curve kPlayerArtCurve = Curves.linear;

/// Space between neighbouring covers in the strip.
const double _kGap = 24;

class CoverCarousel extends StatefulWidget {
  const CoverCarousel({
    super.key,
    required this.size,
    required this.currentId,
    required this.currentArt,
    required this.prev,
    required this.next,
    required this.onPrev,
    required this.onNext,
  });

  final double size;
  final String currentId;
  final String? currentArt;
  final FeedItem? prev;
  final FeedItem? next;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  State<CoverCarousel> createState() => _CoverCarouselState();
}

class _CoverCarouselState extends State<CoverCarousel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController.unbounded(vsync: this)
    ..addListener(() => setState(() => _dx = _c.value));

  double _dx = 0;

  /// Set while the strip waits at a neighbour for the engine to catch up.
  bool _awaitingSkip = false;

  double get _step => widget.size + _kGap;

  @override
  void didUpdateWidget(CoverCarousel old) {
    super.didUpdateWidget(old);
    if (old.currentId == widget.currentId) return;
    _c.stop();
    if (_awaitingSkip) {
      // The swipe already showed the new sleeve sliding in; centre it.
      _awaitingSkip = false;
      _dx = 0;
    } else {
      // Changed from a button or the engine: slide the new cover in a
      // little from the right, the direction the queue runs.
      _dx = 60;
      _settle(0, 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _settle(double to, double velocity) {
    _c.value = _dx;
    _c.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 320, damping: 34),
        _dx,
        to,
        velocity,
      ),
    );
  }

  void _onUpdate(DragUpdateDetails d) {
    _c.stop();
    final blocked =
        (d.delta.dx > 0 && widget.prev == null) ||
        (d.delta.dx < 0 && widget.next == null);
    setState(() => _dx += blocked ? d.delta.dx * 0.25 : d.delta.dx);
  }

  void _onEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    final goNext = (_dx < -_step * 0.3 || v < -600) && widget.next != null;
    final goPrev = (_dx > _step * 0.3 || v > 600) && widget.prev != null;
    if (!goNext && !goPrev) return _settle(0, v);
    _awaitingSkip = true;
    _settle(goNext ? -_step : _step, v);
    goNext ? widget.onNext() : widget.onPrev();
    // If the engine never reports the change (end of queue, a failure),
    // do not leave the strip parked on the neighbour.
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted && _awaitingSkip) {
        _awaitingSkip = false;
        _settle(0, 0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return GestureDetector(
      onHorizontalDragUpdate: _onUpdate,
      onHorizontalDragEnd: _onEnd,
      child: SizedBox.square(
        dimension: s,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (widget.prev != null)
              _at(-_step, _Cover(item: widget.prev!, size: s)),
            if (widget.next != null)
              _at(_step, _Cover(item: widget.next!, size: s)),
            _at(
              0,
              Hero(
                tag: kPlayerArtHeroTag,
                createRectTween: straightRectTween,
                curve: kPlayerArtCurve,
                reverseCurve: kPlayerArtCurve,
                // Flies with the finger when the player is dragged closed.
                transitionOnUserGestures: true,
                flightShuttleBuilder: _shuttle,
                child: _Art(
                  id: widget.currentId,
                  url: widget.currentArt,
                  size: s,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _at(double x, Widget child) => Positioned(
    left: x + _dx,
    top: 0,
    width: widget.size,
    height: widget.size,
    child: child,
  );

  /// The flight between the mini player's 44px thumbnail and this cover:
  /// the corner radius grows with the size instead of snapping at the end.
  static Widget _shuttle(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection direction,
    BuildContext fromContext,
    BuildContext toContext,
  ) {
    final to =
        (direction == HeroFlightDirection.push ? toContext : fromContext).widget
            as Hero;
    final art = to.child as _Art;
    return AnimatedBuilder(
      animation: animation,
      builder: (_, _) => squircleClip(
        radius:
            SunohRadius.row +
            (SunohRadius.cover - SunohRadius.row) * animation.value,
        child: SunohArt(
          id: art.id,
          imageUrl: art.url,
          size: art.size,
          radius: 0,
          shadow: false,
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.item, required this.size});
  final FeedItem item;
  final double size;

  @override
  Widget build(BuildContext context) =>
      _Art(id: item.id, url: item.artwork, size: size);
}

/// A cover at full size with the player's lift under it.
class _Art extends StatelessWidget {
  const _Art({required this.id, required this.url, required this.size});
  final String id;
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: squircleBorder(SunohRadius.cover),
        shadows: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isLight ? 0.18 : 0.5),
            blurRadius: 60,
            offset: const Offset(0, 26),
          ),
        ],
      ),
      child: SunohArt(
        id: id,
        imageUrl: url,
        size: size,
        radius: SunohRadius.cover,
        shadow: false,
      ),
    );
  }
}
