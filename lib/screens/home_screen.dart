// Home screen — sunoh wordmark + top tabs (Music / Radio / Podcasts). The
// Music tab consumes the live /music/home feed via Riverpod.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../api/dto.dart';
import '../data/models.dart';
import '../providers/app_state_provider.dart';
import '../providers/home_provider.dart';
import '../providers/palette_provider.dart';
import '../audio/radio_actions.dart';
import '../router/router.dart';
import '../widgets/update_banner.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/ui.dart';
import 'podcasts_tab.dart';
import 'radio_tab.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'sunoh.',
                style: SunohType.heading(
                  fontSize: 22,
                  color: c.fg,
                  letterSpacing: -0.5,
                ),
              ),
              IconBtn(
                icon: SolarIconsOutline.settings,
                color: c.fgDim,
                size: 18,
                width: 32,
                height: 32,
                onTap: () => context.openSettings(),
              ),
            ],
          ),
        ),
        _TopTabs(tab: s.topTab, onChange: s.setTopTab, colors: c),
        // Slim "Update available" ribbon — renders only when the published
        // manifest carries a strictly-newer version than this build, and
        // the user hasn't dismissed that exact version yet. Sits between
        // the tabs and the feed so it reads as a tab-level notice rather
        // than chrome wedged between the title and the tabs.
        const UpdateBanner(),
        const SizedBox(height: 22),
        TweenAnimationBuilder<double>(
          key: ValueKey('tab-${s.topTab}'),
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
          builder: (_, v, child) => Opacity(
            opacity: v,
            child: Transform.translate(
              offset: Offset(0, (1 - v) * 6),
              child: child,
            ),
          ),
          child: switch (s.topTab) {
            'Radio' => RadioTab(colors: c),
            'Podcasts' => PodcastsTab(colors: c),
            _ => MusicTab(colors: c),
          },
        ),
      ],
    );
  }
}

class _TopTabs extends StatelessWidget {
  const _TopTabs({
    required this.tab,
    required this.onChange,
    required this.colors,
  });
  final String tab;
  final ValueChanged<String> onChange;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    const opts = ['Music', 'Radio', 'Podcasts'];
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.line, width: 0.5)),
      ),
      child: Row(
        children: [
          for (final t in opts)
            Padding(
              padding: const EdgeInsets.only(right: 22),
              child: GestureDetector(
                onTap: () => onChange(t),
                child: _TabLabel(label: t, active: t == tab, colors: colors),
              ),
            ),
        ],
      ),
    );
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel({
    required this.label,
    required this.active,
    required this.colors,
  });
  final String label;
  final bool active;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: active
              ? SunohType.heading(
                  fontSize: 22,
                  color: colors.fg,
                  letterSpacing: -0.2,
                )
              : SunohType.sans(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: colors.fgMute,
                ),
        ),
        const SizedBox(height: 4),
        Container(
          height: 1.5,
          width: 28,
          color: active ? colors.accent : Colors.transparent,
        ),
      ],
    );
  }
}

// ── Music tab ──────────────────────────────────────────────────────────────
// Live data: fetches the unified /music/home feed and renders each section
// (preserves the design system — Gilroy, squircles, 40px inter-section gaps).
class MusicTab extends ConsumerWidget {
  const MusicTab({super.key, required this.colors});
  final SunohColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    final s = ref.watch(appStateProvider);
    final feedAsync = ref.watch(homeFeedProvider(s.selectedLanguagesCsv));
    final gap = 40 * s.density.scale;

