// Search — input + debounced live results from /music/search?type=all.
// Browse view (recent + genre tiles) takes over when the query is empty.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../api/dto.dart';
import '../data/models.dart';
import '../overlays/track_menu_sheet.dart';
import '../providers/app_state_provider.dart';
import '../providers/search_provider.dart';
import '../router/router.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/ui.dart';

/// Debounce window between the user typing and us actually firing the
/// `/music/search` request. 280 ms feels responsive for mobile typing
/// without spamming the API on every keystroke.
const _kDebounce = Duration(milliseconds: 280);

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final controller = TextEditingController();
  String q = '';
  // The debounced query — what we actually feed `searchProvider`. Empty
  // string means "don't search yet" (browse view stays up).
  String _activeQuery = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    controller.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    setState(() => q = v);
    _debounce?.cancel();
    final trimmed = v.trim();
    if (trimmed.isEmpty) {
      if (_activeQuery.isNotEmpty) setState(() => _activeQuery = '');
      return;
    }
    _debounce = Timer(_kDebounce, () {
      if (!mounted) return;
      if (trimmed == _activeQuery) return;
      setState(() => _activeQuery = trimmed);
    });
  }

  void _clear() {
    _debounce?.cancel();
    controller.clear();
    setState(() {
      q = '';
      _activeQuery = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final hasQuery = q.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Search',
                  style: SunohType.heading(
                      fontSize: 28, color: c.fg, letterSpacing: -0.4)),
              IconBtn(
                  icon: SolarIconsOutline.microphone,
                  color: c.fgDim,
                  size: 20,
                  onTap: () {}),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: squircleDecoration(
                radius: 14, color: c.surface, borderColor: c.line),
            child: Row(
              children: [
                Icon(SolarIconsOutline.magnifier, size: 19, color: c.fgMute),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: controller,
                    onChanged: _onChanged,
                    onSubmitted: (_) {
                      _debounce?.cancel();
                      setState(() => _activeQuery = q.trim());
                    },
                    cursorColor: c.accent,
                    textInputAction: TextInputAction.search,
                    style: SunohType.sans(fontSize: 15.5, color: c.fg),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: 'Artists, songs, podcasts, stations…',
                      hintStyle:
                          SunohType.sans(fontSize: 15, color: c.fgMute),
                    ),
                  ),
                ),
                if (q.isNotEmpty)
                  GestureDetector(
                    onTap: _clear,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(SolarIconsOutline.closeCircle,
                          size: 14, color: c.fg),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (!hasQuery)
          _browse(c)
        else
          _liveResults(c, s),
        const SizedBox(height: 20),
      ],
    );
  }

  /// Browse view: trending sections (horizontal carousels) followed by the
  /// live Explore Categories grid (occasions). Both are fetched on first
  /// open and cached for 1 hour (matches the RN reference's staleTime).
  /// Tapping a trending item routes via [_routeFeedItem]; tapping a
  /// category opens the occasion section detail (currently stubbed —
  /// `/music/occasions/:slug` wiring is a separate follow-up).
  Widget _browse(SunohColors c) {
    final trending = ref.watch(trendingSearchProvider);
    final occasions = ref.watch(occasionsProvider('gaana'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        // ── Trending — same shape as home, horizontal carousels per section.
        trending.when(
          loading: () =>
              _SearchHint(colors: c, label: 'Loading trending…'),
          error: (e, _) => const SizedBox.shrink(),
          data: (sections) {
            final nonEmpty =
                sections.where((s) => s.items.isNotEmpty).toList();
            if (nonEmpty.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < nonEmpty.length; i++) ...[
                  if (i > 0) const SizedBox(height: 24),
                  _TrendingRow(section: nonEmpty[i], colors: c),
                ],
                const SizedBox(height: 28),
              ],
            );
          },
        ),
        // ── Explore Categories grid — live occasions.
        // Uses the default SectionHeader padding so the header→content gap
        // matches the home-feed sections (Recently Played etc.).
        SectionHeader(title: 'Explore Categories', colors: c),
        occasions.when(
          loading: () => Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Loading categories…',
                style: SunohType.sans(fontSize: 12, color: c.fgMute)),
          ),
          error: (e, _) => const SizedBox.shrink(),
          data: (items) {
            if (items.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 171 / 110,
                children: [
                  for (final item in items)
                    _OccasionTile(item: item, colors: c),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  /// Live `/music/search?type=all` results — sections of FeedItems mirroring
  /// the home feed shape. When `_activeQuery` is empty (typing in-flight),
  /// shows a lightweight "Searching…" hint while the user is still typing.
  Widget _liveResults(SunohColors c, AppState s) {
    // Typed but debounce hasn't fired yet → just show "Searching…".
    if (_activeQuery.isEmpty) {
      return _SearchHint(colors: c, label: 'Searching…');
    }
    final async = ref.watch(searchProvider(_activeQuery));
    return async.when(
      loading: () =>
          _SearchHint(colors: c, label: 'Searching “$_activeQuery”…'),
      error: (e, _) => _SearchHint(
        colors: c,
        label: 'Couldn’t reach search. Try again.',
        detail: '$e',
      ),
      data: (sections) {
        final nonEmpty = sections.where((sec) => sec.items.isNotEmpty).toList();
        if (nonEmpty.isEmpty) {
          return _SearchHint(
            colors: c,
            label: 'Nothing yet.',
            detail: 'No results for “$_activeQuery”',
          );
        }
        // Pin "Top Results" / "Topquery" (whichever the active provider
        // returns) to the top — those carry the richest cross-provider
        // matches and are usually what the user actually wants.
        final ordered = [...nonEmpty]
          ..sort((a, b) => _topPriority(b.heading) -
              _topPriority(a.heading));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            for (var i = 0; i < ordered.length; i++) ...[
              _ResultsSection(
                section: ordered[i],
                colors: c,
                onPlay: (song) => s.playApiSong(song,
                    sourceLabel: 'SEARCH · $_activeQuery'),
              ),
              if (i < ordered.length - 1) const SizedBox(height: 20),
            ],
          ],
        );
      },
    );
  }

  /// Higher = render earlier. Top results / topquery first; everything
  /// else preserves the order the API returned in.
  static int _topPriority(String heading) {
    final h = heading.toLowerCase();
    if (h.contains('top result') || h == 'topquery' || h == 'top results') {
      return 100;
    }
    return 0;
  }
}

