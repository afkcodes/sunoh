// Per-category audiobook listing.
//
// The /audiobooks/by-category endpoint returns skeleton FeedItems
// (title + slug, no cover/author). Each tile lazy-enriches via
// audiobookDetailProvider(slug) as it builds — the provider has 24 h
// keepAlive so revisiting the category doesn't refetch.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      audiobooksByCategoryProvider(
        AudiobookCategoryKey(id: id),
      ),
    );

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(SolarIconsOutline.altArrowLeft, color: c.fg),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          name ?? 'Genre',
          style: SunohType.sans(
              fontSize: 16, fontWeight: FontWeight.w600, color: c.fg),
        ),
      ),
      body: async.when(
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Text('No books in this genre',
                  style: SunohType.sans(fontSize: 13, color: c.fgMute)),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 18,
              childAspectRatio: 0.62,
            ),
            itemCount: items.length,
            itemBuilder: (ctx, i) =>
                _LazyTile(seed: items[i], colors: c),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Couldn’t load this genre. Try again later.',
              textAlign: TextAlign.center,
              style: SunohType.sans(fontSize: 13, color: c.fgMute),
            ),
          ),
        ),
      ),
    );
  }
}

/// Skeleton tile that swaps in the enriched cover + author once
/// audiobookDetailProvider resolves. While the detail fetch is in
/// flight, shows the slug-derived placeholder + title only.
class _LazyTile extends ConsumerWidget {
  const _LazyTile({required this.seed, required this.colors});
  final FeedItem seed;
  final SunohColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    final detailAsync = ref.watch(audiobookDetailProvider(seed.id));
    final enriched = detailAsync.value;
    final cover = enriched?.cover ?? seed.artwork;
    final author = enriched?.author ?? seed.subtitle;
    return GestureDetector(
      onTap: () => context.openAudiobook(seed.id, item: seed),
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: squircleClip(
              radius: 12,
              child: SunohArt(
                id: seed.id,
                imageUrl: cover,
                size: 112,
                radius: 12,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            seed.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: SunohType.sans(
              fontSize: 12,
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
              style: SunohType.sans(
                fontSize: 10.5,
                color: c.fgMute,
                height: 1.2,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
