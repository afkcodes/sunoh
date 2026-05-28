// Per-category podcast list. Mounted at `/podcast-category/:slug` with
// the human-readable name passed via `extra` so the header reads
// nicely without a second fetch.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';

import '../api/dto.dart';
import '../data/models.dart';
import '../providers/app_state_provider.dart';
import '../providers/podcast_provider.dart';
import '../router/router.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/ui.dart';

class PodcastCategoryScreen extends ConsumerWidget {
  const PodcastCategoryScreen({super.key, required this.slug, this.name});
  final String slug;
  final String? name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final async = ref.watch(podcastsByCategoryProvider(slug));
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
                      onTap: () => context.pop()),
                  const SizedBox(width: 6),
                  Text(name ?? slug,
                      style: SunohType.heading(
                          fontSize: 22, color: c.fg, letterSpacing: -0.3)),
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
                    child: Text('Couldn’t load this category.\n$e',
                        textAlign: TextAlign.center,
                        style: SunohType.sans(
                            fontSize: 13, color: c.fgMute)),
                  ),
                ),
                data: (shows) => shows.isEmpty
                    ? Center(
                        child: Text('No podcasts in this category.',
                            style: SunohType.sans(
                                fontSize: 13, color: c.fgMute)),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 140),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 14,
                          childAspectRatio: 0.78,
                        ),
                        itemCount: shows.length,
                        itemBuilder: (context, i) =>
                            _ShowTile(show: shows[i], colors: c),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShowTile extends StatelessWidget {
  const _ShowTile({required this.show, required this.colors});
  final FeedItem show;
  final SunohColors colors;
  @override
  Widget build(BuildContext context) {
    final c = colors;
    return GestureDetector(
      onTap: () =>
          context.openRef(DetailRef('podcast', show.id, source: show.source)),
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          squircleClip(
            radius: 10,
            child: AspectRatio(
              aspectRatio: 1,
              child: SunohArt(
                id: show.id,
                imageUrl: show.artwork,
                size: 200,
                radius: 10,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(show.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: SunohType.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: c.fg,
                  height: 1.2)),
          if ((show.subtitle ?? '').isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(show.subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SunohType.sans(fontSize: 11.5, color: c.fgMute)),
          ],
        ],
      ),
    );
  }
}
