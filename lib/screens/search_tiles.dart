// The leaf widgets the search screen renders: a result row, the top-result
// card, a trending row, and a recent search.
//
// Split out of `search_screen.dart`, which was 1115 lines. These know how to
// draw one thing and nothing about the screen's state; the tile, row and
// browse-tile shapes themselves are the feed's (feed_tiles.dart), so a
// result looks like the same song on Home.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:remixicon/remixicon.dart';

import '../api/dto.dart';
import '../data/models.dart';
import '../overlays/track_menu_sheet.dart';
import '../providers/app_state_provider.dart';
import '../router/router.dart';
import '../theme/tokens.dart';
import '../widgets/cover_hero.dart';
import '../widgets/motion.dart';
import '../widgets/ui.dart';
import 'feed_row.dart';
import 'feed_tiles.dart';

final Expando<String> _subtitles = Expando('search subtitle');

/// Compact subtitle line — only *meaningful* text, so the row can drop the
/// line entirely when nothing useful is available. Generic type labels
/// ("Song" / "Album") are deliberately suppressed because saavn search
/// returns subtitle:null + artists:[] for many songs and showing the bare
/// word "Song" under every row reads as broken. Memoised on the item.
String resultSubtitle(FeedItem item) => _subtitles[item] ??= _subtitleFor(item);

String _subtitleFor(FeedItem item) {
  final fromApi = (item.subtitle ?? '').trim();
  if (fromApi.isNotEmpty) return fromApi;
  final names = (item.artists ?? const [])
      .map((a) => a.name.trim())
      .where((n) => n.isNotEmpty)
      .take(2)
      .toList();
  return names.join(', ');
}

/// Where a tap on a search result goes. Shared by the rows, the top-result
/// card and the trending tiles so the three cannot disagree.
void openResult(
  BuildContext context,
  FeedItem item, {
  required String? sectionSource,
  required void Function(FeedItem song) onPlay,
  CoverHeroRef? hero,
}) {
  final source = item.source ?? sectionSource;
  // YouTube ids are browse ids that sunoh-api can't resolve — route them to
  // the YouTube screens instead.
  if (source == 'youtube' && item.type != 'song') {
    context.openYtItem(item, hero: hero);
    return;
  }
  switch (item.type) {
    case 'song':
      onPlay(item);
    case 'album':
    case 'playlist':
    case 'artist':
    case 'podcast':
      context.openRef(
        DetailRef(item.type, item.id, source: source),
        hero: hero,
      );
    default:
      // Unknown type — a no-op rather than a route somewhere invalid.
      break;
  }
}

/// One result: the feed's list row, with a duration and the track menu for
/// songs and a chevron for anything that opens a screen.
class ResultRow extends ConsumerWidget {
  const ResultRow({
    super.key,
    required this.colors,
    required this.item,
    required this.onTap,
    this.heroTag,
  });
  final SunohColors colors;
  final FeedItem item;
  final VoidCallback onTap;
  final String? heroTag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSong = item.type == 'song';
    // 0 not current, 1 current and paused, 2 current and playing — one int,
    // so the rows that are not current never rebuild on play/pause.
    final state = ref.watch(
      appStateProvider.select(
        (s) => s.currentApiSong?.id != item.id ? 0 : (s.isPlaying ? 2 : 1),
      ),
    );
    return FeedRow(
      item: item,
      colors: colors,
      onTap: onTap,
      heroTag: heroTag,
      subtitle: resultSubtitle(item),
      playing: state > 0,
      animateBars: state == 2,
      meta: isSong ? durationOf(item) : null,
      onMore: isSong
          ? () => showTrackMenuSheet(context, song: item, sourceLabel: 'SEARCH')
          : null,
      chevron: !isSong,
    );
  }
}

/// The top-result card's cover size.
const double kTopResultArt = 96;

/// The first result, as a card: big art, its kind, title and subtitle, and a
/// button saying whether a tap plays or opens. The card is the target.
class TopResultCard extends StatelessWidget {
  const TopResultCard({
    super.key,
    required this.item,
    required this.colors,
    required this.onTap,
    this.heroTag,
  });
  final FeedItem item;
  final SunohColors colors;
  final VoidCallback onTap;
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final sub = resultSubtitle(item);
    final isSong = item.type == 'song';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Pressable(
        onTap: onTap,
        child: DecoratedBox(
          decoration: squircleDecoration(
            radius: SunohRadius.card,
            color: c.surface,
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CoverHero(
                  tag: heroTag,
                  id: item.id,
                  imageUrl: item.artwork,
                  size: kTopResultArt,
                  radius: item.type == 'artist' ? 999 : SunohRadius.tile,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      eyebrow(
                        'Top result · ${labelFor(item.type)}',
                        c.fgMute,
                        size: 10.5,
                        letterSpacing: 0.84,
                        maxLines: 1,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: SunohType.heading(
                          fontSize: 22,
                          color: c.fg,
                          height: 1.15,
                        ),
                      ),
                      if (sub.isNotEmpty)
                        Text(
                          sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SunohType.sans(fontSize: 13, color: c.fgDim),
                        ),
                      const SizedBox(height: 10),
                      Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: c.accent,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isSong
                              ? PhosphorIconsFill.play
                              : RemixIcons.arrow_right_line,
                          size: 16,
                          color: c.onAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A trending section on the browse view: the feed's header and tile row.
/// Songs play where they are; everything else opens.
class TrendingRow extends ConsumerWidget {
  const TrendingRow({super.key, required this.section, required this.colors});
  final HomeSection section;
  final SunohColors colors;

  static String? _subtitle(FeedItem item) => item.displaySubtitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    final circles =
        section.items.isNotEmpty &&
        section.items.every((it) => it.type == 'artist');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: section.heading, colors: c),
        FeedTileRow(
          items: section.items.length > 10
              ? section.items.sublist(0, 10)
              : section.items,
          colors: c,
          circles: circles,
          // Artist circles carried only a name before and still do.
          subtitleOf: circles ? null : _subtitle,
          heroScope: section.heading,
          onTap: (item) => openResult(
            context,
            item,
            sectionSource: section.source,
            hero: feedHeroRef(section.heading, section.items, item, kTileWidth),
            // Songs play immediately — a song in a trending carousel never
            // opens a song-detail screen.
            onPlay: (song) => ref
                .read(appStateProvider)
                .playApiSong(
                  song,
                  sourceLabel: 'TRENDING · ${section.heading}',
                ),
          ),
        ),
      ],
    );
  }
}

/// A recent search: a clock in a square where a cover would be, then the
/// query. A tap runs it again.
class RecentRow extends StatelessWidget {
  const RecentRow({
    super.key,
    required this.query,
    required this.colors,
    required this.onTap,
  });
  final String query;
  final SunohColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Pressable(
      scale: 0.99,
      onTap: onTap,
      child: SizedBox(
        height: 52,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: squircleDecoration(
                  radius: SunohRadius.row,
                  color: c.surface2,
                ),
                child: Icon(RemixIcons.time_line, size: 18, color: c.fgMute),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  query,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SunohType.sans(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                    color: c.fg,
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
