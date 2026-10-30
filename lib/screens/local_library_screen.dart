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
import 'package:remixicon/remixicon.dart';

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
import '../widgets/motion.dart';
import '../widgets/top_tabs.dart';
import '../widgets/ui.dart';
import 'local_track_row.dart';
import 'sub_page_bar.dart';

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

  /// Search, sort and folders in the bar; a spinner in their place while a
  /// scan runs, since all three would act on a library that is changing.
  List<Widget> _actions(BuildContext context, LocalLibrary lib, SunohColors c) {
    if (lib.isScanning) {
      return [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: c.fgMute),
          ),
        ),
      ];
    }
    return [
      IconBtn(
        icon: RemixIcons.search_line,
        color: _searching ? c.accent : c.fg,
        onTap: _toggleSearch,
      ),
      IconBtn(
        icon: RemixIcons.sort_desc,
        color: c.fg,
        onTap: () => showLocalSortSheet(context),
      ),
      IconBtn(
        icon: RemixIcons.folder_3_line,
        color: c.fg,
        onTap: () => context.openLocalFolders(),
      ),
    ];
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
          SubPageBar(
            title: 'On this device',
            colors: c,
            actions: _actions(context, lib, c),
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
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
