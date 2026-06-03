// Audiobooks tab — multi-section feed from /audiobooks/home.
//
// Visually shares language with the radio + podcast tabs: a top-of-tab
// header strip (eyebrow + "Browse" chip), then a stream of horizontal
// strips of squircle tiles. Two tile kinds:
//   - audiobook tile (cover + title + author)
//   - audiobook_category tile (chip with name + count)
//
// Backend serves enriched data (cover + author scraped per book during
// home aggregation) so cold tab open is one round-trip; cache means
// subsequent opens are instant.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../api/dto.dart';
import '../providers/audiobook_provider.dart';
import '../router/router.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/ui.dart';

class AudiobooksTab extends ConsumerWidget {
  const AudiobooksTab({super.key, required this.colors});
  final SunohColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    final async = ref.watch(audiobookHomeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              eyebrow('AUDIOBOOKS', c.fgMute, size: 10, letterSpacing: 1.4),
              GestureDetector(
                onTap: () => context.openAudiobookCategories(),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: squircleDecoration(
                    radius: 999,
                    color: c.surface,
                    borderColor: c.line,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(SolarIconsOutline.widget,
                          size: 12, color: c.fgDim),
                      const SizedBox(width: 6),
                      Text('Browse',
                          style: SunohType.sans(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: c.fgDim)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: async.when(
            data: (sections) {
              if (sections.isEmpty) {
                return Center(
                  child: Text('No audiobooks yet',
                      style: SunohType.sans(fontSize: 13, color: c.fgMute)),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: sections.length,
                itemBuilder: (ctx, i) =>
                    _AudiobookSection(section: sections[i], colors: c),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Couldn’t load audiobooks. Try again later.',
                  textAlign: TextAlign.center,
                  style: SunohType.sans(fontSize: 13, color: c.fgMute),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One horizontal strip — heading + scrolling row of tiles. Tile type
/// is decided per-item: `audiobook_category` renders as a chip, anything
/// else (`audiobook`) renders as a cover tile.
class _AudiobookSection extends StatelessWidget {
  const _AudiobookSection({required this.section, required this.colors});
  final HomeSection section;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final items = section.items;
    if (items.isEmpty) return const SizedBox.shrink();
    final isCategoryStrip =
        items.isNotEmpty && items.first.type == 'audiobook_category';
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              section.heading,
              style: SunohType.sans(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: c.fg,
                letterSpacing: -0.2,
              ),
            ),
          ),
          SizedBox(
            height: isCategoryStrip ? 56 : 184,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (ctx, i) {
                final it = items[i];
                if (it.type == 'audiobook_category') {
                  return _CategoryChip(item: it, colors: c);
                }
                return _AudiobookTile(item: it, colors: c);
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Cover + title + author. Square 120×120 cover (squircle 14) so two
/// fit comfortably side-by-side on a mid-density phone, with title +
/// author below in two reserved lines so adjacent tiles stay aligned.
class _AudiobookTile extends StatelessWidget {
  const _AudiobookTile({required this.item, required this.colors});
  final FeedItem item;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return GestureDetector(
      onTap: () => context.openAudiobook(item.id, item: item),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 120,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            squircleClip(
              radius: 14,
              child: SunohArt(
                id: item.id,
                imageUrl: item.artwork,
                size: 120,
                radius: 14,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: SunohType.sans(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: c.fg,
                height: 1.2,
              ),
            ),
            if ((item.subtitle ?? '').isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                item.subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SunohType.sans(
                  fontSize: 11,
                  color: c.fgMute,
                  height: 1.2,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Genre chip — name + count badge. Used in the "Browse genres" strip
/// at the top of the home; tap → per-category screen.
class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.item, required this.colors});
  final FeedItem item;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final idNum = int.tryParse(item.id) ?? 0;
    return GestureDetector(
      onTap: () => context.openAudiobookCategory(idNum, name: item.title),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: squircleDecoration(
          radius: 12,
          color: c.surface,
          borderColor: c.line,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              item.title,
              style: SunohType.sans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: c.fg,
              ),
            ),
            if ((item.subtitle ?? '').isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                item.subtitle!,
                style: SunohType.sans(fontSize: 11, color: c.fgMute),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
