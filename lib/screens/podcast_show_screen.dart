// Podcast show detail, laid out as an album page: the show's cover hero,
// subscribe / download / queue and the play disc, the description (tap to
// read all of it), then the episodes as list rows.
//
// The first 30 episodes arrive with the show; the full list is fetched once
// the reader nears the bottom (see _expandEpisodes).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remixicon/remixicon.dart';

import '../api/dto.dart';
import '../providers/api_providers.dart';
import '../providers/app_state_provider.dart';
import '../providers/palette_provider.dart';
import '../providers/podcast_provider.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/motion.dart';
import '../widgets/ui.dart';
import 'detail_chrome.dart';
import 'detail_hero.dart';
import 'detail_loading.dart';
import 'podcast_episode_row.dart';

/// Threshold (in pixels from the bottom of the list) at which the
/// expand-to-full fetch fires. 600 ≈ a screenful — by the time the user
/// has the bottom of the initial 30 in view, the rest are already
/// loading (and usually landed) so there's no visible gap.
const double _kLoadMoreThreshold = 600;

/// One-shot expand size for the full episode list. PodcastIndex's
/// /episodes/byfeedid has no older-than cursor (only `since=…` which
/// is a NEWER-than filter), and the API hard-caps at max=1000 — so
/// 1000 is the absolute ceiling, full stop. The initial fast 30 (from
/// the bundled /podcasts/:id call) gets replaced with this fetch the
/// moment the user scrolls in. Covers ~every podcast ever made except
/// a handful of long-running daily shows (Rogan, This American Life,
/// Stuff You Should Know); reaching beyond would need a server-side
/// raw-RSS parse, which isn't worth the new dep right now.
const int _kFullFetchMax = 1000;

class PodcastShowScreen extends ConsumerStatefulWidget {
  const PodcastShowScreen({super.key, required this.id});
  final String id;

  @override
  ConsumerState<PodcastShowScreen> createState() => _PodcastShowScreenState();
}

class _PodcastShowScreenState extends ConsumerState<PodcastShowScreen> {
  final ScrollController _scroll = ScrollController();
  // Local mirror of the episode list. Initialised from the bundled show
  // fetch (30 newest); replaced wholesale once the "load full list"
  // request lands. We mirror locally so the list can grow independently
  // of the upstream provider (which caches the initial show payload).
  List<FeedItem>? _episodes;
  bool _expanding = false;
  bool _expanded = false;
  String? _expandError;

