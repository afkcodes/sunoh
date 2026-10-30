// Library tab — the user's own collections as one list, with shelves for
// the music that lives elsewhere (this phone, a YouTube account, shows).
//
// Laid out as the prototype's Library: a title row, the filter chips, a sort
// row, then a list whose first rows are the three fixed collections (Liked
// songs, Recently played, Downloads — see library_rows.dart) followed by the
// user's own playlists, so the top of the tab reads as one list. The shelves
// come next and the saved items last, under a header of their own: under
// "All" that list includes every liked song, and a shelf placed after it
// would sit a thousand rows down.
//
// Everything is real data — the LibraryStore-backed saved albums, playlists,
// artists and liked songs — never the placeholder catalog.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dto.dart';
import '../data/models.dart';
import '../data/user_playlist.dart';
import '../overlays/playlist_name_sheet.dart';
import '../providers/app_state_provider.dart';
import '../providers/local_library_provider.dart';
import '../providers/ytmusic_provider.dart';
import '../router/router.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/cover_hero.dart';
import '../widgets/motion.dart';
import '../widgets/ui.dart';
import 'cover_tile.dart';
import 'library_controls.dart';
import 'library_device_section.dart';
import 'library_filter.dart';
import 'library_playlists.dart';
import 'library_rows.dart';
import 'library_saved.dart';
import 'library_search_field.dart';
import 'library_youtube_section.dart';

enum _LibFilter { all, playlists, albums, artists, songs }

extension on _LibFilter {
  String get label => switch (this) {
    _LibFilter.all => 'All',
    _LibFilter.playlists => 'Playlists',
    _LibFilter.albums => 'Albums',
    _LibFilter.artists => 'Artists',
    _LibFilter.songs => 'Songs',
  };

  /// The header over the saved items, naming what the chip left in the list.
  String get heading => switch (this) {
    _LibFilter.all => 'Saved',
    _LibFilter.playlists => 'Saved playlists',
    _LibFilter.albums => 'Saved albums',
    _LibFilter.artists => 'Followed artists',
    _LibFilter.songs => 'Liked songs',
  };

