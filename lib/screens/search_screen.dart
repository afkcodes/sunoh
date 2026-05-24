// Search — input + debounced live results from /music/search?type=all.
// Browse view (recent + genre tiles) takes over when the query is empty.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../api/dto.dart';
import '../data/models.dart';
import '../providers/app_state_provider.dart';
import '../providers/search_provider.dart';
import '../router/router.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/ui.dart';

class _Genre {
  const _Genre(this.label, this.bg, this.accent);
  final String label;
  final Color bg;
  final Color accent;
}

const _genres = [
  _Genre('Jazz', Color(0xFF1C1410), Color(0xFF8C5A3E)),
  _Genre('Folk', Color(0xFF15201B), Color(0xFF82B07B)),
  _Genre('Electronic', Color(0xFF0F1820), Color(0xFF7FB3D5)),
  _Genre('Ambient', Color(0xFF221A2B), Color(0xFFA78BD1)),
  _Genre('Soul', Color(0xFF2C1B16), Color(0xFFD97757)),
  _Genre('Indie', Color(0xFF1F2418), Color(0xFFCAA66B)),
  _Genre('Hip-Hop', Color(0xFF0E1216), Color(0xFF3C5B78)),
  _Genre('Classical', Color(0xFF222018), Color(0xFFC8B88A)),
  _Genre('Pop', Color(0xFF2B1C1C), Color(0xFFA13F3F)),
  _Genre('Documentary', Color(0xFF15171C), Color(0xFF5B9B95)),
];

const _recentSearches = [
  'Niamh Calder', 'After Hours', 'OKO', 'Tideline FM', 'Long Form, Slowly',
];

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

  void _pickRecent(String r) {
    _debounce?.cancel();
    controller.text = r;
    setState(() {
      q = r;
      _activeQuery = r.trim();
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
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: squircleDecoration(
                radius: 12, color: c.surface, borderColor: c.line),
            child: Row(
              children: [
                Icon(SolarIconsOutline.magnifier, size: 17, color: c.fgMute),
                const SizedBox(width: 10),
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
                    style: SunohType.sans(fontSize: 14, color: c.fg),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: 'Artists, songs, podcasts, stations…',
                      hintStyle:
                          SunohType.sans(fontSize: 14, color: c.fgMute),
                    ),
                  ),
                ),
                if (q.isNotEmpty)
                  GestureDetector(
                    onTap: _clear,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(SolarIconsOutline.closeCircle,
                          size: 12, color: c.fg),
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

  Widget _browse(SunohColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              eyebrow('RECENT', c.fgMute),
              Text('Clear',
                  style: SunohType.sans(fontSize: 11, color: c.fgMute)),
            ],
          ),
        ),
        for (final r in _recentSearches)
          GestureDetector(
            onTap: () => _pickRecent(r),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
              child: Row(
                children: [
                  Icon(SolarIconsOutline.magnifier,
                      size: 15, color: c.fgMute),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text(r,
                          style:
                              SunohType.sans(fontSize: 14, color: c.fg))),
                  Icon(SolarIconsOutline.closeCircle,
                      size: 13, color: c.fgMute),
                ],
              ),
            ),
          ),
        const SizedBox(height: 26),
        SectionHeader(title: 'Browse', colors: c),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 171 / 96,
            children: [for (final g in _genres) _GenreTile(g)],
          ),
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
        final nonEmpty =
            sections.where((sec) => sec.items.isNotEmpty).toList();
        if (nonEmpty.isEmpty) {
          return _SearchHint(
            colors: c,
            label: 'Nothing yet.',
            detail: 'No results for “$_activeQuery”',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            for (var i = 0; i < nonEmpty.length; i++) ...[
              _ResultsSection(
                section: nonEmpty[i],
                colors: c,
                onPlay: (song) => s.playApiSong(song,
                    sourceLabel: 'SEARCH · $_activeQuery'),
              ),
              if (i < nonEmpty.length - 1) const SizedBox(height: 20),
            ],
          ],
        );
      },
    );
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
    final trailingIcon = isSong
        ? SolarIconsBold.menuDots
        : SolarIconsOutline.altArrowRight;
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
            Icon(trailingIcon, size: 18, color: c.fgMute),
          ],
        ),
      ),
    );
  }

  /// Compact subtitle line — picks the most useful field per type.
  String _subFor(FeedItem item) {
    if ((item.displaySubtitle ?? '').isNotEmpty) return item.displaySubtitle!;
    if (item.type == 'song' && (item.artists ?? const []).isNotEmpty) {
      return item.artists!.map((a) => a.name).take(2).join(', ');
    }
    if (item.type == 'artist') return 'Artist';
    if (item.type == 'album') return 'Album';
    if (item.type == 'playlist') return 'Playlist';
    return item.type;
  }
}

class _GenreTile extends StatelessWidget {
  const _GenreTile(this.g);
  final _Genre g;
  @override
  Widget build(BuildContext context) {
    return squircleClip(
      radius: 12,
      child: Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: g.bg)),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(1, 1),
                  radius: 1.1,
                  colors: [g.accent, g.accent.withValues(alpha: 0)],
                  stops: const [0, 0.6],
                ),
              ),
            ),
          ),
          Positioned(
            right: -16,
            bottom: -16,
            child: Transform.rotate(
              angle: 0.314,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: g.accent.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Positioned(
            left: 14,
            top: 12,
            child: Text(g.label,
                style: SunohType.heading(
                    fontSize: 20,
                    color: Colors.white,
                    letterSpacing: -0.2)),
          ),
          Positioned(
            left: 14,
            bottom: 12,
            child: eyebrow('GENRE', Colors.white.withValues(alpha: 0.6),
                size: 9, letterSpacing: 1.2),
          ),
        ],
      ),
    );
  }
}