    return feedAsync.when(
      loading: () => const _LoadingFeed(),
      error: (e, _) => _ErrorFeed(
        message: 'Couldn’t load the home feed.',
        detail: '$e',
        onRetry: () => ref.invalidate(homeFeedProvider(s.selectedLanguagesCsv)),
        colors: c,
      ),
      data: (sections) {
        final nonEmpty =
            sections.where((s) => s.items.isNotEmpty).toList();
        if (nonEmpty.isEmpty) {
          return _ErrorFeed(
            message: 'Nothing in the feed right now.',
            colors: c,
            onRetry: () => ref.invalidate(homeFeedProvider(s.selectedLanguagesCsv)),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < nonEmpty.length; i++) ...[
              if (i > 0) SizedBox(height: gap),
              // First section gets the big feature-tile treatment (matches the
              // prototype's "Editorial picks" hierarchy).
              _ApiSection(section: nonEmpty[i], colors: c, featured: i == 0),
            ],
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }
}

class _ApiSection extends ConsumerWidget {
  const _ApiSection({
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
    // Items that should render as round chips: artists + radio stations.
    final isCircleRow = section.items.isNotEmpty &&
        section.items.every((it) =>
            it.type == 'artist' ||
            it.type == 'radio_station' ||
            it.type == 'radio');
    // Channels (the Saavn "Browse" row) are a distinct shape — wide
    // rectangular tiles in a 3-row horizontal-scroll grid. Different
    // enough from regular cards/circles that they get their own renderer
    // entirely.
    final isChannelRow = section.items.isNotEmpty &&
        section.items.every((it) => it.type == 'channel');
    // Cap each row at 10 items; if there are more, show "See all →" linking
    // to the full section.
    final visible = section.items.take(10).toList();
    final hasMore = section.items.length > 10;

    if (isChannelRow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: section.heading,
            colors: c,
            onSeeAll: hasMore ? () => context.openSection(section) : null,
          ),
          _ChannelGrid(
            items: section.items.take(15).toList(),
            colors: c,
            sectionSource: section.source,
          ),
        ],
      );
    }
    // featured (first section) → big 220px tiles like the prototype's
    // Editorial picks. Circle rows stay round but a touch larger when featured.
    final width = isCircleRow
        ? (featured ? 120.0 : 96.0)
        : (featured ? 220.0 : 148.0);
    final gap = isCircleRow ? 18.0 : (featured ? 14.0 : 12.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: section.heading,
          colors: c,
          onSeeAll: hasMore ? () => context.openSection(section) : null,
        ),
        HCardRow<FeedItem>(
          items: visible,
          width: width,
          gap: gap,
          onTap: (item) => _routeTap(context, ref, item, section.source),
          builder: (item, w) => isCircleRow
              ? _ArtistCard(item: item, size: w, colors: c)
              : _CoverCard(item: item, width: w, colors: c, featured: featured),
        ),
      ],
    );
  }

  void _routeTap(
    BuildContext context,
    WidgetRef ref,
    FeedItem item,
    String? sectionSource,
  ) {
    final s = ref.read(appStateProvider);
    final src = item.source ?? sectionSource;
    switch (item.type) {
      case 'album':
        context.openRef(DetailRef('album', item.id, source: src));
        break;
      case 'playlist':
        context.openRef(DetailRef('playlist', item.id, source: src));
        break;
      case 'artist':
        // Pure artist tiles navigate to the artist screen. The
        // "Recommended Artist Stations" tiles are a separate concept
        // — they come back as `type='radio_station'` with
        // `stationType='artist'` (via the API's mapSaavnChannel
        // rebrand) and are caught by the radio_station case below.
        context.openRef(DetailRef('artist', item.id, source: src));
        break;
      case 'song':
        // Songs play immediately — home rows full of songs (Trending,
        // Popular, New Releases) should kick playback on tap, not navigate
        // to a non-existent "song detail" screen.
        s.playApiSong(item,
            sourceLabel: 'HOME · ${section.heading}');
        break;
      case 'radio_station':
      case 'radio':
        // Radio stations need a two-step session bootstrap (create
        // session → fetch first batch of songs). Shared with the channel
        // detail screen via lib/audio/radio_actions.dart so both tap
        // sources behave identically.
        startRadioStation(ref, item, provider: src);
        break;
      case 'channel':
        // Channels (the Saavn "Browse" row) aren't radio stations and
        // can't be opened via /music/radio/session — but the backend
        // routes them through the occasion detail endpoint just fine
        // (/music/occasions/<channelId>?provider=saavn returns the
        // expected sections). Re-use OccasionScreen for the layout.
        context.openOccasion(item);
        break;
      case 'occasion':
        context.openOccasion(item);
        break;
      default:
        s.flashToast(item.type);
    }
  }

}

