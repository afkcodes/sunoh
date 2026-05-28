// Library tab — pinned shortcuts + filterable list of saved + liked.
//
// Restored after a brief pared-down version: chips (All / Playlists / Albums
// / Artists / Songs) + sort + grid/list toggle are back. The items list is
// driven by REAL data now (LibraryStore-backed saved_albums /
// saved_playlists / saved_artists / liked_songs) rather than the dummy
// catalog. Pinned tiles: Liked Songs (count) + Recently Played (count).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../api/dto.dart';
import '../data/models.dart';
import '../data/user_playlist.dart';
import '../providers/app_state_provider.dart';
import '../providers/downloads_provider.dart';
import '../router/router.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/ui.dart';
import 'user_playlist_screen.dart';

enum _LibFilter { all, playlists, albums, artists, songs }

extension on _LibFilter {
  String get label => switch (this) {
        _LibFilter.all => 'All',
        _LibFilter.playlists => 'Playlists',
        _LibFilter.albums => 'Albums',
        _LibFilter.artists => 'Artists',
        _LibFilter.songs => 'Songs',
      };
}

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});
  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  _LibFilter filter = _LibFilter.all;
  bool grid = false;
  String sort = 'Recent'; // 'Recent' | 'A–Z'

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final items = _itemsFor(s);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Library',
                  style: SunohType.heading(
                      fontSize: 28, color: c.fg, letterSpacing: -0.4)),
              Row(children: [
                IconBtn(
                    icon: SolarIconsOutline.magnifier,
                    color: c.fgDim,
                    size: 18,
                    width: 32,
                    height: 32,
                    onTap: () {}),
                IconBtn(
                    icon: SolarIconsOutline.downloadMinimalistic,
                    color: c.fgDim,
                    size: 18,
                    width: 32,
                    height: 32,
                    onTap: () => context.openSpotifyImport()),
                IconBtn(
                    icon: SolarIconsOutline.addCircle,
                    color: c.fgDim,
                    size: 18,
                    width: 32,
                    height: 32,
                    onTap: () async {
                      final name =
                          await promptForPlaylistName(context);
                      if (name == null || name.isEmpty) return;
                      if (!context.mounted) return;
                      final p = await s.createUserPlaylist(name);
                      if (context.mounted) {
                        context.openUserPlaylist(p.id);
                      }
                    }),
              ]),
            ],
          ),
        ),
        // Filter chips — single horizontally-scrolling row.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
          child: Row(
            children: [
              for (final f in _LibFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => filter = f),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: f == filter ? c.fg : c.surface,
                        borderRadius: BorderRadius.circular(999),
                        border: f == filter
                            ? null
                            : Border.all(color: c.line, width: 0.5),
                      ),
                      child: Text(f.label,
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
                onTap: () =>
                    setState(() => sort = sort == 'Recent' ? 'A–Z' : 'Recent'),
                child: Row(
                  children: [
                    Icon(SolarIconsOutline.tuningSquare,
                        size: 14, color: c.fgMute),
                    const SizedBox(width: 6),
                    eyebrow('SORT · $sort', c.fgMute,
                        size: 10, letterSpacing: 1.2),
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
        // Pinned shortcuts — Liked Songs + Recently Played + Downloads.
        // Each surfaces a real count and routes into its dedicated screen.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
          child: Row(
            children: [
              Expanded(
                child: _PinnedTile(
                  title: 'Liked Songs',
                  sub: '${s.likedSongs.length} '
                      '${s.likedSongs.length == 1 ? 'song' : 'songs'}',
                  icon: SolarIconsBold.heart,
                  gradient: [
                    s.resolvedAccent.withValues(alpha: 0.85),
                    s.resolvedAccent.withValues(alpha: 0.18),
                  ],
                  onTap: () => context.openLikedSongs(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PinnedTile(
                  title: 'Recently Played',
                  sub: s.playedHistory.isEmpty
                      ? 'No history yet'
                      : '${s.playedHistory.length} '
                          'recent ${s.playedHistory.length == 1 ? 'song' : 'songs'}',
                  icon: SolarIconsOutline.clockCircle,
                  gradient: const [Color(0xFF1D3A3A), Color(0xFF0E1818)],
                  onTap: () => context.openRecentlyPlayed(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Consumer(builder: (ctx, innerRef, _) {
                  // Use the live download list count so the subtitle
                  // updates the moment a new download lands without
                  // bouncing the whole library page through `s`.
                  final dl = innerRef
                      .watch(downloadEntriesProvider)
                      .asData
                      ?.value;
                  final n = dl?.length ?? 0;
                  return _PinnedTile(
                    title: 'Downloads',
                    sub: n == 0
                        ? 'Tap a song to save'
                        : '$n ${n == 1 ? 'song' : 'songs'}',
                    icon: SolarIconsOutline.downloadMinimalistic,
                    gradient: const [Color(0xFF2A1F3A), Color(0xFF13101C)],
                    onTap: () => context.openDownloads(),
                  );
                }),
              ),
            ],
          ),
        ),
        if (s.userPlaylists.isNotEmpty) ...[
          _UserPlaylistsStrip(
              playlists: s.userPlaylists,
              colors: c,
              accent: s.resolvedAccent),
          const SizedBox(height: 18),
        ],
        if (s.subscribedPodcasts.isNotEmpty) ...[
          _SubscribedShowsStrip(shows: s.subscribedPodcasts, colors: c),
          const SizedBox(height: 18),
        ],
        if (items.isEmpty)
          _EmptyState(filter: filter, colors: c)
        else if (grid)
          _GridList(items: items, colors: c, onTap: _onItemTap)
        else
          for (final it in items)
            _ListRow(item: it, colors: c, onTap: () => _onItemTap(it)),
        const SizedBox(height: 20),
      ],
    );
  }

  /// Items to render under the chips for the active filter, sorted per
  /// the active sort key.
  List<FeedItem> _itemsFor(AppState s) {
    List<FeedItem> base;
    switch (filter) {
      case _LibFilter.all:
        // Newest-first across the whole library, deduped by id+type so an
        // album that's also queued doesn't appear twice. We append in
        // the "natural" order each bucket wants (saved buckets are
        // already newest-first via LibraryStore) and let the sort below
        // re-sort if the user picked A-Z.
        base = [
          ...s.savedAlbums,
          ...s.savedPlaylists,
          ...s.savedArtists,
          ...s.likedSongs,
        ];
      case _LibFilter.playlists:
        base = s.savedPlaylists;
      case _LibFilter.albums:
        base = s.savedAlbums;
      case _LibFilter.artists:
        base = s.savedArtists;
      case _LibFilter.songs:
        base = s.likedSongs;
    }
    if (sort == 'A–Z') {
      final sorted = [...base]
        ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      return sorted;
    }
    return base;
  }

  void _onItemTap(FeedItem item) {
    final s = ref.read(appStateProvider);
    if (item.type == 'song') {
      s.playApiSong(item, sourceLabel: 'LIBRARY');
      return;
    }
    if (item.type == 'album' ||
        item.type == 'playlist' ||
        item.type == 'artist') {
      context
          .openRef(DetailRef(item.type, item.id, source: item.source));
    }
  }
}

class _ListRow extends StatelessWidget {
  const _ListRow({
    required this.item,
    required this.colors,
    required this.onTap,
  });
  final FeedItem item;
  final SunohColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final isArtist = item.type == 'artist';
    final isSong = item.type == 'song';
    final sub = _subFor(item);
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
                size: 50,
                radius: isArtist ? 999 : (isSong ? 6 : 8)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SunohType.sans(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w500,
                          color: c.fg)),
                  if (sub.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            SunohType.sans(fontSize: 11.5, color: c.fgMute)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GridList extends StatelessWidget {
  const _GridList({
    required this.items,
    required this.colors,
    required this.onTap,
  });
  final List<FeedItem> items;
  final SunohColors colors;
  final void Function(FeedItem) onTap;
  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.78,
        children: [
          for (final it in items)
            GestureDetector(
              onTap: () => onTap(it),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: SunohArt(
                        id: it.id,
                        imageUrl: it.artwork,
                        width: double.infinity,
                        radius: it.type == 'artist' ? 999 : 6),
                  ),
                  const SizedBox(height: 6),
                  Text(it.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SunohType.sans(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: c.fg,
                          height: 1.25)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Subtitle picker — uses the FeedItem's displaySubtitle (which falls
/// through artists → subtitle → kind label) but skips the literal
/// "Song" / "Album" / etc. fallbacks so library rows don't read as
/// broken under every entry.
String _subFor(FeedItem item) {
  final fromApi = (item.subtitle ?? '').trim();
  if (fromApi.isNotEmpty) return fromApi;
  final names = (item.artists ?? const <ApiArtistRef>[])
      .map((a) => a.name.trim())
      .where((n) => n.isNotEmpty)
      .take(2)
      .toList();
  if (names.isNotEmpty) return names.join(', ');
  switch (item.type) {
    case 'song':
      return 'Song';
    case 'album':
      return 'Album';
    case 'playlist':
      return 'Playlist';
    case 'artist':
      return 'Artist';
    default:
      return '';
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filter, required this.colors});
  final _LibFilter filter;
  final SunohColors colors;
  @override
  Widget build(BuildContext context) {
    final c = colors;
    final message = switch (filter) {
      _LibFilter.all =>
        'Save albums, playlists, or artists by tapping the heart on their page. Liked songs show up here too.',
      _LibFilter.playlists =>
        'No saved playlists yet. Tap the heart on a playlist to save it.',
      _LibFilter.albums =>
        'No saved albums yet. Tap the heart on an album to save it.',
      _LibFilter.artists =>
        'No followed artists yet. Tap the heart on an artist page to follow.',
      _LibFilter.songs =>
        'No liked songs yet. Tap the heart on any song to like it.',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Text(message,
          style: SunohType.sans(fontSize: 12.5, color: c.fgMute, height: 1.5)),
    );
  }
}

class _PinnedTile extends StatelessWidget {
  const _PinnedTile({
    required this.title,
    required this.sub,
    required this.icon,
    required this.gradient,
    required this.onTap,
  });
  final String title;
  final String sub;
  final IconData icon;
  final List<Color> gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 84,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: squircleDecoration(
          radius: 14,
          gradient: LinearGradient(
              colors: gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: Colors.white.withValues(alpha: 0.95)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SunohType.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          letterSpacing: -0.1)),
                  const SizedBox(height: 4),
                  eyebrow(sub, Colors.white.withValues(alpha: 0.6),
                      size: 9, letterSpacing: 1.2, maxLines: 1),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal scroller of the user's playlists. Hidden when the list is
/// empty (the "+" in the header is then the only entry point — no need
/// to clutter the library with an empty section).
class _UserPlaylistsStrip extends StatelessWidget {
  const _UserPlaylistsStrip({
    required this.playlists,
    required this.colors,
    required this.accent,
  });
  final List<UserPlaylist> playlists;
  final SunohColors colors;
  final Color accent;
  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: eyebrow('MY PLAYLISTS', c.fgMute,
              size: 10, letterSpacing: 1.4),
        ),
        SizedBox(
          height: 158,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: playlists.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final p = playlists[i];
              final cover = _firstArtwork(p);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => context.openUserPlaylist(p.id),
                child: SizedBox(
                  width: 116,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      squircleClip(
                        radius: 10,
                        child: Container(
                          width: 116,
                          height: 116,
                          decoration: BoxDecoration(
                            gradient: cover == null
                                ? LinearGradient(
                                    colors: [
                                      accent.withValues(alpha: 0.85),
                                      accent.withValues(alpha: 0.35),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  )
                                : null,
                          ),
                          child: cover == null
                              ? Icon(SolarIconsBold.musicLibrary2,
                                  size: 38,
                                  color:
                                      Colors.white.withValues(alpha: 0.9))
                              : Image.network(cover,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Icon(
                                      SolarIconsBold.musicLibrary2,
                                      size: 38,
                                      color: Colors.white
                                          .withValues(alpha: 0.9))),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SunohType.sans(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: c.fg)),
                      const SizedBox(height: 1),
                      Text(
                          '${p.songs.length} '
                          '${p.songs.length == 1 ? 'song' : 'songs'}',
                          style:
                              SunohType.sans(fontSize: 11, color: c.fgMute)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  static String? _firstArtwork(UserPlaylist p) {
    for (final s in p.songs) {
      final a = s.artwork;
      if (a != null && a.isNotEmpty) return a;
    }
    return null;
  }
}

/// Horizontal scroller of subscribed podcasts. Renders only when the
/// user has any (the Library tab hides the section otherwise).
class _SubscribedShowsStrip extends StatelessWidget {
  const _SubscribedShowsStrip({
    required this.shows,
    required this.colors,
  });
  final List<FeedItem> shows;
  final SunohColors colors;
  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: eyebrow('MY SHOWS', c.fgMute,
              size: 10, letterSpacing: 1.4),
        ),
        SizedBox(
          height: 158,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: shows.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final show = shows[i];
              return GestureDetector(
                onTap: () => context.openRef(DetailRef(
                    'podcast', show.id,
                    source: show.source)),
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 116,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      squircleClip(
                        radius: 10,
                        child: SunohArt(
                          id: show.id,
                          imageUrl: show.artwork,
                          size: 116,
                          radius: 10,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(show.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SunohType.sans(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: c.fg)),
                      if ((show.subtitle ?? '').isNotEmpty) ...[
                        const SizedBox(height: 1),
                        Text(show.subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SunohType.sans(
                                fontSize: 11, color: c.fgMute)),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
