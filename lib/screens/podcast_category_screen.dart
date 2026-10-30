// Per-category podcast list. Mounted at `/podcast-category/:slug` with
// the human-readable name passed via `extra` so the bar reads nicely
// without a second fetch. The shows are a two-column grid of the same
// cover tiles every shelf uses.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dto.dart';
import '../data/models.dart';
import '../providers/app_state_provider.dart';
import '../providers/podcast_provider.dart';
import '../router/router.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/motion.dart';
import 'cover_tile.dart';
import 'sub_page_bar.dart';

class PodcastCategoryScreen extends ConsumerWidget {
  const PodcastCategoryScreen({super.key, required this.slug, this.name});
  final String slug;
  final String? name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(appStateProvider).colors;
    final async = ref.watch(podcastsByCategoryProvider(slug));
    return ColoredBox(
      color: c.bg,
      child: Column(
        children: [
          SubPageBar(title: name ?? slug, colors: c),
          Expanded(
            child: async.when(
              loading: () => Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: c.fgDim,
                  ),
                ),
              ),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Couldn’t load this category.\n$e',
                    textAlign: TextAlign.center,
                    style: SunohType.sans(fontSize: 13, color: c.fgMute),
                  ),
                ),
              ),
              data: (shows) => shows.isEmpty
                  ? Center(
                      child: Text(
                        'No podcasts in this category.',
                        style: SunohType.sans(fontSize: 13, color: c.fgMute),
                      ),
                    )
                  : FadeSlideIn(
                      child: CoverGrid(
                        count: shows.length,
                        tile: (context, i, w) =>
                            _ShowTile(show: shows[i], width: w, colors: c),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShowTile extends StatelessWidget {
  const _ShowTile({
    required this.show,
    required this.width,
    required this.colors,
  });
  final FeedItem show;
  final double width;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    return CoverTile(
      width: width,
      cover: SunohArt(
        id: show.id,
        imageUrl: show.artwork,
        size: width,
        radius: SunohRadius.tile,
        shadow: false,
      ),
      title: show.title,
      subtitle: show.subtitle,
      colors: colors,
      onTap: () =>
          context.openRef(DetailRef('podcast', show.id, source: show.source)),
    );
  }
}