class _CoverCard extends StatelessWidget {
  const _CoverCard({
    required this.item,
    required this.width,
    required this.colors,
    this.featured = false,
  });
  final FeedItem item;
  final double width;
  final SunohColors colors;
  final bool featured;
  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SunohArt(
          id: item.id,
          size: width,
          radius: featured ? 12 : 10,
          imageUrl: item.artwork,
        ),
        SizedBox(height: featured ? 10 : 8),
        Text(
          item.title,
          maxLines: featured ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          style: featured
              ? SunohType.heading(
                  fontSize: 18,
                  color: c.fg,
                  height: 1.15,
                  letterSpacing: -0.2,
                )
              : SunohType.sans(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: c.fg,
                  height: 1.2,
                ),
        ),
        if ((item.displaySubtitle ?? '').isNotEmpty) ...[
          SizedBox(height: featured ? 4 : 2),
          Text(
            item.displaySubtitle!,
            maxLines: featured ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: SunohType.sans(
              fontSize: featured ? 12.5 : 11.5,
              color: c.fgDim,
              height: featured ? 1.35 : 1.2,
            ),
          ),
        ],
      ],
    );
  }
}

class _ArtistCard extends StatelessWidget {
  const _ArtistCard({
    required this.item,
    required this.size,
    required this.colors,
  });
  final FeedItem item;
  final double size;
  final SunohColors colors;
  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Column(
      children: [
        SunohArt(
          id: item.id,
          size: size - 10,
          radius: 999,
          imageUrl: item.artwork,
        ),
        const SizedBox(height: 10),
        Text(
          item.title,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: SunohType.sans(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: c.fg,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

// Skeleton placeholder for the home feed — mirrors the real layout (one
// featured row + standard rows) and pulses so the wait feels intentional
// rather than stuck.
class _LoadingFeed extends StatelessWidget {
  const _LoadingFeed();
  @override
  Widget build(BuildContext context) {
    return const Pulse(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SkeletonSection(featured: true),
          SizedBox(height: 40),
          _SkeletonSection(),
          SizedBox(height: 40),
          _SkeletonSection(),
          SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _SkeletonSection extends StatelessWidget {
  const _SkeletonSection({this.featured = false});
  final bool featured;
  @override
  Widget build(BuildContext context) {
    final tileSize = featured ? 220.0 : 148.0;
    final tileCount = featured ? 2 : 4;
    final titleHeight = featured ? 16.0 : 13.0;
    final subHeight = featured ? 12.0 : 11.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
          child: SkeletonBar(height: 22, width: 180, radius: 6),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < tileCount; i++) ...[
                if (i > 0) SizedBox(width: featured ? 14 : 12),
                SizedBox(
                  width: tileSize,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBar(
                        height: tileSize,
                        width: tileSize,
                        radius: featured ? 12 : 10,
                      ),
                      SizedBox(height: featured ? 10 : 8),
                      SkeletonBar(
                        height: titleHeight,
                        width: tileSize * 0.85,
                        radius: 4,
                      ),
                      SizedBox(height: featured ? 4 : 2),
                      SkeletonBar(
                        height: subHeight,
                        width: tileSize * 0.55,
                        radius: 4,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorFeed extends StatelessWidget {
  const _ErrorFeed({
    required this.message,
    required this.colors,
    required this.onRetry,
    this.detail,
  });
  final String message;
  final String? detail;
  final SunohColors colors;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 80, 20, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: SunohType.heading(fontSize: 18, color: c.fg),
          ),
          if (detail != null) ...[
            const SizedBox(height: 8),
            Text(
              detail!,
              textAlign: TextAlign.center,
              style: SunohType.sans(fontSize: 12, color: c.fgMute),
            ),
          ],
          const SizedBox(height: 20),
          GestureDetector(
            onTap: onRetry,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: squircleDecoration(
                radius: 999,
                color: c.surface,
                borderColor: c.line,
              ),
              child: Text(
                'Try again',
                style: SunohType.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: c.fg,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Saavn-style "Browse" channels — 3-row horizontal-scroll grid of wide
/// rectangular tiles. Used when an entire section is channel-typed.
class _ChannelGrid extends StatelessWidget {
  const _ChannelGrid({
    required this.items,
    required this.colors,
    required this.sectionSource,
  });
  final List<FeedItem> items;
  final SunohColors colors;
  final String? sectionSource;

  // Layout sizing — kept as constants so the SizedBox height matches the
  // grid's actual row arithmetic exactly.
  static const double _tileH = 64;
  static const double _gap = 10;
  static const int _rows = 3;
  static const double _tileW = 180;

  @override
  Widget build(BuildContext context) {
    // GridView in horizontal mode: `crossAxisCount` is the ROW count.
    final totalHeight = _rows * _tileH + (_rows - 1) * _gap;
    return SizedBox(
      height: totalHeight,
      // No `physics:` override — `SunohScrollBehavior` (app-wide) owns scroll
      // feel. Earlier inline BouncingScrollPhysics ignored the global friction
      // tuning and made this row feel different from the rest of the app.
      child: GridView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _rows,
          // In a horizontal GridView, `childAspectRatio` is cross/main —
          // i.e. height/width here, not width/height. Passing _tileW/_tileH
          // collapsed each tile to ~19 px wide (the colored-strip bug).
          childAspectRatio: _tileH / _tileW,
          mainAxisSpacing: _gap,
          crossAxisSpacing: _gap,
        ),
        itemCount: items.length,
        itemBuilder: (_, i) =>
            _ChannelTile(item: items[i], colors: colors, sectionSource: sectionSource),
      ),
    );
  }
}

/// One wide rectangular channel tile — accent-tinted gradient + title on
/// the left, artwork tucked off the right edge at a slight angle for a
/// bit of dimensionality. Tap opens via openOccasion (Saavn channels
/// route through `music/occasions/[id]` per the API).
class _ChannelTile extends ConsumerWidget {
  const _ChannelTile({
    required this.item,
    required this.colors,
    required this.sectionSource,
  });
  final FeedItem item;
  final SunohColors colors;
  final String? sectionSource;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    final url = item.artwork ?? '';
    // Tint priority: real artwork palette > deterministic id hash. The
    // hash stands in until palette extraction completes so the tile has
    // a stable color identity from the first frame instead of flashing
    // a placeholder. `artPaletteProvider` is autoDispose + 30-min keep-
    // alive, so a scrolled-away tile won't keep extracting forever.
    final palette = url.isEmpty
        ? null
        : ref.watch(artPaletteProvider(url)).value;
    final tint = palette?.accent ?? artAccent(item.id);
    return GestureDetector(
      onTap: () => context.openOccasion(item),
      behavior: HitTestBehavior.opaque,
      child: squircleClip(
        radius: 10,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Color.lerp(c.bg, tint, 0.55)!,
                Color.lerp(c.bg, tint, 0.18)!,
              ],
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SunohType.heading(
                        fontSize: 13.5,
                        color: Colors.white,
                        letterSpacing: -0.1,
                        height: 1.15,
                      ),
                    ),
                  ),
                ),
              ),
              Transform.rotate(
                angle: 0.20,
                child: Transform.translate(
                  offset: const Offset(6, 4),
                  child: squircleClip(
                    radius: 4,
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: url.isEmpty
                          ? ColoredBox(
                              color: Colors.white.withValues(alpha: 0.18))
                          : SunohArt(
                              id: item.id,
                              imageUrl: url,
                              size: 56,
                              radius: 0,
                              shadow: false),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
