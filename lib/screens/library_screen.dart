// Your Library — filter chips, sort + grid/list toggle, pinned tiles, items.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../data/catalog.dart';
import '../data/models.dart';
import '../providers/app_state_provider.dart';
import '../router/router.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/ui.dart';

class _LibItem {
  const _LibItem(this.kind, this.id, this.title, this.sub, this.radius);
  final String kind;
  final String id;
  final String title;
  final String sub;
  final double radius;
}

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});
  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  String filter = 'All';
  bool grid = false;
  String sort = 'Recent';

  static const filters = ['All', 'Playlists', 'Albums', 'Artists', 'Podcasts'];

  List<_LibItem> get items {
    final playlists = kPlaylists
        .map((p) => _LibItem('playlist', p.id, p.title, 'Playlist · ${p.curator}', 8))
        .toList();
    final albums = kAlbums
        .map((a) => _LibItem('album', a.id, a.title, '${a.kind} · ${a.artist}', 6))
        .toList();
    final artists =
        kArtists.map((a) => _LibItem('artist', a.id, a.name, 'Artist', 999)).toList();
    final podcasts = kPodcasts
        .map((p) => _LibItem('podcast', p.id, p.title, 'Podcast · ${p.host}', 6))
        .toList();
    switch (filter) {
      case 'Playlists':
        return playlists;
      case 'Albums':
        return albums;
      case 'Artists':
        return artists;
      case 'Podcasts':
        return podcasts;
      default:
        return [...playlists, ...albums, ...artists, ...podcasts];
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.read(appStateProvider);
    final c = s.colors;
    final list = items;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Library',
                  style: SunohType.heading(fontSize: 28, color: c.fg, letterSpacing: -0.4)),
              Row(children: [
                IconBtn(icon: SolarIconsOutline.magnifier, color: c.fgDim, size: 18, width: 32, height: 32, onTap: () {}),
                IconBtn(icon: SolarIconsOutline.addCircle, color: c.fgDim, size: 18, width: 32, height: 32, onTap: () {}),
              ]),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
          child: Row(
            children: [
              for (final f in filters)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => filter = f),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: f == filter ? c.fg : c.surface,
                        borderRadius: BorderRadius.circular(999),
                        border: f == filter ? null : Border.all(color: c.line, width: 0.5),
                      ),
                      child: Text(f,
                          style: SunohType.sans(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: f == filter ? c.bg : c.fgDim,
                              letterSpacing: -0.1)),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () => setState(() => sort = sort == 'Recent' ? 'A–Z' : 'Recent'),
                child: Row(
                  children: [
                    Icon(SolarIconsOutline.tuningSquare, size: 14, color: c.fgMute),
                    const SizedBox(width: 6),
                    eyebrow('SORT · $sort', c.fgMute, size: 10, letterSpacing: 1.2),
                  ],
                ),
              ),
              Row(children: [
                IconBtn(
                  icon: SolarIconsOutline.list,
                  color: !grid ? c.fg : c.fgMute,
                  size: 16,
                  width: 32,
                  height: 32,
                  background: !grid ? c.surface : null,
                  onTap: () => setState(() => grid = false),
                ),
                const SizedBox(width: 4),
                IconBtn(
                  icon: SolarIconsOutline.widget,
                  color: grid ? c.fg : c.fgMute,
                  size: 16,
                  width: 32,
                  height: 32,
                  background: grid ? c.surface : null,
                  onTap: () => setState(() => grid = true),
                ),
              ]),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
          child: Row(
            children: [
              Expanded(
                child: _PinnedTile(
                  title: 'Liked Songs',
                  sub: '248 songs',
                  gradient: const [Color(0xFF5B2A3E), Color(0xFF1A1014)],
                  onTap: () => context.openRef(const DetailRef('playlist', 'p01')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PinnedTile(
                  title: 'Downloaded',
                  sub: '6 albums',
                  gradient: const [Color(0xFF1D3A3A), Color(0xFF0E1818)],
                  onTap: () {},
                ),
              ),
            ],
          ),
        ),
        if (!grid)
          for (final it in list)
            GestureDetector(
              onTap: () => context.openRef(DetailRef(it.kind, it.id)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    SunohArt(id: it.id, size: 50, radius: it.radius),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(it.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: SunohType.sans(
                                  fontSize: 14.5, fontWeight: FontWeight.w500, color: c.fg)),
                          const SizedBox(height: 2),
                          Text(it.sub,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: SunohType.sans(fontSize: 11.5, color: c.fgMute)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.78,
              children: [
                for (final it in list)
                  GestureDetector(
                    onTap: () => context.openRef(DetailRef(it.kind, it.id)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AspectRatio(
                          aspectRatio: 1,
                          child: SunohArt(
                              id: it.id,
                              width: double.infinity,
                              radius: it.radius == 999 ? 999 : 6),
                        ),
                        const SizedBox(height: 6),
                        Text(it.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: SunohType.sans(
                                fontSize: 11.5, fontWeight: FontWeight.w500, color: c.fg, height: 1.25)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 20),
      ],
    );
  }
}

class _PinnedTile extends StatelessWidget {
  const _PinnedTile({
    required this.title,
    required this.sub,
    required this.gradient,
    required this.onTap,
  });
  final String title;
  final String sub;
  final List<Color> gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 72,
        padding: const EdgeInsets.all(12),
        decoration: squircleDecoration(
          radius: 10,
          gradient: LinearGradient(
              colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title,
                style: SunohType.sans(
                    fontSize: 13.5, fontWeight: FontWeight.w600, color: Colors.white, letterSpacing: -0.1)),
            eyebrow(sub, Colors.white.withValues(alpha: 0.55), size: 9, letterSpacing: 1.2),
          ],
        ),
      ),
    );
  }
}