class _SearchHint extends StatelessWidget {
  const _SearchHint({
    required this.colors,
    required this.label,
    this.detail,
  });
  final SunohColors colors;
  final String label;
  final String? detail;
  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 40),
      child: Center(
        child: Column(
          children: [
            Text(label,
                style: SunohType.heading(fontSize: 22, color: c.fgDim)),
            if (detail != null) ...[
              const SizedBox(height: 8),
              Text(detail!,
                  textAlign: TextAlign.center,
                  style: SunohType.sans(fontSize: 13, color: c.fgMute)),
            ],
          ],
        ),
      ),
    );
  }
}

/// One section from `/music/search` (Songs / Albums / Artists / Playlists
/// / Topquery). Renders an eyebrow heading + a vertical list of result
/// rows. Tap behavior depends on item type — songs play, the rest open
/// the matching detail screen.
class _ResultsSection extends StatelessWidget {
  const _ResultsSection({
    required this.section,
    required this.colors,
    required this.onPlay,
  });
  final HomeSection section;
  final SunohColors colors;
  final void Function(FeedItem song) onPlay;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
          child: eyebrow(section.heading.toUpperCase(), c.fgMute),
        ),
        for (final item in section.items.take(8))
          _ResultRow(
            colors: c,
            item: item,
            onTap: () {
              switch (item.type) {
                case 'song':
                  onPlay(item);
                case 'album':
                case 'playlist':
                case 'artist':
                  context.openRef(DetailRef(item.type, item.id,
                      source: item.source ?? section.source));
                default:
                  // Unknown type — fall through to a no-op so we don't
                  // route somewhere invalid.
                  break;
              }
            },
          ),
      ],
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.colors,
    required this.item,
    required this.onTap,
  });
  final SunohColors colors;
  final FeedItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final isArtist = item.type == 'artist';
    final isSong = item.type == 'song';
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            SunohArt(
              id: item.id,
              imageUrl: item.artwork,
              size: 42,
              radius: isArtist ? 999 : 4,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SunohType.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: c.fg)),
                  if ((_subFor(item)).isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(_subFor(item),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            SunohType.sans(fontSize: 12, color: c.fgMute)),
                  ],
                ],
              ),
            ),
            if (isSong)
              GestureDetector(
                onTap: () => showTrackMenuSheet(context,
                    song: item, sourceLabel: 'SEARCH'),
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: Icon(SolarIconsBold.menuDots,
                      size: 18, color: c.fgMute),
                ),
              )
            else
              Icon(SolarIconsOutline.altArrowRight,
                  size: 18, color: c.fgMute),
          ],
        ),
      ),
    );
  }

  /// Compact subtitle line — only returns *meaningful* text so the UI can
  /// skip the row entirely when nothing useful is available. Generic type
  /// labels ("Song" / "Album") are deliberately suppressed because saavn
  /// search returns subtitle:null + artists:[] for many songs and showing
  /// the bare word "Song" under every row reads as broken.
  String _subFor(FeedItem item) {
    final fromApi = (item.subtitle ?? '').trim();
    if (fromApi.isNotEmpty) return fromApi;
    final names = (item.artists ?? const [])
        .map((a) => a.name.trim())
        .where((n) => n.isNotEmpty)
        .take(2)
        .toList();
    if (names.isNotEmpty) return names.join(', ');
    return '';
  }
}

