// SectionScreen — "See all" view: every item of a home-feed section as a
// two-column grid of shelf tiles under a big page title. Reached via
// context.openSection(section).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dto.dart';
import '../data/models.dart';
import '../providers/app_state_provider.dart';
import '../router/router.dart';
import '../widgets/cover_hero.dart';
import '../widgets/motion.dart';
import 'detail_chrome.dart';
import 'detail_shelf.dart';
import 'feed_tiles.dart';

class SectionScreen extends ConsumerWidget {
  const SectionScreen({super.key, required this.section});
  final HomeSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final items = section.items;
    final round = items.every((it) => it.type == 'artist');
    // Two columns on the 16 gutter with the shelf's 12 gap. A tile is its
    // square cover, the 9 gap, a title line and — for anything but an
    // artist — two subtitle lines, at whatever size the user's text is.
    final tile = (MediaQuery.sizeOf(context).width - 32 - 12) / 2;
    final lines = MediaQuery.textScalerOf(context).scale(round ? 18 : 51);

    return DetailPage(
      colors: c,
      colour: c.bg,
      title: section.heading,
      solidAt: PageTitle.solidAt,
      builder: (_) => [
        SliverToBoxAdapter(
          child: PageTitle(colors: c, title: section.heading),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid.builder(
            itemCount: items.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 20,
              mainAxisExtent: tile + 9 + lines + 4,
            ),
            itemBuilder: (context, i) {
              final cell = Pressable(
                onTap: () => _routeTap(
                  context,
                  ref,
                  items[i],
                  feedHeroRef(_scope, items, items[i], tile),
                ),
                child: ShelfTile(
                  item: items[i],
                  width: tile,
                  colors: c,
                  round: round,
                  heroTag: feedHeroTag(_scope, items, items[i]),
                ),
              );
              return i < 9 ? Entrance(index: 1 + i, child: cell) : cell;
            },
          ),
        ),
      ],
    );
  }

  /// The grid's hero scope (`feedHeroTag`): its own, so a cover here never
  /// shares a tag with the same cover on the page this was opened from.
  String get _scope => 'see all ${section.heading}';

  void _routeTap(
    BuildContext context,
    WidgetRef ref,
    FeedItem item,
    CoverHeroRef? hero,
  ) {
    final s = ref.read(appStateProvider);
    final src = item.source ?? section.source;
    // YouTube ids are browse ids sunoh-api can't resolve.
    if (src == 'youtube' && item.type != 'song') {
      context.openYtItem(item, hero: hero);
      return;
    }
    switch (item.type) {
      case 'album' || 'playlist' || 'artist':
        final at = DetailRef(item.type, item.id, source: src);
        context.openRef(at, hero: hero);
      case 'song':
        // As on Home: the section's songs become the queue, from this one.
        final songs = [
          for (final it in section.items)
            if (it.type == 'song') it,
        ];
        s.playApiQueue(
          songs,
          songs.indexOf(item),
          sourceLabel: 'HOME · ${section.heading}',
        );
      default:
        s.flashToast(item.type);
    }
  }
}
