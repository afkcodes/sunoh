// Radio tab — country-aware live-stream catalog from /radios/home.
//
// Visually distinct from PodcastsTab:
//   - Tiles are SQUARE LOGOS, not "labeled cards". Radio station logos
//     are typically logotype-on-solid-background and don't benefit from
//     the bottom-gradient title overlay podcast covers use. The title
//     sits BELOW the cover instead.
//   - Tap = play (PlayMode.live). No detail screen — live streams have
//     no metadata browse, the player itself adapts (see [[sunoh-audio]]
//     and `expanded_player.dart` for the LIVE-mode UI).
//
// Country comes from the device locale; the backend has its own
// IP-geo fallback if the locale doesn't carry one.
//
// (Earlier incarnation was a Stateful FM-dial mockup ported from
// radio.jsx — long since unused; this file replaces it wholesale.)

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../api/dto.dart';
import '../audio/audio_handler.dart' show PlayMode;
import '../providers/app_state_provider.dart';
import '../providers/radio_provider.dart';
import '../router/router.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/ui.dart';

class RadioTab extends ConsumerWidget {
  const RadioTab({super.key, required this.colors});
  final SunohColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    final country =
        PlatformDispatcher.instance.locale.countryCode?.toUpperCase();
    final async = ref.watch(radioHomeProvider(country));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Eyebrow + "Browse genres" chip on the right. Same 20-px
        // gutter the podcasts tab uses.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              eyebrow('RADIO', c.fgMute, size: 10, letterSpacing: 1.4),
              GestureDetector(
                onTap: () => context.openRadioGenres(),
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
        async.when(
          loading: () => _RadioSkeleton(colors: c),
          error: (e, _) => _RadioErrorState(colors: c, message: '$e'),
          data: (sections) {
            if (sections.isEmpty) return _RadioEmpty(colors: c);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < sections.length; i++) ...[
                  _RadioSection(
                      section: sections[i],
                      colors: c,
                      featured: i == 0),
                  if (i < sections.length - 1) const SizedBox(height: 32),
                  // Drop the genres preview after the featured section
                  // for the same discovery-aid reason podcasts use the
                  // categories strip after Trending.
                  if (i == 0) ...[
                    const _GenresPreview(),
                    const SizedBox(height: 32),
                  ],
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}

/// One horizontally-scrolling row of station tiles. Featured (first)
/// section gets bigger tiles, same convention as music + podcasts home.
class _RadioSection extends ConsumerWidget {
  const _RadioSection({
    required this.section,
    required this.colors,
    this.featured = false,
  });
  final HomeSection section;
  final SunohColors colors;
  final bool featured;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    final items = section.items;
    final width = featured ? 180.0 : 140.0;
    // height = cover (square) + spacing + 2 lines of caption.
    final height = width + 48;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: section.heading, colors: c),
        SizedBox(
          height: height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, i) => _RadioTile(
              item: items[i],
              colors: c,
              width: width,
            ),
          ),
        ),
      ],
    );
  }
}

/// Square-logo tile. Tap → play live; no detail screen.
class _RadioTile extends ConsumerWidget {
  const _RadioTile({
    required this.item,
    required this.colors,
    required this.width,
  });
  final FeedItem item;
  final SunohColors colors;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    final s = ref.read(appStateProvider);
    return GestureDetector(
      onTap: () => s.playApiQueue(
        [item],
        0,
        sourceLabel: 'RADIO · ${item.title}',
        mode: PlayMode.live,
      ),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            squircleClip(
              radius: 14,
              child: SunohArt(
                id: item.id,
                imageUrl: item.artwork,
                size: width,
                radius: 14,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.title,
              maxLines: 1,
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

/// Compact 2-row grid of genre chips — top 8 from the facet endpoint
/// with a "See all" CTA opening the full taxonomy. Lives between the
/// featured section and the rest of the genre rows.
class _GenresPreview extends ConsumerWidget {
  const _GenresPreview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final accent = s.resolvedAccent;
    final async = ref.watch(radioGenresProvider);
    final genres = async.asData?.value ?? const <RadioFacet>[];
    if (genres.isEmpty) return const SizedBox.shrink();
    final top = genres.take(8).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Genres',
                style: SunohType.heading(
                    fontSize: 17, color: c.fg, letterSpacing: -0.2),
              ),
              GestureDetector(
                onTap: () => context.openRadioGenres(),
                behavior: HitTestBehavior.opaque,
                child: Text(
                  'See all',
                  style: SunohType.sans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: top.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) => _GenreChip(
              facet: top[i],
              colors: c,
              accent: accent,
            ),
          ),
        ),
      ],
    );
  }
}

/// Single genre chip — bigger than a typical chip; doubles as a "genre
/// card" that surfaces the count.
class _GenreChip extends StatelessWidget {
  const _GenreChip({
    required this.facet,
    required this.colors,
    required this.accent,
  });
  final RadioFacet facet;
  final SunohColors colors;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return GestureDetector(
      onTap: () => context.openRadioGenre(facet.value),
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 140,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: squircleDecoration(
          radius: 12,
          color: Color.alphaBlend(accent.withValues(alpha: 0.10), c.surface),
          borderColor: accent.withValues(alpha: 0.20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              titleCase(facet.value),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SunohType.heading(
                fontSize: 14,
                color: c.fg,
                letterSpacing: -0.2,
              ),
            ),
            Text(
              '${facet.count} stations',
              style: SunohType.sans(fontSize: 11, color: c.fgMute),
            ),
          ],
        ),
      ),
    );
  }
}

/// Title-cased genre label — "hip-hop" → "Hip-Hop", "top40" → "Top40".
/// Used by genre chips + the genre-detail screen header.
String titleCase(String s) {
  if (s.isEmpty) return s;
  return s.split(RegExp(r'\s+')).map((w) {
    if (w.isEmpty) return w;
    return w[0].toUpperCase() + w.substring(1).toLowerCase();
  }).join(' ');
}

class _RadioSkeleton extends StatelessWidget {
  const _RadioSkeleton({required this.colors});
  final SunohColors colors;
  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < 3; i++) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Container(
              width: 120,
              height: 14,
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          SizedBox(
            height: 188,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: 5,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (_, _) => Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ],
    );
  }
}

class _RadioErrorState extends StatelessWidget {
  const _RadioErrorState({required this.colors, required this.message});
  final SunohColors colors;
  final String message;
  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        'Couldn’t load radio stations.\n$message',
        style: SunohType.sans(fontSize: 13, color: c.fgMute),
      ),
    );
  }
}

class _RadioEmpty extends StatelessWidget {
  const _RadioEmpty({required this.colors});
  final SunohColors colors;
  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        'No radio stations yet.',
        style: SunohType.sans(fontSize: 13, color: c.fgMute),
      ),
    );
  }
}
