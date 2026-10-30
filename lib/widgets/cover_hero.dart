// A cover that flies between screens: from a tile or a row into the detail
// page it opens, and back again when that page closes — by the back button
// or under a swipe.
//
// The tag pairs one cover on the list screen with the big cover on the page
// it opened. It is built from where the tap happened (the shelf or list) and
// the item's id, because the same album can sit in two shelves of one screen
// and two covers sharing a tag in one route is an error. The tag travels to
// the detail page with the navigation (`CoverHeroRef`, see router.dart), so a
// page opened from a deep link simply has no partner and nothing flies.
//
// The flight morphs the corner from the small cover's to the big one's and
// moves on a straight line with a linear curve: the route's controller
// already carries the easing (router/transitions.dart), and a Hero's own
// default curve on top of it put the cover on a different clock from the
// page it flies with.

import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'album_art.dart';
import 'ui.dart';

/// What a detail page needs to fly its cover in: the tag the tapped cover
/// used, and that cover's art so the page can show it before its own data
/// has loaded.
class CoverHeroRef {
  const CoverHeroRef({
    required this.tag,
    required this.id,
    required this.size,
    this.imageUrl,
  });
  final String tag;
  final String id;
  final String? imageUrl;

  /// The tapped cover's size: drawing its art at this size reuses the bitmap
  /// already decoded for it, where any other size decodes it again.
  final double size;
}

/// The tag for the cover of [id] tapped in [scope] (a shelf heading, a list
/// name).
String coverHeroTag(String scope, String id) => 'cover|$scope|$id';

/// A straight path between the two rectangles. The Material default bends
/// each corner along its own arc, which stretched a square cover into a wide
/// one halfway through the flight.
RectTween straightRectTween(Rect? begin, Rect? end) =>
    RectTween(begin: begin, end: end);

/// [SunohArt] that flies when [tag] is set, and is plain art when it is not.
class CoverHero extends StatelessWidget {
  const CoverHero({
    super.key,
    required this.tag,
    required this.id,
    required this.imageUrl,
    required this.size,
    required this.radius,
    this.preview,
    this.zoom = 1,
    this.child,
  });

  final String? tag;
  final String id;
  final String? imageUrl;
  final double size;
  final double radius;

  /// How much larger than [size] the art is drawn and cropped, as on the Home
  /// hero cards. The flight eases it to its partner's, so the crop opens out
  /// into the whole sleeve instead of jumping to it.
  final double zoom;

  /// Drawn in place of the plain art while the cover is not flying — for a
  /// cover that moves on its own, like the hero cards' drifting art.
  final Widget? child;

  /// The cover this one was opened from: shown, scaled up, until this
  /// cover's own art has decoded.
  final CoverHeroRef? preview;

  @override
  Widget build(BuildContext context) {
    final p = preview;
    final art = _CoverArt(
      id: id,
      url: imageUrl,
      size: size,
      radius: radius,
      fallback: p == null ? null : _scaled(p.id, p.imageUrl, p.size),
      zoom: zoom,
      child: child,
    );
    final t = tag;
    if (t == null) return art;
    return Hero(
      tag: t,
      createRectTween: straightRectTween,
      curve: Curves.linear,
      reverseCurve: Curves.linear,
      transitionOnUserGestures: true,
      flightShuttleBuilder: _shuttle,
      child: art,
    );
  }

  static Widget _shuttle(
    BuildContext flight,
    Animation<double> animation,
    HeroFlightDirection direction,
    BuildContext fromContext,
    BuildContext toContext,
  ) {
    final from = (fromContext.widget as Hero).child as _CoverArt;
    final to = (toContext.widget as Hero).child as _CoverArt;
    // The art that is already decoded — the one on the screen being left.
    final shown = direction == HeroFlightDirection.push ? from : to;
    final small = direction == HeroFlightDirection.push ? from : to;
    final big = direction == HeroFlightDirection.push ? to : from;
    return AnimatedBuilder(
      animation: animation,
      builder: (_, _) {
        final t = direction == HeroFlightDirection.push
            ? animation.value
            : 1 - animation.value;
        return LayoutBuilder(
          builder: (_, box) => squircleClip(
            radius: lerpDouble(
              small._cornerFor(box.biggest.shortestSide),
              big._cornerFor(box.biggest.shortestSide),
              t,
            )!,
            child: Transform.scale(
              scale: lerpDouble(small.zoom, big.zoom, t)!,
              // At the leaving cover's own size, scaled to the flight: a new
              // size would decode the art again and flash the placeholder
              // on the flight's first frame.
              child: _scaled(shown.id, shown.url, shown.size * shown.zoom),
            ),
          ),
        );
      },
    );
  }
}

/// [id]'s art drawn at [size] and stretched to fill whatever holds it.
Widget _scaled(String id, String? url, double size) => SizedBox.expand(
  child: FittedBox(
    fit: BoxFit.fill,
    child: SunohArt(
      id: id,
      imageUrl: url,
      size: size,
      radius: 0,
      shadow: false,
    ),
  ),
);

class _CoverArt extends StatelessWidget {
  const _CoverArt({
    required this.id,
    required this.url,
    required this.size,
    required this.radius,
    this.fallback,
    this.zoom = 1,
    this.child,
  });
  final String id;
  final String? url;
  final double size;
  final double radius;
  final Widget? fallback;
  final double zoom;
  final Widget? child;

  /// This cover's corner at [side]: a circle stays a circle at any size,
  /// a squircle keeps its radius.
  double _cornerFor(double side) => radius >= size / 2 ? side / 2 : radius;

  @override
  Widget build(BuildContext context) =>
      child ??
      SunohArt(
        id: id,
        imageUrl: url,
        size: size,
        radius: radius,
        shadow: false,
        fallback: fallback,
      );
}
