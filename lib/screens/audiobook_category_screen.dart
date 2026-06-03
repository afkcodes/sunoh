// Per-genre audiobook listing.
//
// Same structural shell as PodcastCategoryScreen — header (back chip +
// heading) above a 2-col grid of cover tiles. The backend serves
// skeleton items (no cover/author); each tile lazy-enriches via
// audiobookDetailProvider(slug) as it builds. The provider has 24 h
// keepAlive so revisiting the genre stays warm.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';

import '../api/dto.dart';
import '../providers/app_state_provider.dart';
import '../providers/audiobook_provider.dart';
import '../router/router.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/ui.dart';

class AudiobookCategoryScreen extends ConsumerWidget {
  const AudiobookCategoryScreen({
    super.key,
    required this.id,
    this.name,
  });
  final int id;
  final String? name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final async = ref.watch(
      audiobooksByCategoryProvider(AudiobookCategoryKey(id: id)),
    );
    return ColoredBox(
      color: c.bg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  IconBtn(
                    icon: SolarIconsOutline.altArrowLeft,
                    color: c.fg,
                    size: 22,
                    onTap: () => context.pop(),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    name ?? 'Genre',
                    style: SunohType.heading(
                      fontSize: 22,
                      color: c.fg,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: async.when(
                loading: () => Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: c.fgDim),
                  ),
                ),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Couldn’t load this genre.\n$e',
                      textAlign: TextAlign.center,
                      style:
                          SunohType.sans(fontSize: 13, color: c.fgMute),
                    ),
                  ),
                ),
                data: (books) => books.isEmpty
                    ? Center(
                        child: Text('No books in this genre.',
                            style: SunohType.sans(
                                fontSize: 13, color: c.fgMute)),
                      )
                    : GridView.builder(
                        padding:
                            const EdgeInsets.fromLTRB(20, 0, 20, 140),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 14,
                          childAspectRatio: 0.78,
                        ),
                        itemCount: books.length,
                        itemBuilder: (context, i) =>
                            _AudiobookGridTile(seed: books[i], colors: c),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Two-up grid tile that lazy-loads cover + author from
/// [audiobookDetailProvider] when it builds. While the detail fetch is
/// in flight the painted SunohArt placeholder shows; once it resolves,
/// the Amazon CDN cover swaps in via [SunohArt.imageUrl].
class _AudiobookGridTile extends ConsumerWidget {
  const _AudiobookGridTile({required this.seed, required this.colors});
  final FeedItem seed;
  final SunohColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    final detail = ref.watch(audiobookDetailProvider(seed.id)).value;
    final cover = detail?.cover ?? seed.artwork;
    final author = detail?.author ?? seed.subtitle;
    return GestureDetector(
      onTap: () => context.openAudiobook(seed.id, item: seed),
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          squircleClip(
            radius: 10,
            child: AspectRatio(
              aspectRatio: 1,
              child: SunohArt(
                id: seed.id,
                imageUrl: cover,
                size: 200,
                radius: 10,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            seed.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: SunohType.sans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: c.fg,
              height: 1.2,
            ),
          ),
          if ((author ?? '').isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              author!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SunohType.sans(fontSize: 11.5, color: c.fgMute),
            ),
          ],
        ],
      ),
    );
  }
}
