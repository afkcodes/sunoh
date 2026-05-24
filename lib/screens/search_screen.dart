// Search — input, recent queries, genre tiles, live filtered results.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../data/catalog.dart';
import '../data/models.dart';
import '../providers/app_state_provider.dart';
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

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final controller = TextEditingController();
  String q = '';

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.read(appStateProvider);
    final c = s.colors;
    final trimmed = q.trim().toLowerCase();
    final hasQuery = trimmed.isNotEmpty;
    bool match(String? str) => str != null && str.toLowerCase().contains(trimmed);

    final tracks = hasQuery
        ? kTracks.where((t) => match(t.title) || match(t.artist)).take(6).toList()
        : <Track>[];
    final artists = hasQuery
        ? kArtists.where((a) => match(a.name)).take(4).toList()
        : <Artist>[];
    final albums = hasQuery
        ? kAlbums.where((a) => match(a.title) || match(a.artist)).take(4).toList()
        : <Album>[];
    final podcasts = hasQuery
        ? kPodcasts.where((p) => match(p.title) || match(p.host)).take(4).toList()
        : <Podcast>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Search',
                  style: SunohType.heading(fontSize: 28, color: c.fg, letterSpacing: -0.4)),
              IconBtn(icon: SolarIconsOutline.microphone, color: c.fgDim, size: 20, onTap: () {}),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: squircleDecoration(radius: 12, color: c.surface, borderColor: c.line),
            child: Row(
              children: [
                Icon(SolarIconsOutline.magnifier, size: 17, color: c.fgMute),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: controller,
                    onChanged: (v) => setState(() => q = v),
                    cursorColor: c.accent,
                    style: SunohType.sans(fontSize: 14, color: c.fg),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: 'Artists, songs, podcasts, stations…',
                      hintStyle: SunohType.sans(fontSize: 14, color: c.fgMute),
                    ),
                  ),
                ),
                if (q.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      controller.clear();
                      setState(() => q = '');
                    },
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(SolarIconsOutline.closeCircle, size: 12, color: c.fg),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (!hasQuery) _browse(c) else _results(c, s, tracks, artists, albums, podcasts),
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
              Text('Clear', style: SunohType.sans(fontSize: 11, color: c.fgMute)),
            ],
          ),
        ),
        for (final r in _recentSearches)
          GestureDetector(
            onTap: () {
              controller.text = r;
              setState(() => q = r);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
              child: Row(
                children: [
                  Icon(SolarIconsOutline.magnifier, size: 15, color: c.fgMute),
                  const SizedBox(width: 12),
                  Expanded(child: Text(r, style: SunohType.sans(fontSize: 14, color: c.fg))),
                  Icon(SolarIconsOutline.closeCircle, size: 13, color: c.fgMute),
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

  Widget _results(SunohColors c, AppState s, List<Track> tracks,
      List<Artist> artists, List<Album> albums, List<Podcast> podcasts) {
    final empty =
        tracks.isEmpty && artists.isEmpty && albums.isEmpty && podcasts.isEmpty;
    if (empty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 40, 20, 40),
        child: Center(
          child: Column(
            children: [
              Text('Nothing yet.',
                  style: SunohType.heading(fontSize: 22, color: c.fgDim)),
              const SizedBox(height: 8),
              Text('No results for “$q”',
                  style: SunohType.sans(fontSize: 13, color: c.fgMute)),
            ],
          ),
        ),
      );
    }
    Widget heading(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
          child: eyebrow(t, c.fgMute),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        if (tracks.isNotEmpty) ...[
          heading('SONGS'),
          for (final t in tracks)
            _ResultRow(
              colors: c,
              title: t.title,
              sub: '${t.artist} · ${fmt(t.duration)}',
              art: SunohArt(id: t.id, size: 42, radius: 4),
              trailing: Icon(SolarIconsBold.menuDots, size: 18, color: c.fgMute),
              onTap: () => s.playTrack(t),
            ),
          const SizedBox(height: 20),
        ],
        if (artists.isNotEmpty) ...[
          heading('ARTISTS'),
          for (final a in artists)
            _ResultRow(
              colors: c,
              title: a.name,
              sub: '${a.monthly} monthly listeners',
              art: SunohArt(id: a.id, size: 42, radius: 999),
              trailing: Icon(SolarIconsOutline.altArrowRight, size: 18, color: c.fgMute),
              onTap: () => context.openRef(DetailRef('artist', a.id)),
            ),
          const SizedBox(height: 20),
        ],
        if (albums.isNotEmpty) ...[
          heading('ALBUMS'),
          for (final a in albums)
            _ResultRow(
              colors: c,
              title: a.title,
              sub: '${a.kind} · ${a.artist} · ${a.year}',
              art: SunohArt(id: a.id, size: 42, radius: 4),
              trailing: Icon(SolarIconsOutline.altArrowRight, size: 18, color: c.fgMute),
              onTap: () => context.openRef(DetailRef('album', a.id)),
            ),
          const SizedBox(height: 20),
        ],
        if (podcasts.isNotEmpty) ...[
          heading('PODCASTS'),
          for (final p in podcasts)
            _ResultRow(
              colors: c,
              title: p.title,
              sub: '${p.host} · ${p.episodes} episodes',
              art: SunohArt(id: p.id, size: 42, radius: 4),
              trailing: Icon(SolarIconsOutline.altArrowRight, size: 18, color: c.fgMute),
              onTap: () => context.openRef(DetailRef('podcast', p.id)),
            ),
        ],
      ],
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.colors,
    required this.title,
    required this.sub,
    required this.art,
    required this.onTap,
    this.trailing,
  });
  final SunohColors colors;
  final String title;
  final String sub;
  final Widget art;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            art,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SunohType.sans(
                          fontSize: 14, fontWeight: FontWeight.w500, color: colors.fg)),
                  const SizedBox(height: 1),
                  Text(sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SunohType.sans(fontSize: 12, color: colors.fgMute)),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
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
                style: SunohType.heading(fontSize: 20, color: Colors.white, letterSpacing: -0.2)),
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
