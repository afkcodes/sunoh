// The cover shapes Home and Search draw their feeds with: a tile for a
// horizontal row, the row itself, and a browse tile for category grids.
// List rows are in feed_row.dart; the snap physics and entrance gate the
// rows share are in feed_motion.dart.
//
// Shared rather than copied per screen. Home's three tabs and Search's two
// views draw the same shapes, and while each kept its own they drifted to
// five tile widths, three title sizes and two corner radii. The measures are
// the redesign prototype's, read off as dp.

import 'package:flutter/material.dart';

import '../api/dto.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/cover_hero.dart';
import '../widgets/motion.dart';
import '../widgets/ui.dart';

/// A cover tile's width in a horizontal row, and the wider one a featured
/// mix row uses.
const double kTileWidth = 136;
const double kTileWideWidth = 164;
const double kTileGap = 12;

/// Above this many items a tile row is built lazily. Below it the row is
/// built whole, which lets it take the height its tallest tile needs rather
/// than reserving two subtitle lines that most rows never use.
const int _kEagerTiles = 20;

// ── Tiles ────────────────────────────────────────────────────────────────

/// A cover in a horizontal row: square art, a one-line title, and up to two
/// lines of subtitle. Artists get a round cover; a row of nothing but round
/// covers centres its text under them.
class FeedTile extends StatelessWidget {
  const FeedTile({
    super.key,
    required this.item,
    required this.width,
    required this.colors,
    this.subtitle,
    this.round = false,
    this.centred = false,
    this.heroTag,
  });

  final FeedItem item;
  final double width;
  final SunohColors colors;
  final String? subtitle;
  final bool round;
  final bool centred;

  /// Flies this cover into the page it opens (widgets/cover_hero.dart).
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final sub = subtitle ?? '';
    final align = centred ? TextAlign.center : TextAlign.start;
    return Column(
      crossAxisAlignment: centred
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        // No shadow: the prototype's covers sit flat on the page, and a
        // blurred shadow under every tile of every row is real paint cost.
        CoverHero(
          tag: heroTag,
          id: item.id,
          imageUrl: item.artwork,
          size: width,
          radius: round ? 999 : SunohRadius.tile,
        ),
        const SizedBox(height: 9),
        // One line, always: a wrapped title pushed the subtitle down and left
        // the tile at a different height from its neighbours.
        Text(
          item.title,
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
            style: SunohType.sans(fontSize: 12, color: c.fgDim, height: 1.35),
          ),
      ],
    );
  }
}

/// The tag [item]'s cover flies under when tapped in [scope] among [items],
/// or null when it does not fly. The rail drawing the cover and the tap
/// opening the page both ask here, so a page only fades in to meet a cover
/// when there really is one (router/transitions.dart, `fromCover`).
///
/// Only covers that open an album or playlist fly, and only the first of a
/// repeated item: two covers with one tag in one screen is an error.
String? feedHeroTag(String? scope, List<FeedItem> items, FeedItem item) {
  if (scope == null || (item.type != 'album' && item.type != 'playlist')) {
    return null;
  }
  final first = items.indexWhere((x) => x.id == item.id);
  return identical(items[first], item) ? coverHeroTag(scope, item.id) : null;
}

/// What a page opened from [item]'s cover (drawn at [size]) needs to fly it
/// in, or null when that cover does not fly — see [feedHeroTag].
CoverHeroRef? feedHeroRef(
  String? scope,
  List<FeedItem> items,
  FeedItem item,
  double size,
) {
  final tag = feedHeroTag(scope, items, item);
  if (tag == null) return null;
  return CoverHeroRef(
    tag: tag,
    id: item.id,
    imageUrl: item.artwork,
    size: size,
  );
}

/// A horizontal row of [FeedTile]s on the 16dp gutter.
///
/// [subtitleOf] null means the row has no subtitle line at all (artists, a
/// show strip that only ever showed titles). [circles] draws every cover
/// round with centred text; otherwise only artists are round.
class FeedTileRow extends StatelessWidget {
  const FeedTileRow({
    super.key,
    required this.items,
    required this.colors,
    required this.onTap,
    this.width = kTileWidth,
    this.subtitleOf,
    this.circles = false,
    this.heroScope,
  });

  /// Where these covers are, for the tag that flies a cover into the album
  /// or playlist it opens — the tapper builds the same tag (see
  /// `coverHeroTag`). Null: nothing flies.
  final String? heroScope;

  final List<FeedItem> items;
  final SunohColors colors;
  final ValueChanged<FeedItem> onTap;
  final double width;
  final String? Function(FeedItem item)? subtitleOf;
  final bool circles;

  Widget _tile(FeedItem item, double w) => FeedTile(
    item: item,
    width: w,
    colors: colors,
    subtitle: subtitleOf?.call(item),
    round: circles || item.type == 'artist',
    centred: circles,
    heroTag: feedHeroTag(heroScope, items, item),
  );

  @override
  Widget build(BuildContext context) {
    if (items.length <= _kEagerTiles) {
      return HCardRow<FeedItem>(
        items: items,
        width: width,
        gap: kTileGap,
        onTap: onTap,
        builder: _tile,
      );
    }
    // A lazy list cannot size itself to its children, so it reserves the
    // tallest a tile can be: cover, gap, a title line, two subtitle lines.
    final scale = MediaQuery.textScalerOf(context);
    final text =
        scale.scale(13.5) * 1.3 +
        (subtitleOf == null ? 0 : scale.scale(12) * 1.35 * 2);
    return SizedBox(
      height: (width + 9 + text).ceilToDouble() + 1,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: kTileGap),
        itemBuilder: (_, i) => Pressable(
          onTap: () => onTap(items[i]),
          child: SizedBox(width: width, child: _tile(items[i], width)),
        ),
      ),
    );
  }
}

// ── Browse tiles ─────────────────────────────────────────────────────────

/// A category or channel in a browse grid: the artwork full-bleed under a
/// left-to-right scrim, the name top-left and any subtitle bottom-left.
///
/// The scrim and the type are the media ones in both themes — artwork is as
/// likely to be dark on the light palette as on the dark.
class BrowseTile extends StatelessWidget {
  const BrowseTile({super.key, required this.item, required this.onTap});
  final FeedItem item;
  final VoidCallback onTap;

  static const double height = 96;

  @override
  Widget build(BuildContext context) {
    final sub = item.subtitle ?? '';
    return Pressable(
      onTap: onTap,
      child: squircleClip(
        radius: SunohRadius.card,
        child: Stack(
          fit: StackFit.expand,
          children: [
            SunohArt(
              id: item.id,
              imageUrl: item.artwork,
              size: 160,
              radius: 0,
              shadow: false,
            ),
            const _BrowseScrim(),
            Positioned(
              left: 14,
              top: 12,
              right: 14,
              child: Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: SunohType.heading(
                  fontSize: 16,
                  color: SunohMedia.ink,
                  height: 1.15,
                ),
              ),
            ),
            if (sub.isNotEmpty)
              Positioned(
                left: 14,
                right: 14,
                bottom: 10,
                child: Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SunohType.sans(
                    fontSize: 11.5,
                    color: SunohMedia.inkDim,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BrowseScrim extends StatelessWidget {
  const _BrowseScrim();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          stops: const [0, 0.7, 1],
          colors: [
            SunohMedia.scrim.withValues(alpha: 0.82),
            SunohMedia.scrim.withValues(alpha: 0.35),
            SunohMedia.scrim.withValues(alpha: 0.1),
          ],
        ),
      ),
    );
  }
}
