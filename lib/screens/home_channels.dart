// The Saavn "Browse" row: channels as browse tiles in a two-row grid.
//
// Split out of home_screen.dart (which was over the size limit) along the
// seam it already had: a channel row is its own shape with its own renderer,
// used nowhere else.
//
// The tiles are Search's browse tiles — the channel's artwork full-bleed
// under a scrim, its name on top. They used to be a gradient tinted from
// each tile's artwork palette, with the art tucked rotated into the corner;
// that meant a palette extraction per tile on the way into Home, for a
// colour the artwork itself now shows.

import 'package:flutter/material.dart';

import '../api/dto.dart';
import '../router/router.dart';
import '../theme/tokens.dart';
import 'feed_tiles.dart';

/// Channels as a horizontally scrolling grid of [BrowseTile]s. Used when an
/// entire section is channel-typed.
class ChannelGrid extends StatelessWidget {
  const ChannelGrid({
    super.key,
    required this.items,
    required this.colors,
    required this.sectionSource,
  });
  final List<FeedItem> items;
  final SunohColors colors;
  final String? sectionSource;

  // Kept as constants so the SizedBox height matches the grid's row
  // arithmetic exactly. Two rows, not three: at the browse tile's 96dp a
  // third row made the section taller than a screenful of anything else.
  // At 164 wide two columns fit with a third peeking.
  static const int _rows = 2;
  static const double _gap = 8;
  static const double _tileW = 164;

  @override
  Widget build(BuildContext context) {
    const totalHeight = _rows * BrowseTile.height + (_rows - 1) * _gap;
    return SizedBox(
      height: totalHeight,
      // No `physics:` override — `SunohScrollBehavior` (app-wide) owns scroll
      // feel. Earlier inline BouncingScrollPhysics ignored the global friction
      // tuning and made this row feel different from the rest of the app.
      child: GridView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          // In a horizontal GridView `crossAxisCount` is the ROW count, and
          // `mainAxisExtent` is each tile's width.
          crossAxisCount: _rows,
          mainAxisExtent: _tileW,
          mainAxisSpacing: _gap,
          crossAxisSpacing: _gap,
        ),
        itemCount: items.length,
        // Saavn channels open through `music/occasions/[id]` per the API.
        itemBuilder: (context, i) => BrowseTile(
          item: items[i],
          onTap: () => context.openOccasion(items[i]),
        ),
      ),
    );
  }
}
