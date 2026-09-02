// On-device music — Songs / Albums / Artists.
//
// Tabs use the app's shared `SunohTabs`, and the three lists sit in a PageView
// so they swipe as well as tap. The tab strip and the pager drive each other:
// a tap animates the page, a swipe settles the strip.
//
// The device library is the one source that can be empty for reasons the user
// has to act on, so the empty states carry most of the weight here: a refused
// permission needs a prompt, a permanently refused one needs Settings, and a
// device with no music needs neither. Showing "nothing here" for all three
// would leave the user with no way forward.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';

import '../api/dto.dart';
import '../api/local_media_channel.dart';
import '../audio/local_library.dart';
import '../overlays/local_sort_sheet.dart';
import '../providers/app_state_provider.dart';
import '../providers/local_library_provider.dart';
import '../router/router.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/top_tabs.dart';
import '../widgets/ui.dart';
import 'local_track_row.dart';

/// The tab content. See the file header there.
part 'local_library_lists.dart';

const String _kSongs = 'Songs';
const String _kAlbums = 'Albums';
const String _kArtists = 'Artists';
const String _kGenres = 'Genres';
const String _kFolders = 'Folders';

/// Genres and Folders only appear when there is something in them. MediaStore
/// has no GENRE column below Android 11, and a library of loose files in one
/// directory has nothing to browse by folder — an always-present tab holding
/// one bucket is worse than no tab.
List<String> _tabsFor(LocalLibrary lib) => [
  _kSongs,
  _kAlbums,
  _kArtists,
  if (lib.genres.isNotEmpty) _kGenres,
  if (lib.folderGroups.length > 1) _kFolders,
];

class LocalLibraryScreen extends ConsumerStatefulWidget {
  const LocalLibraryScreen({super.key});
  @override
  ConsumerState<LocalLibraryScreen> createState() => _LocalLibraryScreenState();
}

class _LocalLibraryScreenState extends ConsumerState<LocalLibraryScreen> {
  final PageController _pages = PageController();
  final TextEditingController _search = TextEditingController();
  int _index = 0;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    // Re-scan on entry so files added since the last visit appear. `load`
    // reuses a completed scan, so this is free after the first time — and it
    // is the point at which asking for permission is something the user has
    // actually asked for.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(localLibraryProvider).load();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _pages.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) _search.clear();
    });
  }

  void _select(int i) {
    if (i == _index) return;
    setState(() => _index = i);
    _pages.animateToPage(
      i,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final lib = ref.watch(localLibraryProvider);

    final tabs = _tabsFor(lib);
    final index = _index.clamp(0, tabs.length - 1);
    final query = _searching ? _search.text.trim() : '';

    return ColoredBox(
      color: c.bg,
      child: Column(
        children: [
          _Header(
            library: lib,
            colors: c,
            searching: _searching,
            onToggleSearch: _toggleSearch,
          ),
          if (_searching)
            _SearchField(
              controller: _search,
              colors: c,
              onChanged: (_) => setState(() {}),
            ),
          if (lib.hasMusic && !_searching)
            SunohTabs(
              tabs: tabs,
              active: tabs[index],
              colors: c,
              onChange: (t) => _select(tabs.indexOf(t)),
            ),
          Expanded(
            child: !lib.hasMusic
                ? SingleChildScrollView(
                    child: _EmptyState(library: lib, colors: c),
                  )
                // Search replaces the tabs rather than filtering within one:
                // looking for a song by name should not require first knowing
                // whether it lives under Albums or Artists.
                : _searching
                ? _SongList(songs: lib.search(query), state: s, colors: c)
                : PageView(
                    controller: _pages,
                    onPageChanged: (i) => setState(() => _index = i),
                    children: [
                      for (final tab in tabs)
                        switch (tab) {
                          _kAlbums => _CollectionList(
                            collections: lib.albums,
                            album: true,
                            colors: c,
                          ),
                          _kArtists => _CollectionList(
                            collections: lib.artists,
                            album: false,
                            colors: c,
                          ),
                          _kGenres => _CollectionList(
                            collections: lib.genres,
                            album: true,
                            colors: c,
                          ),
                          _kFolders => _CollectionList(
                            collections: lib.folderGroups,
                            album: true,
                            colors: c,
                          ),
                          _ => _SongList(songs: lib.songs, state: s, colors: c),
                        },
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.library,
    required this.colors,
    required this.searching,
    required this.onToggleSearch,
  });
  final LocalLibrary library;
  final SunohColors colors;
  final bool searching;
  final VoidCallback onToggleSearch;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.of(context).padding.top + 20,
        20,
        6,
      ),
      child: Row(
        children: [
          IconBtn(
            icon: SolarIconsOutline.altArrowLeft,
            color: c.fgDim,
            size: 18,
            onTap: () => context.pop(),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              'On this device',
              style: SunohType.heading(
                fontSize: 24,
                color: c.fg,
                letterSpacing: -0.4,
              ),
            ),
          ),
          if (library.isScanning)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: c.fgMute),
            )
          else ...[
            IconBtn(
              icon: SolarIconsOutline.magnifier,
              color: searching ? c.accent : c.fgDim,
              size: 18,
              onTap: onToggleSearch,
            ),
            IconBtn(
              icon: SolarIconsOutline.sort,
              color: c.fgDim,
              size: 18,
              onTap: () => showLocalSortSheet(context),
            ),
            IconBtn(
              icon: SolarIconsOutline.folder,
              color: c.fgDim,
              size: 18,
              onTap: () => context.openLocalFolders(),
            ),
          ],
        ],
      ),
    );
  }
}
