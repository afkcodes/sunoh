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

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dto.dart';
import '../providers/app_state_provider.dart';
import '../router/router.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/ui.dart';
import 'cover_tile.dart';

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
    if (!sections.any((s) => s.items.isNotEmpty)) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final section in sections)
          if (section.items.isNotEmpty) ...[
            const SizedBox(height: 30),
            SectionHeader(
              title: section.heading,
              colors: colors,
              eyebrowText: 'YOUTUBE MUSIC',
            ),
            _Shelf(
              items: section.items,
              heading: section.heading,
              colors: colors,
            ),
          ],
      ],
    );
  }
}

class _Shelf extends ConsumerWidget {
  const _Shelf({
    required this.items,
    required this.heading,
    required this.colors,
  });

  final List<FeedItem> items;
  final String heading;
  final SunohColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CoverShelf(
      // The first covers of the full list, indexed in place: the index is
      // then the item's position in the queue a song tap plays.
      itemCount: math.min(items.length, _kPreviewCount),
      itemBuilder: (context, i) {
        final item = items[i];
        // Artists read as people, everything else as artwork — the same rule
        // the home feed follows, so a shelf does not change shape between
        // tabs.
        final round = item.type == 'artist';
        return CoverTile(
          cover: SunohArt(
            id: item.id,
            size: kCoverTileWidth,
            radius: round ? 999 : SunohRadius.tile,
            imageUrl: _art(item),
            shadow: false,
          ),
          title: item.title,
          subtitle: item.subtitle,
          round: round,
          colors: colors,
          // A song plays; an album, playlist or artist opens. Routing every
          // tap through openYtItem was the bug: its default case is `break`,
          // so tapping a liked song did nothing at all — no navigation, no
          // playback, and nothing in the log to show for it.
          onTap: () {
            if (item.type == 'song') {
              ref
                  .read(appStateProvider)
                  .playApiQueue(items, i, sourceLabel: 'YOUTUBE · $heading');
            } else {
              context.openYtItem(item);
            }
          },
        );
      },
    );
  }
}

/// The largest artwork the item carries, or null to fall back to the painted
/// placeholder. YouTube ships several sizes; the biggest is the one that still
/// looks right on a high-density screen.
///
/// Not `.last`: that is only the biggest while the API happens to list sizes
/// ascending. [FeedItem.artwork] ranks by the labelled dimension.
String? _art(FeedItem item) => item.artwork;
