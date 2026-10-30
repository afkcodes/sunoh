// The cover tile and the horizontal shelf that holds a row of them.
//
// One tile for every shelf and cover grid these screens draw — on-device
// albums, YouTube shelves, subscribed shows, playlists in grid mode, the
// podcast category grid — so none of them can drift in size.
// The measures are the prototype's tile: a square cover on the tile radius,
// 9 to a one-line title, then up to two lines of subtitle. Artists take a
// circle and centre their text, the way people read differently from sleeves.
//
// Also the two-column cover grid the podcast category page
// use, so a grid cell and a shelf tile are the same tile.

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../widgets/motion.dart';

/// A tile's width in a horizontal shelf. Grids size theirs to the column.
const double kCoverTileWidth = 136;

class CoverTile extends StatelessWidget {
  const CoverTile({
    super.key,
    required this.cover,
    required this.title,
    required this.colors,
    required this.onTap,
    this.subtitle,
    this.round = false,
    this.width = kCoverTileWidth,
  });

  /// The artwork, already sized to [width] square by the caller — a
  /// `SunohArt` mostly, a painted fallback for a playlist with no songs.
  final Widget cover;
  final String title;
  final String? subtitle;
  final SunohColors colors;
  final VoidCallback onTap;
  final bool round;
  final double width;

  /// Everything under the cover: the gap, one title line and two subtitle
  /// lines, at the reader's text scale. A shelf or grid cell is this plus the
  /// cover, so a subtitle that wraps never overflows the box it was given.
  static double textHeight(BuildContext context) {
    final t = MediaQuery.textScalerOf(context);
    return 9 + t.scale(13.5) * 1.3 + t.scale(12) * 1.35 * 2 + 2;
  }

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final align = round ? TextAlign.center : TextAlign.start;
    final sub = subtitle ?? '';
    return Pressable(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: round
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            cover,
            const SizedBox(height: 9),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: align,
              style: SunohType.sans(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: c.fg,
                height: 1.3,
              ),
            ),
            if (sub.isNotEmpty)
              Text(
                sub,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: align,
                style: SunohType.sans(
                  fontSize: 12,
                  color: c.fgDim,
                  height: 1.35,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A lazy horizontal row of [CoverTile]s on the page gutter, 12 between.
class CoverShelf extends StatelessWidget {
  const CoverShelf({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kCoverTileWidth + CoverTile.textHeight(context),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: itemCount,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: itemBuilder,
      ),
    );
  }
}

/// A lazy two-column grid of cover tiles on the page gutter. Each cell is a
/// square cover at the column's width plus the tile's text block, so a
/// two-line byline never overflows its cell; [tile] is handed that width.
class CoverGrid extends StatelessWidget {
  const CoverGrid({super.key, required this.count, required this.tile});

  final int count;
  final Widget Function(BuildContext context, int i, double width) tile;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = (box.maxWidth - 32 - 12) / 2;
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 140),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 18,
            mainAxisExtent: w + CoverTile.textHeight(context),
          ),
          itemCount: count,
          itemBuilder: (context, i) => tile(context, i, w),
        );
      },
    );
  }
}
