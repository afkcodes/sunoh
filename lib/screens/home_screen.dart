// Home screen — sunoh wordmark + top tabs (Music / Radio / Podcasts). The
// Music tab consumes the live /music/home feed via Riverpod.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../api/dto.dart';
import '../data/models.dart';
import '../providers/api_providers.dart';
import '../providers/app_state_provider.dart';
import '../providers/home_provider.dart';
import '../router/router.dart';
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
    final feedAsync = ref.watch(homeFeedProvider(null));
    final gap = 40 * ref.watch(appStateProvider).density.scale;

    return feedAsync.when(
      loading: () => const _LoadingFeed(),
      error: (e, _) => _ErrorFeed(
        message: 'Couldn’t load the home feed.',
        detail: '$e',
        onRetry: () => ref.invalidate(homeFeedProvider(null)),
        colors: c,
      ),
      data: (sections) {
        final nonEmpty = sections.where((s) => s.items.isNotEmpty).toList();
        if (nonEmpty.isEmpty) {
          return _ErrorFeed(
            message: 'Nothing in the feed right now.',
            colors: c,
            onRetry: () => ref.invalidate(homeFeedProvider(null)),
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
    // (Channels stay square — they're typically program-art tiles.) When a
    // row is uniformly one of these, swap the card to the circle variant.
    final isCircleRow = section.items.isNotEmpty &&
        section.items.every((it) =>
            it.type == 'artist' ||
            it.type == 'radio_station' ||
            it.type == 'radio');
    // featured (first section) → big 220px tiles like the prototype's
    // Editorial picks. Circle rows stay round but a touch larger when featured.
    final width = isCircleRow
        ? (featured ? 120.0 : 96.0)
        : (featured ? 220.0 : 148.0);
    final gap = isCircleRow ? 18.0 : (featured ? 14.0 : 12.0);

    // Cap each row at 10 items; if there are more, show "See all →" linking
    // to the full section.
    final visible = section.items.take(10).toList();
    final hasMore = section.items.length > 10;

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
        context.openRef(DetailRef('artist', item.id, source: src));
        break;
      case 'song':
        // Songs play immediately — home rows full of songs (Trending,
        // Popular, New Releases) should kick playback on tap, not navigate
        // to a non-existent "song detail" screen.
        s.playApiSong(item,
            sourceLabel: 'HOME · ${section.heading}');
        break;
      case 'channel':
      case 'radio_station':
      case 'radio':
        // Radio stations need a two-step session bootstrap: create the
        // session (returns an opaque stationId), then fetch the first
        // batch of songs to populate the queue. Auto-extend on near-end-
        // of-queue (RN's useAutoQueue) is a separate follow-up.
        _startRadioStation(context, ref, item, src);
        break;
      default:
        s.flashToast(item.type);
    }
  }

  Future<void> _startRadioStation(
    BuildContext context,
    WidgetRef ref,
    FeedItem item,
    String? src,
  ) async {
    final s = ref.read(appStateProvider);
    final api = ref.read(sunohApiProvider);
    final provider = src ?? 'saavn';
    final stationKind = item.stationType ?? 'featured';
    s.flashToast('Starting ${item.title}…');
    try {
      final sessionId = await api.fetchRadioSession(
        id: item.id,
        type: stationKind,
        provider: provider,
        name: item.title,
        lang: item.language,
      );
      if (sessionId == null) {
        s.flashToast('Couldn’t start ${item.title}');
        return;
      }
      final songs = await api.fetchRadioSongs(sessionId, count: 20);
      if (songs.isEmpty) {
        s.flashToast('No songs available on this station');
        return;
      }
      await s.playApiQueue(songs, 0,
          sourceLabel: 'RADIO · ${item.title}');
    } catch (e) {
      s.flashToast('Radio failed: $e');
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
    return _Pulse(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
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
        // Section-header skeleton.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
          child: _SkeletonBar(height: 22, width: 180, radius: 6),
        ),
        // Horizontal "row" of card skeletons.
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
                      _SkeletonBar(
                        height: tileSize,
                        width: tileSize,
                        radius: featured ? 12 : 10,
                      ),
                      SizedBox(height: featured ? 10 : 8),
                      _SkeletonBar(
                        height: titleHeight,
                        width: tileSize * 0.85,
                        radius: 4,
                      ),
                      SizedBox(height: featured ? 4 : 2),
                      _SkeletonBar(
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

class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({
    required this.height,
    required this.width,
    this.radius = 6,
  });
  final double height;
  final double width;
  final double radius;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: squircleDecoration(
        radius: radius,
        color: Colors.white.withValues(alpha: 0.06),
      ),
    );
  }
}

/// Subtle opacity pulse for skeleton placeholders.
class _Pulse extends StatefulWidget {
  const _Pulse({required this.child});
  final Widget child;
  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        // Curved opacity for a softer pulse than a linear lerp.
        final t = Curves.easeInOut.transform(_c.value);
        return Opacity(opacity: 0.55 + 0.35 * t, child: child);
      },
      child: widget.child,
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
