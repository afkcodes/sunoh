// Small shared UI building blocks reused across screens.

import 'package:flutter/material.dart';
import 'package:smooth_corner/smooth_corner.dart';

import '../theme/tokens.dart';
import 'motion.dart';

// ── Squircles ────────────────────────────────────────────────────────────────
// iOS-style continuous (superellipse) corners. Used for all cards and cover
// images so corners feel smooth rather than abruptly rounded.
const double kSquircleSmoothness = 0.6;

/// Space a scrolling page leaves under its last item so it clears the shell's
/// bottom bar. The bar is the gradient lead-in (28) + mini player (62) + nav
/// (about 63) = roughly 153 logical px, PLUS the system gesture/nav inset,
/// which a fixed 140 ignored: the last row ended behind the mini player on
/// every phone with a gesture bar. Computed from the inset, never cached, so
/// it follows 3-button vs gesture navigation.
double shellClearance(BuildContext context) =>
    156 + MediaQuery.paddingOf(context).bottom;

SmoothRectangleBorder squircleBorder(
  double radius, {
  BorderSide side = BorderSide.none,
}) => SmoothRectangleBorder(
  borderRadius: BorderRadius.circular(radius),
  smoothness: kSquircleSmoothness,
  side: side,
);

/// A squircle with only its top corners rounded — sheets attached to the
/// bottom edge.
SmoothRectangleBorder squircleTopBorder(double radius) => SmoothRectangleBorder(
  borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
  smoothness: kSquircleSmoothness,
);

/// A squircle surface decoration (replacement for BoxDecoration on cards).
ShapeDecoration squircleDecoration({
  required double radius,
  Color? color,
  Gradient? gradient,
  Color? borderColor,
  double borderWidth = 0.5,
  List<BoxShadow>? shadows,
}) => ShapeDecoration(
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
    ClipPath(
      clipper: ShapeBorderClipper(shape: squircleBorder(radius)),
      child: child,
    );

/// Mono uppercase eyebrow / data label.
Widget eyebrow(
  String text,
  Color color, {
  double size = 10,
  double letterSpacing = 1.4,
  int? maxLines,
}) {
  return Text(
    text.toUpperCase(),
    maxLines: maxLines,
    overflow: maxLines == null ? TextOverflow.clip : TextOverflow.ellipsis,
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
    return InkResponse(onTap: onTap, radius: width / 2 + 4, child: child);
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
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) SizedBox(width: gap),
            Pressable(
              onTap: onTap == null ? null : () => onTap!(items[i]),
              child: SizedBox(width: width, child: builder(items[i], width)),
            ),
          ],
        ],
      ),
    );
  }
}

/// Section header — title, optional eyebrow, optional "See all".
///
/// "See all" is a plain word now, not "See all →": the arrow doubled the
/// affordance the row's own position already gives, and at 12px it read as a
/// stray glyph. It sits on the title's baseline so the two scan as one line.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    required this.colors,
    this.eyebrowText,
    this.onSeeAll,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 14),
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
                  eyebrow(eyebrowText!, colors.fgMute, letterSpacing: 1.2),
                  const SizedBox(height: 4),
                ],
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SunohType.heading(
                    fontSize: 20,
                    color: colors.fg,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
          if (onSeeAll != null)
            GestureDetector(
              onTap: onSeeAll,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(left: 12, top: 6),
                child: Text(
                  'See all',
                  style: SunohType.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: colors.fgDim,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A filter or scope chip — the one control every chip row in the app uses.
///
/// Filled rather than outlined: an outlined pill on a near-black page is a
/// hairline that reads as disabled, and on light it competes with the text
/// inside it. The selected chip inverts to the ink colour, so selection is
/// carried by a change of fill, not by a colour the user might not see.
class SunohChip extends StatelessWidget {
  const SunohChip({
    super.key,
    required this.label,
    required this.selected,
    required this.colors,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final SunohColors colors;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? colors.bg : colors.fg;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: squircleDecoration(
          radius: 16,
          color: selected ? colors.fg : colors.surface2,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: fg),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: SunohType.sans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Skeleton placeholders ────────────────────────────────────────────────────
// Used by home + search + (future) detail loaders. Pair `Pulse` (subtle
// opacity breathe) with `SkeletonBar` (a squircle filled-rect placeholder).
// Promoted out of home_screen 2026-05-24 so search can reuse the same look.

/// Subtle opacity breathe for skeleton placeholders. 1.1 s reverse-loop with
/// an easeInOut curve so the pulse reads as breathing, not strobing.
class Pulse extends StatefulWidget {
  const Pulse({super.key, required this.child});
  final Widget child;
  @override
  State<Pulse> createState() => _PulseState();
}

class _PulseState extends State<Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        final t = Curves.easeInOut.transform(_c.value);
        return Opacity(opacity: 0.55 + 0.35 * t, child: child);
      },
      child: widget.child,
    );
  }
}

/// A squircle placeholder rectangle. Use sparingly inside `Pulse`.
class SkeletonBar extends StatelessWidget {
  const SkeletonBar({
    super.key,
    required this.height,
    required this.width,
    this.radius = 6,
  });
  final double height;
  final double width;
  final double radius;
  @override
  Widget build(BuildContext context) {
    // White at 6% is a visible placeholder on a near-black page and nothing at
    // all on a light one, which would leave every loading state blank. Take
    // the ink from the theme instead.
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Container(
      width: width,
      height: height,
      decoration: squircleDecoration(
        radius: radius,
        color: isLight
            ? Colors.black.withValues(alpha: 0.07)
            : Colors.white.withValues(alpha: 0.06),
      ),
    );
  }
}
