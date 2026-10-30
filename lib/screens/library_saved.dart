// The Library tab's saved items — what the filter chips filter and the sort
// row orders. Split from library_screen.dart, which decides which items and
// in what order; this draws them.

import 'package:flutter/material.dart';

import '../api/dto.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/cover_hero.dart';
import '../widgets/ui.dart';
import 'cover_tile.dart';
import 'feed_tiles.dart';
import 'library_rows.dart';

/// The hero scope of Library's saved covers (`feedHeroTag`).
const String _kScope = 'library';

/// A tap on a saved item, with its cover when that cover flies.
typedef SavedTap = void Function(FeedItem item, CoverHeroRef? hero);

/// Saved albums, playlists, artists and liked songs, as the chip filters
/// them: a header, then big rows in list mode or a three-across cover grid.
class LibrarySavedList extends StatelessWidget {
  const LibrarySavedList({
    super.key,
    required this.heading,
    required this.emptyMessage,
    required this.items,
    required this.grid,
    required this.state,
    required this.colors,
    required this.onTap,
  });
  final String heading;
  final String emptyMessage;
  final List<FeedItem> items;
  final bool grid;
  final AppState state;
  final SunohColors colors;
  final SavedTap onTap;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final playingId = state.currentApiSong?.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 30),
        SectionHeader(title: heading, colors: c),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              emptyMessage,
              style: SunohType.sans(fontSize: 14, color: c.fgDim, height: 1.45),
            ),
          )
        else if (grid)
          _GridList(items: items, colors: c, onTap: onTap)
        else
          for (final it in items)
            LibraryRow(
              art: CoverHero(
                tag: feedHeroTag(_kScope, items, it),
                id: it.id,
                imageUrl: it.artwork,
                size: 56,
                radius: it.type == 'artist' ? 999 : SunohRadius.row,
              ),
              title: it.title,
              subtitle: _subFor(it),
              colors: c,
              onTap: () => onTap(it, feedHeroRef(_kScope, items, it, 56)),
              downloadId: it.type == 'song' ? it.id : null,
              playing: it.type == 'song' && it.id == playingId,
              animate: state.isPlaying,
            ),
      ],
    );
  }
}

class _GridList extends StatelessWidget {
  const _GridList({
    required this.items,
    required this.colors,
    required this.onTap,
  });
  final List<FeedItem> items;
  final SunohColors colors;
  final SavedTap onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, box) {
          // Three across; each cell is a cover tile at the column's width.
          final w = (box.maxWidth - 2 * 12) / 3;
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 16,
              mainAxisExtent: w + CoverTile.textHeight(context),
            ),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final it = items[i];
              final round = it.type == 'artist';
              return CoverTile(
                width: w,
                cover: CoverHero(
                  tag: feedHeroTag(_kScope, items, it),
                  id: it.id,
                  imageUrl: it.artwork,
                  size: w,
                  radius: round ? 999 : SunohRadius.tile,
                ),
                title: it.title,
                subtitle: _subFor(it),
                round: round,
                colors: colors,
                onTap: () => onTap(it, feedHeroRef(_kScope, items, it, w)),
              );
            },
          );
        },
      ),
    );
  }
}

/// Subtitle picker — uses the FeedItem's displaySubtitle (which falls
/// through artists → subtitle → kind label) but skips the literal
/// "Song" / "Album" / etc. fallbacks so library rows don't read as
/// broken under every entry.
String _subFor(FeedItem item) {
  final fromApi = (item.subtitle ?? '').trim();
  if (fromApi.isNotEmpty) return fromApi;
  final names = (item.artists ?? const <ApiArtistRef>[])
      .map((a) => a.name.trim())
      .where((n) => n.isNotEmpty)
      .take(2)
      .toList();
  if (names.isNotEmpty) return names.join(', ');
  switch (item.type) {
    case 'song':
      return 'Song';
    case 'album':
      return 'Album';
    case 'playlist':
      return 'Playlist';
    case 'artist':
      return 'Artist';
    default:
      return '';
  }
}