/// Horizontal carousel of trending items for one section heading. Mirrors
/// the home-feed `_ApiSection` pattern — uses the same `HCardRow` and
/// per-item card chrome so trending feels at home with everything else.
class _TrendingRow extends ConsumerWidget {
  const _TrendingRow({required this.section, required this.colors});
  final HomeSection section;
  final SunohColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    final s = ref.read(appStateProvider);
    final isArtistRow = section.items.every((it) => it.type == 'artist');
    final width = isArtistRow ? 96.0 : 140.0;
    final gap = isArtistRow ? 18.0 : 12.0;
    final items = section.items.take(10).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: section.heading, colors: c),
        HCardRow<FeedItem>(
          items: items,
          width: width,
          gap: gap,
          onTap: (item) {
            switch (item.type) {
              case 'song':
                // Songs play immediately — tapping a song in a "trending"
                // carousel should never open a song-detail screen.
                s.playApiSong(item,
                    sourceLabel: 'TRENDING · ${section.heading}');
              case 'album':
              case 'playlist':
              case 'artist':
                context.openRef(DetailRef(item.type, item.id,
                    source: item.source ?? section.source));
              default:
                break;
            }
          },
          builder: (item, w) => isArtistRow
              ? Column(
                  children: [
                    SunohArt(
                        id: item.id,
                        imageUrl: item.artwork,
                        size: w - 10,
                        radius: 999),
                    const SizedBox(height: 10),
                    Text(item.title,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: SunohType.sans(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: c.fg,
                            height: 1.2)),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SunohArt(
                        id: item.id,
                        imageUrl: item.artwork,
                        size: w,
                        radius: 10),
                    const SizedBox(height: 8),
                    Text(item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SunohType.sans(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: c.fg,
                            height: 1.2)),
                    if ((item.displaySubtitle ?? '').isNotEmpty) ...[
                      const SizedBox(height: 3),
                      eyebrow(item.displaySubtitle!, c.fgMute,
                          size: 10, letterSpacing: 0.8, maxLines: 2),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

/// Live "Explore Categories" tile backed by an occasion FeedItem — image
/// background, dark-bottom-up gradient for text readability, title on top.
/// Tapping is currently a toast — the occasion-detail route + endpoint
/// isn't wired yet (separate follow-up). The visual stays useful as a
/// browse affordance even without the detail screen.
class _OccasionTile extends StatelessWidget {
  const _OccasionTile({required this.item, required this.colors});
  final FeedItem item;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    final url = item.artwork ?? '';
    return GestureDetector(
      onTap: () => context.openOccasion(item),
      child: squircleClip(
        radius: 14,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Image background — falls back to the painted album-art if no URL.
            SunohArt(id: item.id, imageUrl: url, size: 220, radius: 0),
            // Dark gradient (bottom-up) keeps the title legible regardless
            // of the cover's brightness.
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x00000000),
                      Color(0x66000000),
                      Color(0xCC000000),
                    ],
                    stops: [0.35, 0.75, 1],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 10,
              child: Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: SunohType.heading(
                  fontSize: 15,
                  color: Colors.white,
                  letterSpacing: -0.1,
                  height: 1.1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
