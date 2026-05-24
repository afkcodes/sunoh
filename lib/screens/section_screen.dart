// SectionScreen — "See all" view: shows every item of a home-feed section in
// a 2-column squircle grid. Reached via context.push('<branch>/section', extra: section).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';

import '../api/dto.dart';
import '../data/models.dart';
import '../providers/app_state_provider.dart';
import '../router/router.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/ui.dart';

class SectionScreen extends ConsumerWidget {
  const SectionScreen({super.key, required this.section});
  final HomeSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final topInset = MediaQuery.of(context).padding.top;
    final isArtistGrid = section.items.every((it) => it.type == 'artist');

    return ColoredBox(
      color: c.bg,
      child: ListView(
        padding: EdgeInsets.only(top: topInset + 8, bottom: 140),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                IconBtn(
                    icon: SolarIconsOutline.altArrowLeft,
                    color: c.fg,
                    size: 22,
                    background: c.surface,
                    onTap: () => context.pop()),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Text(section.heading,
                style: SunohType.heading(
                    fontSize: 30, color: c.fg, height: 1.05, letterSpacing: -0.5)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              removeBottom: true,
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: section.items.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 22,
                  childAspectRatio: isArtistGrid ? 0.82 : 0.78,
                ),
                itemBuilder: (context, i) {
                  final item = section.items[i];
                  return GestureDetector(
                    onTap: () => _routeTap(context, ref, item),
                    behavior: HitTestBehavior.opaque,
                    child: isArtistGrid
                        ? _ArtistTile(item: item, colors: c)
                        : _CoverTile(item: item, colors: c),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _routeTap(BuildContext context, WidgetRef ref, FeedItem item) {
    final s = ref.read(appStateProvider);
    final src = item.source ?? section.source;
    switch (item.type) {
      case 'album':
        context.openRef(DetailRef('album', item.id, source: src));
        break;
      case 'playlist':
        context.openRef(DetailRef('playlist', item.id, source: src));
        break;
      case 'artist':
        context.openRef(DetailRef('artist', item.id, source: src));
        break;
      case 'song':
        s.flashToast('Playback coming soon');
        break;
      default:
        s.flashToast(item.type);
    }
  }
}

class _CoverTile extends StatelessWidget {
  const _CoverTile({required this.item, required this.colors});
  final FeedItem item;
  final SunohColors colors;
  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: SunohArt(
              id: item.id, width: double.infinity, radius: 10, imageUrl: item.artwork),
        ),
        const SizedBox(height: 10),
        Text(item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SunohType.sans(
                fontSize: 14, fontWeight: FontWeight.w500, color: c.fg, height: 1.2)),
        if ((item.displaySubtitle ?? '').isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(item.displaySubtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SunohType.sans(fontSize: 12, color: c.fgMute)),
        ],
      ],
    );
  }
}

class _ArtistTile extends StatelessWidget {
  const _ArtistTile({required this.item, required this.colors});
  final FeedItem item;
  final SunohColors colors;
  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: SunohArt(
              id: item.id, width: double.infinity, radius: 999, imageUrl: item.artwork),
        ),
        const SizedBox(height: 10),
        Text(item.title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: SunohType.sans(
                fontSize: 13, fontWeight: FontWeight.w500, color: c.fg, height: 1.2)),
      ],
    );
  }
}