  // The description, stripped of its HTML once per show rather than on
  // every rebuild.
  String? _aboutSource;
  String _about = '';

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_expanded || _expanding) return;
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.maxScrollExtent - pos.pixels <= _kLoadMoreThreshold) {
      _expandEpisodes();
    }
  }

  Future<void> _expandEpisodes() async {
    if (_expanded || _expanding) return;
    setState(() {
      _expanding = true;
      _expandError = null;
    });
    try {
      final api = ref.read(sunohApiProvider);
      final list = await api.fetchPodcastEpisodes(
        widget.id,
        max: _kFullFetchMax,
      );
      if (!mounted) return;
      // Defensive dedup by id — the bundled 30 and the full 500 overlap
      // entirely so we just take the new list, but if anything weird
      // happens upstream the union is the safe move.
      final byId = <String, FeedItem>{};
      for (final e in list) {
        byId[e.id] = e;
      }
      // Merge in any locally-known episodes the fresh fetch lacks. For
      // a typical show this is a no-op; for a very-long-running one
      // where the full fetch hit the 500 ceiling, keeping the older
      // bundled ones is wrong (they're newer than the 500th of the
      // re-fetch), so this only adds when ids don't collide.
      final existing = _episodes ?? const <FeedItem>[];
      for (final e in existing) {
        byId.putIfAbsent(e.id, () => e);
      }
      final merged = byId.values.toList()
        ..sort((a, b) {
          // PodcastIndex sorts newest first; preserve that.
          // We don't carry datePublished as a comparable here, so fall
          // back to the order of the fresh fetch (which IS newest first).
          final ai = list.indexWhere((x) => x.id == a.id);
          final bi = list.indexWhere((x) => x.id == b.id);
          if (ai >= 0 && bi >= 0) return ai.compareTo(bi);
          if (ai >= 0) return -1;
          if (bi >= 0) return 1;
          return 0;
        });
      setState(() {
        _episodes = merged;
        _expanded = true;
        _expanding = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _expanding = false;
        _expandError = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final async = ref.watch(podcastShowProvider(widget.id));
    return async.when(
      loading: () => DetailLoading(colors: c),
      error: (e, _) => _ErrorState(
        colors: c,
        message: '$e',
        onRetry: () => ref.invalidate(podcastShowProvider(widget.id)),
      ),
      data: (show) {
        // Seed the local list from the provider's bundled episodes on the
        // first build that has data.
        final episodes = _episodes ??= show.episodes;
        if (!identical(_aboutSource, show.description)) {
          _aboutSource = show.description;
          _about = _strip(show.description ?? '');
        }
        final art = show.artwork;
        final palette = (art ?? '').isEmpty
            ? null
            : ref.watch(artPaletteProvider(art!)).value;
        // Through themedAccent: a raw artwork accent is a pastel on the
        // light palette, and it fills the play disc.
        final accent = s.themedAccent(palette?.accent ?? s.resolvedAccent);
        final label = 'PODCAST · ${show.title}';
        return DetailPage(
          colors: c,
          colour: accent,
          title: show.title,
          controller: _scroll,
          builder: (scroll) => [
            SliverToBoxAdapter(
              child: DetailHero(
                colors: c,
                colour: accent,
                scroll: scroll,
                cover: DetailCover(id: show.id, imageUrl: art),
                title: show.title,
                byline: show.subtitle,
                meta: 'Podcast',
              ),
            ),
            SliverToBoxAdapter(
              child: FadeSlideIn(
                index: 3,
                child: _actions(s, c, show, episodes, accent, label),
              ),
            ),
            if (_about.isNotEmpty)
              SliverToBoxAdapter(
                child: FadeSlideIn(
                  index: 4,
                  child: _About(text: _about, colors: c),
                ),
              ),
            SliverToBoxAdapter(
              child: _EpisodesHeader(count: episodes.length, colors: c),
            ),
            if (episodes.isEmpty)
              SliverToBoxAdapter(child: _NoEpisodes(colors: c))
            else
              SliverList.builder(
                itemCount: episodes.length,
                itemBuilder: (context, i) => EpisodeRow(
                  episode: episodes[i],
                  colors: c,
                  accent: accent,
                  onTap: () => s.playApiQueue(episodes, i, sourceLabel: label),
                ),
              ),
            // Loading row while expanding, error row on failure (with
            // retry), nothing once fully expanded.
            SliverToBoxAdapter(
              child: _EpisodesFooter(
                expanding: _expanding,
                error: _expandError,
                onRetry: _expandEpisodes,
                colors: c,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _actions(
    AppState s,
    SunohColors c,
    PodcastShowDetail show,
    List<FeedItem> episodes,
    Color accent,
    String label,
  ) {
    final subscribed = s.isSubscribedPodcast(show.id);
    final here = s.apiSourceRef == null && s.apiSourceLabel == label;
    final empty = episodes.isEmpty;
    return DetailActions(
      colors: c,
      colour: accent,
      playing: here && s.isPlaying,
      shuffle: false,
      leading: [
        IconBtn(
          icon: subscribed ? RemixIcons.heart_3_fill : RemixIcons.heart_3_line,
          color: c.fg,
          onTap: () => s.toggleSubscribedPodcast(_showAsFeedItem(show)),
        ),
        IconBtn(
          icon: RemixIcons.download_2_line,
          color: c.fg,
          onTap: () => s.flashToast('Downloads coming soon'),
        ),
        if (!empty)
          IconBtn(
            icon: RemixIcons.play_list_add_line,
            color: c.fg,
            onTap: () {
              for (final e in episodes) {
                s.addApiSongToQueue(e);
              }
              s.flashToast('Added ${episodes.length} to queue');
            },
          ),
      ],
      onPlay: empty
          ? null
          : () => here
                ? s.playPause()
                : s.playApiQueue(episodes, 0, sourceLabel: label),
    );
  }

  static String _strip(String html) {
    final s = html.replaceAll(RegExp(r'<[^>]*>'), ' ');
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

/// Bottom-of-list footer slot — shows a small loading spinner while the
/// "expand to full episode list" fetch is in flight, an error pill with
/// retry on failure, and nothing in the steady state.
class _EpisodesFooter extends StatelessWidget {
  const _EpisodesFooter({
    required this.expanding,
    required this.error,
    required this.onRetry,
    required this.colors,
  });
  final bool expanding;
  final String? error;
  final VoidCallback onRetry;
  final SunohColors colors;
  @override
  Widget build(BuildContext context) {
    final c = colors;
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
        child: Row(
          children: [
            Icon(RemixIcons.error_warning_line, color: c.fgDim, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Couldn’t load more episodes.',
                style: SunohType.sans(fontSize: 12.5, color: c.fgMute),
              ),
            ),
            _RetryPill(colors: c, onTap: onRetry),
          ],
        ),
      );
    }
    if (expanding) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: c.fgDim),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

/// The show's description: four lines and "see more", the whole of it on a
/// tap.
class _About extends StatefulWidget {
  const _About({required this.text, required this.colors});
  final String text;
  final SunohColors colors;

  @override
  State<_About> createState() => _AboutState();
}

class _AboutState extends State<_About> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _open = !_open),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
        child: _DescriptionText(
          text: widget.text,
          expanded: _open,
          colors: widget.colors,
        ),
      ),
    );
  }
}

class _DescriptionText extends StatelessWidget {
  const _DescriptionText({
    required this.text,
    required this.expanded,
    required this.colors,
  });
  final String text;
  final bool expanded;
  final SunohColors colors;
  @override
  Widget build(BuildContext context) {
    final c = colors;
    if (expanded) {
      return Text(
        text,
        style: SunohType.sans(fontSize: 13, color: c.fgDim, height: 1.5),
      );
    }
    // Inline "see more" — render the truncated body + a single bold
    // link at the end so the user can expand without a separate
    // button row underneath.
    return Text.rich(
      TextSpan(
        style: SunohType.sans(fontSize: 13, color: c.fgDim, height: 1.5),
        children: [
          TextSpan(text: _truncated(text)),
          TextSpan(
            text: '… see more',
            style: SunohType.sans(
              fontSize: 13,
              color: c.fg,
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
        ],
      ),
      maxLines: 4,
      overflow: TextOverflow.fade,
    );
  }

  /// Trims text to ~3.5 lines worth of characters. Real layout-aware
  /// truncation needs a TextPainter; this approximation is good
  /// enough for the four-line cap.
  static String _truncated(String s) {
    if (s.length <= 220) return s;
    return s.substring(0, 220);
  }
}

FeedItem _showAsFeedItem(PodcastShowDetail s) => FeedItem(
  id: s.id,
  title: s.title,
  subtitle: s.subtitle,
  type: 'podcast',
  image: s.image,
  source: 'podcastindex',
  language: s.language,
  url: s.url,
);

class _EpisodesHeader extends StatelessWidget {
  const _EpisodesHeader({required this.count, required this.colors});

  /// The live count: the bundled 30 at first, the full list once fetched.
  final int count;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    // SectionHeader's title metrics, with the count on the right — the
    // header has no slot for it.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 30, 16, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(
              'Episodes',
              style: SunohType.heading(fontSize: 20, color: c.fg, height: 1.1),
            ),
          ),
          Text('$count', style: SunohType.mono(fontSize: 13, color: c.fgDim)),
        ],
      ),
    );
  }
}

class _NoEpisodes extends StatelessWidget {
  const _NoEpisodes({required this.colors});
  final SunohColors colors;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Text(
        'No episodes yet.',
        style: SunohType.sans(fontSize: 13, color: colors.fgMute),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.colors,
    required this.message,
    required this.onRetry,
  });
  final SunohColors colors;
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    final c = colors;
    return ColoredBox(
      color: c.bg,
      child: Stack(
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Couldn’t load this show.',
                    style: SunohType.heading(fontSize: 22, color: c.fg),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: SunohType.sans(fontSize: 13, color: c.fgMute),
                  ),
                  const SizedBox(height: 16),
                  _RetryPill(colors: c, onTap: onRetry),
                ],
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: DetailBar(
              colors: c,
              colour: c.bg,
              title: '',
              solid: const FixedFlag(false),
            ),
          ),
        ],
      ),
    );
  }
}

/// Secondary action pill — filled surface2, used by both retry paths.
class _RetryPill extends StatelessWidget {
  const _RetryPill({required this.colors, required this.onTap});
  final SunohColors colors;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: squircleDecoration(radius: 16, color: colors.surface2),
        child: Text(
          'Retry',
          style: SunohType.sans(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: colors.fg,
          ),
        ),
      ),
    );
  }
}
