// A row of covers under a detail page — "More by", "Listeners also like",
// an artist's discography, a category's playlists — and the tile it is made
// of.
//
// Tiles follow the prototype's shelf: a 136 square cover on the tile radius,
// a one-line title and up to two lines of subtitle. Artists sit in circles
// with their name centred under them.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dto.dart';
import '../audio/radio_actions.dart';
import '../data/models.dart';
import '../providers/app_state_provider.dart';
import '../router/router.dart';
import '../theme/tokens.dart';
import '../widgets/cover_hero.dart';
import '../widgets/ui.dart';
import 'feed_tiles.dart';

/// Width of a regular shelf tile.
const double kShelfTile = 136;

/// One related section: header, then a horizontal row of up to ten tiles,
/// with "See all" opening the rest.
class DetailShelf extends ConsumerWidget {
  const DetailShelf({super.key, required this.section, required this.colors});
  final HomeSection section;
  final SunohColors colors;

  static const int _visible = 10;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = section.items;
    final isArtistRow = items.every((it) => it.type == 'artist');
    final hasMore = items.length > _visible;
    final shown = hasMore ? items.sublist(0, _visible) : items;
    // This shelf's own, not its heading: a page's "More by" can hold the
    // page's own album, whose cover already flies under a tag on that page.
    final scope = 'shelf ${identityHashCode(section)}';
    return Padding(
      padding: const EdgeInsets.only(top: 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: section.heading,
            colors: colors,
            onSeeAll: hasMore ? () => context.openSection(section) : null,
          ),
          HCardRow<FeedItem>(
            items: shown,
            width: kShelfTile,
            onTap: (item) => _open(
              context,
              ref,
              item,
              feedHeroRef(scope, shown, item, kShelfTile),
            ),
            builder: (item, w) => ShelfTile(
              item: item,
              width: w,
              colors: colors,
              round: isArtistRow,
              heroTag: feedHeroTag(scope, shown, item),
            ),
          ),
        ],
      ),
    );
  }

  void _open(
    BuildContext context,
    WidgetRef ref,
    FeedItem item,
    CoverHeroRef? hero,
  ) {
    final src = item.source ?? section.source;
    // YouTube ids are browse ids sunoh-api can't resolve. Without this, a
    // YouTube artist's discography opened the sunoh-api album screen with a
    // browse id and rendered a placeholder record — no title, "NULL, NULL",
    // one sample track. Same guard the search and see-all screens carry.
    if (src == 'youtube' && item.type != 'song') {
      context.openYtItem(item, hero: hero);
      return;
    }
    switch (item.type) {
      case 'song':
        // Songs play at once. The label is the section's heading so the
        // player header reads naturally ("SINGLES · Arijit Singh").
        ref
            .read(appStateProvider)
            .playApiSong(item, sourceLabel: section.heading.toUpperCase());
      case 'album':
      case 'playlist':
      case 'artist':
        context.openRef(DetailRef(item.type, item.id, source: src), hero: hero);
      case 'channel':
      case 'occasion':
        context.openOccasion(item);
      case 'radio':
      case 'radio_station':
        // Saavn quick-stations in channel responses ship with an empty id;
        // the featured-station creator falls back to `name`, so passing the
        // FeedItem through is enough.
        startRadioStation(ref, item, provider: src);
    }
  }
}

/// A shelf tile: square cover (or a circle for an artist) with its title and
/// subtitle underneath.
class ShelfTile extends StatelessWidget {
  const ShelfTile({
    super.key,
    required this.item,
    required this.width,
    required this.colors,
    this.round = false,
    this.subtitle,
    this.heroTag,
  });

  final FeedItem item;
  final double width;
  final SunohColors colors;
  final bool round;

  /// Flies this cover into the page it opens (widgets/cover_hero.dart).
  final String? heroTag;

  /// Overrides the item's own display subtitle (YouTube rows show only what
  /// YouTube sent, never the fallbacks).
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final sub = subtitle ?? item.displaySubtitle ?? '';
    final align = round ? TextAlign.center : TextAlign.start;
    return Column(
      crossAxisAlignment: round
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        CoverHero(
          tag: heroTag,
          id: item.id,
          imageUrl: item.artwork,
          size: width,
          radius: round ? 999 : SunohRadius.tile,
        ),
        const SizedBox(height: 9),
        Text(
          item.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: align,
          style: SunohType.sans(
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
            color: colors.fg,
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
              color: colors.fgDim,
              height: 1.35,
            ),
          ),
      ],
    );
  }
}
