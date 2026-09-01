// The Library tab's window onto a signed-in YouTube account.
//
// Same shape as the on-device section directly above it, and for the same
// reason: covers you recognise are what make a shelf read as yours. A row of
// text links would technically list the same playlists and feel like someone
// else's data borrowed for the afternoon.
//
// Absent entirely when signed out. Not a prompt, not an empty state — the app
// works without an account, and a permanent advert for signing in would say
// otherwise. The invitation lives in Settings, once.

import 'package:flutter/material.dart';

import '../api/dto.dart';
import '../router/router.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/ui.dart';

/// Covers per shelf before the row stops building cards nobody scrolled to.
const int _kPreviewCount = 12;

class LibraryYouTubeSection extends StatelessWidget {
  const LibraryYouTubeSection({
    super.key,
    required this.sections,
    required this.colors,
  });

  final List<HomeSection> sections;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    final withItems = sections.where((s) => s.items.isNotEmpty).toList();
    if (withItems.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final section in withItems) ...[
          SectionHeader(
            title: section.heading,
            colors: colors,
            eyebrowText: 'YOUTUBE MUSIC',
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          ),
          _Strip(items: section.items, colors: colors),
          const SizedBox(height: 22),
        ],
      ],
    );
  }
}

class _Strip extends StatelessWidget {
  const _Strip({required this.items, required this.colors});

  final List<FeedItem> items;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    const width = 116.0;
    final shown = items.take(_kPreviewCount).toList();
    return SizedBox(
      height: width + 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: shown.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) => _Tile(item: shown[i], colors: colors),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.item, required this.colors});

  final FeedItem item;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    const width = 116.0;
    // Artists read as people, everything else as artwork — the same rule the
    // home feed follows, so a shelf does not change shape between tabs.
    final round = item.type == 'artist';
    return GestureDetector(
      onTap: () => context.openYtItem(item),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (round)
              ClipOval(
                child: SunohArt(
                  id: item.id,
                  size: width,
                  radius: 0,
                  imageUrl: _art(item),
                ),
              )
            else
              SunohArt(
                id: item.id,
                size: width,
                radius: 10,
                imageUrl: _art(item),
              ),
            const SizedBox(height: 8),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SunohType.sans(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: c.fg,
              ),
            ),
            if ((item.subtitle ?? '').isNotEmpty)
              Text(
                item.subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SunohType.sans(fontSize: 11, color: c.fgMute),
              ),
          ],
        ),
      ),
    );
  }
}

/// The largest artwork the item carries, or null to fall back to the painted
/// placeholder. YouTube ships several sizes; the biggest is the one that still
/// looks right on a high-density screen.
String? _art(FeedItem item) {
  if (item.image.isEmpty) return null;
  return item.image.last.link;
}