  /// What the saved list says when the chip leaves nothing in it.
  String get empty => switch (this) {
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
}

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});
  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  _LibFilter filter = _LibFilter.all;
  bool grid = false;
  String sort = 'Recents'; // 'Recents' | 'A–Z'

  // The inline filter. `_query` is the folded text (see foldForSearch); the
  // controller keeps what the user typed. Empty `_query` means not filtering.
  bool _searching = false;
  String _query = '';
  final _searchCtl = TextEditingController();
  final _searchFocus = FocusNode();
  final _itemsMemo = LibraryListMemo<FeedItem>();
  final _playlistsMemo = LibraryListMemo<UserPlaylist>();

  @override
  void dispose() {
    _searchCtl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _openSearch() => setState(() => _searching = true);

  void _closeSearch() {
    _searchCtl.clear();
    _searchFocus.unfocus();
    setState(() {
      _searching = false;
      _query = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final items = _itemsFor(s);
    final playlists = _playlistsMemo.get([
      s.userPlaylists,
      _query,
    ], () => filterLibraryPlaylists(s.userPlaylists, _query));
    final filtering = _query.isNotEmpty;

    // Each block arrives in turn (FadeSlideIn). The optional ones are keyed so
    // a playlist appearing does not hand its neighbours' elements around and
    // replay their entrance.
    // Back closes the filter first rather than leaving the tab.
    return PopScope(
      canPop: !_searching,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeSearch();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_searching)
            LibrarySearchRow(
              colors: c,
              controller: _searchCtl,
              focus: _searchFocus,
              onChanged: (t) =>
                  setState(() => _query = foldForSearch(t.trim())),
              onClose: _closeSearch,
            )
          else
            FadeSlideIn(
              child: LibraryTitleRow(
                colors: c,
                onNewPlaylist: () => _newPlaylist(s),
                onSearch: _openSearch,
              ),
            ),
          FadeSlideIn(
            index: 1,
            child: _FilterChips(
              active: filter,
              colors: c,
              onChange: (f) => setState(() => filter = f),
            ),
          ),
          FadeSlideIn(
            index: 2,
            child: LibrarySortRow(
              sort: sort,
              grid: grid,
              colors: c,
              onSort: () =>
                  setState(() => sort = sort == 'Recents' ? 'A–Z' : 'Recents'),
              onGrid: () => setState(() => grid = !grid),
            ),
          ),
          // Fixed shortcuts and the device/YouTube/shows shelves are not
          // searchable items, so they step aside while a query is active.
          if (!filtering)
            FadeSlideIn(
              index: 3,
              child: LibraryShortcuts(state: s, colors: c),
            ),
          if (playlists.isNotEmpty)
            FadeSlideIn(
              key: const ValueKey('playlists'),
              index: 4,
              child: grid
                  ? UserPlaylistsStrip(
                      playlists: playlists,
                      colors: c,
                      accent: s.resolvedAccent,
                    )
                  : UserPlaylistsList(
                      playlists: playlists,
                      colors: c,
                      accent: s.resolvedAccent,
                    ),
            ),
          // On-device music, previewed rather than linked — see
          // LibraryDeviceSection for why covers earn their space here.
          if (!filtering)
            FadeSlideIn(
              key: const ValueKey('device'),
              index: 5,
              child: Consumer(
                builder: (ctx, innerRef, _) => LibraryDeviceSection(
                  library: innerRef.watch(localLibraryProvider),
                  colors: c,
                ),
              ),
            ),
          // A signed-in YouTube account's own shelves. Absent when signed out.
          if (!filtering)
            FadeSlideIn(
              key: const ValueKey('youtube'),
              index: 6,
              child: Consumer(
                builder: (ctx, innerRef, _) => LibraryYouTubeSection(
                  sections:
                      innerRef.watch(ytMusicLibraryProvider).asData?.value ??
                      const <HomeSection>[],
                  colors: c,
                ),
              ),
            ),
          if (!filtering && s.subscribedPodcasts.isNotEmpty)
            FadeSlideIn(
              key: const ValueKey('shows'),
              index: 7,
              child: _ShowsShelf(shows: s.subscribedPodcasts, colors: c),
            ),
          // Keyed on the filter as well, so a chip change brings the new list
          // in the way the page arrived instead of swapping it in place.
          // A matching playlist above already answers the query, so the saved
          // list only shows its own "nothing matches" when it is the whole
          // answer.
          if (!filtering || items.isNotEmpty || playlists.isEmpty)
            FadeSlideIn(
              key: ValueKey(filter),
              index: 8,
              child: LibrarySavedList(
                heading: filter.heading,
                emptyMessage: filtering
                    ? 'Nothing in your library matches ‘${_searchCtl.text.trim()}’'
                    : filter.empty,
                items: items,
                grid: grid,
                state: s,
                colors: c,
                onTap: _onItemTap,
              ),
            ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Future<void> _newPlaylist(AppState s) async {
    final name = await promptForPlaylistName(context);
    if (name == null || name.isEmpty || !mounted) return;
    final p = await s.createUserPlaylist(name);
    if (mounted) context.openUserPlaylist(p.id);
  }

  /// Items to render under the chips for the active filter, narrowed by the
  /// search text and ordered per the active sort key. Memoised on the source
  /// lists, chip, sort and query so build() does no sorting or matching.
  List<FeedItem> _itemsFor(AppState s) => _itemsMemo.get(
    [
      s.savedAlbums,
      s.savedPlaylists,
      s.savedArtists,
      s.likedSongs,
      filter,
      sort,
      _query,
    ],
    () {
      final base = switch (filter) {
        // Appended in each bucket's natural (newest-first) order; the sort
        // below re-orders for A-Z. Not deduped: the buckets are disjoint.
        _LibFilter.all => [
          ...s.savedAlbums,
          ...s.savedPlaylists,
          ...s.savedArtists,
          ...s.likedSongs,
        ],
        _LibFilter.playlists => s.savedPlaylists,
        _LibFilter.albums => s.savedAlbums,
        _LibFilter.artists => s.savedArtists,
        _LibFilter.songs => s.likedSongs,
      };
      final hits = filterLibraryItems(base, _query);
      if (sort != 'A–Z') return hits;
      return [
        ...hits,
      ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    },
  );

  void _onItemTap(FeedItem item, CoverHeroRef? hero) {
    switch (item.type) {
      case 'song':
        ref.read(appStateProvider).playApiSong(item, sourceLabel: 'LIBRARY');
      case 'album' || 'playlist' || 'artist':
        final at = DetailRef(item.type, item.id, source: item.source);
        context.openRef(at, hero: hero);
    }
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({
    required this.active,
    required this.colors,
    required this.onChange,
  });
  final _LibFilter active;
  final SunohColors colors;
  final ValueChanged<_LibFilter> onChange;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        children: [
          for (final f in _LibFilter.values) ...[
            if (f.index > 0) const SizedBox(width: 8),
            SunohChip(
              label: f.label,
              selected: f == active,
              colors: colors,
              onTap: () => onChange(f),
            ),
          ],
        ],
      ),
    );
  }
}

/// Subscribed podcasts as a cover shelf. Only built when there are any.
class _ShowsShelf extends StatelessWidget {
  const _ShowsShelf({required this.shows, required this.colors});
  final List<FeedItem> shows;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 30),
        SectionHeader(title: 'My shows', colors: colors),
        CoverShelf(
          itemCount: shows.length,
          itemBuilder: (context, i) {
            final show = shows[i];
            return CoverTile(
              cover: SunohArt(
                id: show.id,
                imageUrl: show.artwork,
                size: kCoverTileWidth,
                radius: SunohRadius.tile,
                shadow: false,
              ),
              title: show.title,
              subtitle: show.subtitle,
              colors: colors,
              onTap: () => context.openRef(
                DetailRef('podcast', show.id, source: show.source),
              ),
            );
          },
        ),
      ],
    );
  }
}
