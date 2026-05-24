// Small shared UI building blocks reused across screens.

import 'package:flutter/material.dart';
import 'package:smooth_corner/smooth_corner.dart';

import '../theme/tokens.dart';

// ── Squircles ────────────────────────────────────────────────────────────────
// iOS-style continuous (superellipse) corners. Used for all cards and cover
// images so corners feel smooth rather than abruptly rounded.
const double kSquircleSmoothness = 0.6;

SmoothRectangleBorder squircleBorder(double radius, {BorderSide side = BorderSide.none}) =>
    SmoothRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      smoothness: kSquircleSmoothness,
      side: side,
    );

/// A squircle surface decoration (replacement for BoxDecoration on cards).
ShapeDecoration squircleDecoration({
  required double radius,
  Color? color,
  Gradient? gradient,
  Color? borderColor,
  double borderWidth = 0.5,
  List<BoxShadow>? shadows,
}) =>
    ShapeDecoration(
      color: color,
      gradient: gradient,
      shadows: shadows,
      shape: squircleBorder(
        radius,
        side: borderColor == null
            ? BorderSide.none
            : BorderSide(color: borderColor, width: borderWidth),
      ),
    );

/// Clip a child to a squircle (replacement for ClipRRect).
Widget squircleClip({required double radius, required Widget child}) =>
    ClipPath(clipper: ShapeBorderClipper(shape: squircleBorder(radius)), child: child);

/// Mono uppercase eyebrow / data label.
Widget eyebrow(
  String text,
  Color color, {
  double size = 10,
  double letterSpacing = 1.4,
}) {
  return Text(
    text.toUpperCase(),
    style: SunohType.mono(
      fontSize: size,
      color: color,
      letterSpacing: letterSpacing,
      fontWeight: FontWeight.w500,
    ),
  );
}

/// Round, transparent tap target around an icon — the prototype's iconBtn().
class IconBtn extends StatelessWidget {
  const IconBtn({
    super.key,
    required this.icon,
    required this.color,
    this.size = 22,
    this.onTap,
    this.background,
    this.width = 40,
    this.height = 40,
  });

  final IconData icon;
  final Color color;
  final double size;
  final VoidCallback? onTap;
  final Color? background;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final child = Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: background == null
          ? null
          : BoxDecoration(color: background, shape: BoxShape.circle),
      child: Icon(icon, size: size, color: color),
    );
    if (onTap == null) return child;
    return InkResponse(
      onTap: onTap,
      radius: width / 2 + 4,
      child: child,
    );
  }
}

/// Horizontal scroll row of fixed-width cards.
class HCardRow<T> extends StatelessWidget {
  const HCardRow({
    super.key,
    required this.items,
    required this.width,
    required this.builder,
    this.onTap,
    this.gap = 12,
  });

  final List<T> items;
  final double width;
  final double gap;
  final void Function(T item)? onTap;
  final Widget Function(T item, double width) builder;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) SizedBox(width: gap),
            GestureDetector(
              onTap: onTap == null ? null : () => onTap!(items[i]),
              child: SizedBox(width: width, child: builder(items[i], width)),
            ),
          ],
        ],
      ),
    );
  }
}

/// Section header — small serif italic title + optional eyebrow + "See all".
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    required this.colors,
    this.eyebrowText,
    this.onSeeAll,
    this.padding = const EdgeInsets.fromLTRB(20, 0, 20, 14),
  });

  final String title;
  final SunohColors colors;
  final String? eyebrowText;
  final VoidCallback? onSeeAll;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (eyebrowText != null) ...[
                  eyebrow(eyebrowText!, colors.fgMute, size: 10, letterSpacing: 1.2),
                  const SizedBox(height: 2),
                ],
                Text(
                  title,
                  style: SunohType.heading(
                    fontSize: 19,
                    color: colors.fg,
                    height: 1.0,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
          if (onSeeAll != null)
            GestureDetector(
              onTap: onSeeAll,
              child: Text(
                'See all →',
                style: SunohType.sans(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: colors.fgMute,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
