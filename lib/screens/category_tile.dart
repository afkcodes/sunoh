// The "browse" tile the podcast category grid use — the
// prototype's Browse all card.
//
// Radius 12, its height set by the grid (96 there, 64 in the tabs' preview
// rows). The prototype lays a photo under each card; a category has none, so
// the category's own colour fills the tile and its topic glyph, oversized and
// tucked off the right edge, stands where the photo's subject would. Over that
// a scrim runs left to right, darkest under the title, and a 4px stripe of the
// colour runs down the left edge above the scrim, so the colour still reads at
// the end the eye starts from.
//
// The title is SunohMedia.ink, not fg: it sits on the scrim, which is dark in
// both themes, and fg on the light palette is near-black.

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../widgets/motion.dart';
import '../widgets/ui.dart';

/// Built once rather than per tile per build.
final LinearGradient _scrim = LinearGradient(
  colors: [
    SunohMedia.scrim.withValues(alpha: 0.82),
    SunohMedia.scrim.withValues(alpha: 0.35),
    SunohMedia.scrim.withValues(alpha: 0.1),
  ],
  stops: const [0, 0.7, 1],
);

class CategoryTile extends StatelessWidget {
  const CategoryTile({
    super.key,
    required this.title,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  final String title;

  /// The category's colour, from its screen's palette table.
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: squircleClip(
        radius: SunohRadius.card,
        child: ColoredBox(
          color: color,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                right: -14,
                bottom: -18,
                child: Transform.rotate(
                  angle: 0.2,
                  child: Icon(
                    icon,
                    size: 76,
                    color: inkOn(color).withValues(alpha: 0.32),
                  ),
                ),
              ),
              DecoratedBox(decoration: BoxDecoration(gradient: _scrim)),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 4,
                child: ColoredBox(color: color),
              ),
              Positioned(
                left: 14,
                top: 12,
                right: 12,
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: SunohType.heading(
                    fontSize: 16,
                    color: SunohMedia.ink,
                    height: 1.15,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
