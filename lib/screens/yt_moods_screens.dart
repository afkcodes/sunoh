// YouTube Music browsing: the moods & genres chip index, and one mood/genre
// category.
//
// Split out of ytmusic_screens.dart (464 lines) along the seam it already
// had: that file opens one playlist or artist, this one browses.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dto.dart';
import '../api/ytmusic_api.dart';
import '../providers/app_state_provider.dart';
import '../providers/ytmusic_provider.dart';
import '../router/router.dart';
import '../theme/tokens.dart';
import '../widgets/motion.dart';
import '../widgets/ui.dart';
import 'detail_chrome.dart';
import 'detail_shelf.dart';
import 'feed_tiles.dart';
import 'yt_scaffold.dart';

// ── Moods & genres index ───────────────────────────────────────────────────

class YtMoodsScreen extends ConsumerWidget {
  const YtMoodsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final async = ref.watch(ytMusicMoodsProvider);

    return async.when(
      loading: () => YtScaffold(
        title: 'Moods & genres',
        colors: c,
        children: [ytLoading(c)],
      ),
      error: (e, _) => YtScaffold(
        title: 'Moods & genres',
        colors: c,
        children: [ytError(c, 'Couldn’t load moods & genres.')],
      ),
      data: (groups) => YtScaffold(
        title: 'Moods & genres',
        colors: c,
        children: [
          // Entrance, not a bare FadeSlideIn: these sit in a lazy list, and
          // a group scrolled away and back would otherwise fade in again.
          for (var i = 0; i < groups.length; i++)
            Entrance(
              index: i,
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, i == 0 ? 0 : 30, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    eyebrow(
                      groups[i].title,
                      c.fgMute,
                      size: 10.5,
                      letterSpacing: 0.84,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final chip in groups[i].chips)
                          YtCategoryChipTile(chip: chip, colors: c),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One mood/genre pill. YouTube supplies a stripe colour per chip; using it
/// as a left accent keeps a 38-item genre grid scannable instead of a wall
/// of identical pills.
class YtCategoryChipTile extends StatelessWidget {
  const YtCategoryChipTile({
    super.key,
    required this.chip,
    required this.colors,
    this.width,
  });
  final YtCategoryChip chip;
  final SunohColors colors;

  /// Fixed width, used by the home grid so columns line up. Null lets the
  /// tile size to its label (the wrapped index screen).
  final double? width;

  /// Chip height. Shared with [kYtChipRowGap] so the home grid can compute
  /// its own height without guessing.
  static const double height = 44;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final stripe = chip.color == null ? c.accent : Color(chip.color!);
    return GestureDetector(
      onTap: () => context.openYtCategory(
        browseId: chip.browseId,
        params: chip.params,
        name: chip.title,
      ),
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: width,
        height: height,
        decoration: squircleDecoration(
          radius: SunohRadius.card,
          color: c.surface2,
        ),
        child: Row(
          mainAxisSize: width == null ? MainAxisSize.min : MainAxisSize.max,
          children: [
            // YouTube ships a stripe colour per category; using it keeps a
            // 49-chip grid scannable instead of a wall of identical pills.
            Container(
              width: 4,
              height: height,
              decoration: BoxDecoration(
                color: stripe,
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(12),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                chip.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: SunohType.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: c.fg,
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}

/// Vertical gap between chip rows in the home grid.
const double kYtChipRowGap = 10;

// ── One category ───────────────────────────────────────────────────────────

class YtCategoryScreen extends ConsumerWidget {
  const YtCategoryScreen({
    super.key,
    required this.browseId,
    required this.params,
    this.name,
  });
  final String browseId;
  final String params;
  final String? name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final async = ref.watch(
      ytMusicCategoryProvider((browseId: browseId, params: params)),
    );

    return async.when(
      loading: () => YtScaffold(
        title: name ?? 'Browse',
        colors: c,
        children: [ytLoading(c)],
      ),
      error: (e, _) => YtScaffold(
        title: name ?? 'Browse',
        colors: c,
        children: [ytError(c, 'Couldn’t load this category.')],
      ),
      data: (sections) => YtScaffold(
        title: name ?? 'Browse',
        colors: c,
        children: [
          if (sections.isEmpty) ytError(c, 'Nothing here right now.'),
          for (final section in sections) _YtShelf(section: section, colors: c),
        ],
      ),
    );
  }
}

/// One category section: header and a lazy row of tiles. Lazy because a
/// YouTube category section can carry dozens of items. Every tap routes
/// through openYtItem — these are browse ids sunoh-api can't resolve.
class _YtShelf extends StatelessWidget {
  const _YtShelf({required this.section, required this.colors});
  final HomeSection section;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    final items = section.items;
    return Padding(
      padding: const EdgeInsets.only(bottom: 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: section.heading, colors: colors),
          SizedBox(
            // Cover, gap, a title line and two subtitle lines.
            height:
                kShelfTile + 13 + MediaQuery.textScalerOf(context).scale(51),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) => Pressable(
                onTap: () => context.openYtItem(
                  items[i],
                  hero: feedHeroRef(
                    section.heading,
                    items,
                    items[i],
                    kShelfTile,
                  ),
                ),
                child: SizedBox(
                  width: kShelfTile,
                  child: ShelfTile(
                    item: items[i],
                    width: kShelfTile,
                    colors: colors,
                    subtitle: items[i].subtitle ?? '',
                    heroTag: feedHeroTag(section.heading, items, items[i]),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
