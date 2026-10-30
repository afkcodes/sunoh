// go_router configuration for sunoh.
//
// - A StatefulShellRoute.indexedStack drives the three bottom-nav tabs
//   (Home / Search / Library), each with its own state-preserving navigator.
// - Detail screens (album / playlist / artist / podcast) push within the active
//   tab branch, so the mini player + nav bar stay visible and Back returns to
//   the originating tab.
// - The expanded player, queue, and lyrics are full-screen modal routes on the
//   root navigator, layered above the shell.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/dto.dart';
import '../data/models.dart';
import '../overlays/lyrics_screen.dart';
import '../overlays/queue_screen.dart';
import '../player/expanded_player.dart';
import '../player/player_route.dart';
import '../screens/detail_screens.dart';
import '../screens/downloads_screen.dart';
import '../screens/episode_detail_screen.dart';
import '../screens/home_screen.dart';
import '../screens/library_screen.dart';
import '../screens/liked_songs_screen.dart';
import '../screens/local_collection_screen.dart';
import '../screens/local_folders_screen.dart';
import '../screens/local_library_screen.dart';
import '../screens/podcast_categories_screen.dart';
import '../screens/podcast_category_screen.dart';
import '../screens/podcast_show_screen.dart';
import '../screens/recently_played_screen.dart';
import '../screens/search_screen.dart';
import '../screens/section_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/spotify_import_screen.dart';
import '../screens/sync_screen.dart';
import '../screens/user_playlist_screen.dart';
import '../screens/yt_moods_screens.dart';
import '../screens/ytmusic_screens.dart';
import '../shell/app_scaffold.dart';
import '../shell/branch_fade.dart';
import '../widgets/cover_hero.dart';
import '../widgets/ui.dart';
import 'transitions.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();
final _homeKey = GlobalKey<NavigatorState>();
final _searchKey = GlobalKey<NavigatorState>();
final _libraryKey = GlobalKey<NavigatorState>();

GoRouter buildRouter() {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/home',
    // Safety net for inbound Android Intents. The platform forwards the
    // URI's path component to go_router *before* DeepLinkRouter (which
    // lives on top of app_links) gets a chance. Custom-scheme deep links
    // like `sunoh://playlist/abc` get parsed by Flutter as path `/abc`
    // (the `playlist` host is stripped) — that doesn't match any internal
    // route, so without this we'd surface the GoRouter error page and the
    // subsequent deep-link dispatch would push on top of a broken stack.
    //
    // Allow only the route prefixes we own; bounce everything else to
    // /home so the dispatcher's later `push(...)` lands cleanly on top.
    redirect: (context, state) {
      final loc = state.uri.path;
      const ownedPrefixes = ['/home', '/search', '/library', '/player'];
      final known = ownedPrefixes.any((p) => loc == p || loc.startsWith('$p/'));
      if (known) return null;
      return '/home';
    },
    routes: [
      StatefulShellRoute(
        builder: (context, state, navigationShell) =>
            AppScaffold(shell: navigationShell),
        // Same keep-alive model as indexedStack, with a fade on switch.
        navigatorContainerBuilder: (context, shell, children) =>
            BranchFade(index: shell.currentIndex, children: children),
        branches: [
          StatefulShellBranch(
            navigatorKey: _homeKey,
            routes: [
              GoRoute(
                path: '/home',
                pageBuilder: (c, s) => fadePage(const HomeScreen(), s),
                routes: _detailRoutes(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _searchKey,
            routes: [
              GoRoute(
                path: '/search',
                pageBuilder: (c, s) =>
                    // Not wrapped in _RootScroll: SearchScreen is its own
                    // CustomScrollView so its field and pills can pin.
                    fadePage(const SearchScreen(), s),
                routes: _detailRoutes(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _libraryKey,
            routes: [
              GoRoute(
                path: '/library',
                pageBuilder: (c, s) =>
                    fadePage(const _RootScroll(LibraryScreen()), s),
                routes: _detailRoutes(),
              ),
            ],
          ),
        ],
      ),

      // Full-screen modal routes (root navigator → above the shell).
      GoRoute(
        path: '/player',
        parentNavigatorKey: rootNavigatorKey,
        // Opens out of the mini player; closes by sliding down. See
        // player/player_route.dart.
        pageBuilder: (c, s) =>
            PlayerPage(key: s.pageKey, child: const ExpandedPlayer()),
        routes: [
          GoRoute(
            path: 'queue',
            parentNavigatorKey: rootNavigatorKey,
            pageBuilder: (c, s) => playerSheetPage(const QueueScreen(), s),
          ),
          GoRoute(
            path: 'lyrics',
            parentNavigatorKey: rootNavigatorKey,
            pageBuilder: (c, s) => slideUpPage(const LyricsScreen(), s),
          ),
        ],
      ),
    ],
  );
}

// Detail routes shared by every tab branch (fresh instances per branch).
// `?source=saavn|gaana|spotify` is read off the query string — the sunoh-api
// album/playlist endpoints route by provider hint.
/// The tapped cover a detail page flies in from, when it was opened by a tap.
CoverHeroRef? _heroOf(GoRouterState s) =>
    s.extra is CoverHeroRef ? s.extra as CoverHeroRef : null;

List<RouteBase> _detailRoutes() => [
  for (final kind in const ['album', 'playlist'])
    GoRoute(
      path: '$kind/:id',
      pageBuilder: (c, s) => pushPage(
        AlbumScreen(
          id: s.pathParameters['id']!,
          kind: kind,
          source: s.uri.queryParameters['source'],
          hero: _heroOf(s),
        ),
        s,
      ),
    ),
  GoRoute(
    path: 'artist/:id',
    pageBuilder: (c, s) => pushPage(
      ArtistScreen(
        id: s.pathParameters['id']!,
        source: s.uri.queryParameters['source'],
      ),
      s,
    ),
  ),
  GoRoute(
    path: 'podcast/:id',
    pageBuilder: (c, s) =>
        pushPage(PodcastShowScreen(id: s.pathParameters['id']!), s),
  ),
  GoRoute(
    path: 'podcast-episode/:guid',
    pageBuilder: (c, s) =>
        pushPage(EpisodeDetailScreen(guid: s.pathParameters['guid']!), s),
  ),
  GoRoute(
    path: 'podcast-categories',
    pageBuilder: (c, s) => pushPage(const PodcastCategoriesScreen(), s),
  ),
  GoRoute(
    path: 'podcast-category/:slug',
    pageBuilder: (c, s) {
      // `extra` carries the category name when navigating from the
      // categories grid so the per-category screen can show a clean
      // title without a second fetch.
      final name = s.extra is String ? s.extra as String : null;
      return pushPage(
        PodcastCategoryScreen(slug: s.pathParameters['slug']!, name: name),
        s,
      );
    },
  ),
  GoRoute(
    path: 'occasion/:slug',
    pageBuilder: (c, s) {
      // The originating FeedItem is passed via extras so the hero has
      // its title + artwork available before the detail fetch resolves
      // (avoids a flash of "?" in the hero).
      final item = s.extra is FeedItem ? s.extra as FeedItem : null;
      return pushPage(
        OccasionScreen(
          slug: s.pathParameters['slug']!,
          title: item?.title ?? s.pathParameters['slug']!,
          imageUrl: item?.artwork,
          source: s.uri.queryParameters['source'] ?? 'gaana',
        ),
        s,
      );
    },
  ),
  GoRoute(
    path: 'section',
    pageBuilder: (c, s) {
      final section = s.extra as HomeSection;
      return pushPage(SectionScreen(section: section), s);
    },
  ),
  GoRoute(
    path: 'settings',
    pageBuilder: (c, s) => pushPage(const SettingsScreen(), s),
  ),
  GoRoute(
    path: 'liked',
    pageBuilder: (c, s) => pushPage(const LikedSongsScreen(), s),
  ),
  GoRoute(
    path: 'history',
    pageBuilder: (c, s) => pushPage(const RecentlyPlayedScreen(), s),
  ),
  GoRoute(path: 'sync', pageBuilder: (c, s) => pushPage(const SyncScreen(), s)),
  GoRoute(
    path: 'local',
    pageBuilder: (c, s) => pushPage(const LocalLibraryScreen(), s),
  ),
  GoRoute(
    path: 'local-folders',
    pageBuilder: (c, s) => pushPage(const LocalFoldersScreen(), s),
  ),
  GoRoute(
    // `kind` is album|artist. The id is the grouping key, which embeds the
    // album and artist names, so it travels as a query parameter rather than
    // a path segment — names contain slashes.
    path: 'local-collection',
    pageBuilder: (c, s) => pushPage(
      LocalCollectionScreen(
        id: s.uri.queryParameters['id'] ?? '',
        album: s.uri.queryParameters['kind'] != 'artist',
      ),
      s,
    ),
  ),
  GoRoute(
    path: 'downloads',
    pageBuilder: (c, s) => pushPage(const DownloadsScreen(), s),
  ),
  GoRoute(
    path: 'user-playlist/:id',
    pageBuilder: (c, s) =>
        pushPage(UserPlaylistScreen(id: s.pathParameters['id']!), s),
  ),
  GoRoute(
    path: 'spotify-import',
    pageBuilder: (c, s) => pushPage(const SpotifyImportScreen(), s),
  ),
  // ── YouTube Music ──────────────────────────────────────────────
  // Separate from the generic detail routes because YouTube browse ids
  // (VLRDCLAK5uy_…, FEmusic_…) mean nothing to sunoh-api.
  GoRoute(
    path: 'yt-playlist/:id',
    pageBuilder: (c, s) {
      final (name, hero) = s.extra is (String?, CoverHeroRef?)
          ? s.extra! as (String?, CoverHeroRef?)
          : (null, null);
      return pushPage(
        YtPlaylistScreen(
          browseId: Uri.decodeComponent(s.pathParameters['id']!),
          name: name,
          hero: hero,
        ),
        s,
      );
    },
  ),
  GoRoute(
    path: 'yt-artist/:id',
    pageBuilder: (c, s) => pushPage(
      YtArtistScreen(
        browseId: Uri.decodeComponent(s.pathParameters['id']!),
        name: s.extra is String ? s.extra as String : null,
      ),
      s,
    ),
  ),
  GoRoute(
    path: 'yt-moods',
    pageBuilder: (c, s) => pushPage(const YtMoodsScreen(), s),
  ),
  GoRoute(
    path: 'yt-category/:id',
    pageBuilder: (c, s) {
      // `params` is opaque and travels with the browseId; passed via
      // extra alongside the display name rather than in the path.
      final extra = s.extra is Map ? s.extra as Map : const {};
      return pushPage(
        YtCategoryScreen(
          browseId: Uri.decodeComponent(s.pathParameters['id']!),
          params: (extra['params'] ?? '').toString(),
          name: extra['name'] as String?,
        ),
        s,
      );
    },
  ),
];

/// Scroll + safe-area padding for the non-scrolling tab screens (Column roots).
///
/// Home is deliberately not one of them: it owns a CustomScrollView so its
/// feed can be lazy. A SingleChildScrollView builds every child it is given,
/// which for a twenty-section feed meant rebuilding all of it on any theme
/// change.
class _RootScroll extends StatelessWidget {
  const _RootScroll(this.child);
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top,
        bottom: shellClearance(context),
      ),
      child: child,
    );
  }
}

// ── Navigation helpers ───────────────────────────────────────────────────────
extension SunohNav on BuildContext {
  String get _branchPrefix {
    final loc = GoRouterState.of(this).matchedLocation;
    if (loc.startsWith('/search')) return '/search';
    if (loc.startsWith('/library')) return '/library';
    return '/home';
  }

  /// Navigate to a detail screen for [ref].
  ///
  /// [hero] is the tapped cover's tag and art, so the page's big cover can
  /// fly in from it (widgets/cover_hero.dart).
  void openRef(DetailRef ref, {CoverHeroRef? hero}) {
    final src = ref.source;
    final query = (src == null || src.isEmpty)
        ? ''
        : '?source=${Uri.encodeQueryComponent(src)}';
    push('$_branchPrefix/${ref.kind}/${ref.id}$query', extra: hero);
  }

  void openPlayer() => push('/player');
  void openQueue() => push('/player/queue');
  void openLyrics() => push('/player/lyrics');

  /// Push the "See all" screen for a home-feed section.
  void openSection(HomeSection section) {
    push('$_branchPrefix/section', extra: section);
  }

  /// Push an occasion detail (browse-category contents). Pass the FeedItem
  /// so the hero has title + artwork available before the fetch resolves.
  ///
  /// Routes by `id`, NOT by `url` — Saavn channels ship `url` as a full
  /// `https://jiosaavn.com/s/channel/...` link which contains slashes
  /// that go_router can't match into the `:slug` param. The id field is
  /// the canonical slug for both gaana occasions and saavn channels;
  /// both work against `/music/occasions/<id>?provider=…`.
  void openOccasion(FeedItem occasion) {
    final slug = occasion.id;
    final src = occasion.source ?? 'gaana';
    push(
      '$_branchPrefix/occasion/${Uri.encodeComponent(slug)}'
      '?source=${Uri.encodeQueryComponent(src)}',
      extra: occasion,
    );
  }

  /// Push the settings screen inside the active tab branch.
  void openSettings() {
    push('$_branchPrefix/settings');
  }

  void openLikedSongs() => push('$_branchPrefix/liked');
  void openRecentlyPlayed() => push('$_branchPrefix/history');
  void openDownloads() => push('$_branchPrefix/downloads');

  /// The on-device music library.
  void openLocalLibrary() => push('$_branchPrefix/local');

  /// Which device folders count as music.
  void openLocalFolders() => push('$_branchPrefix/local-folders');

  /// Library sync setup and status.
  void openSync() => push('$_branchPrefix/sync');

  /// One on-device album or artist.
  void openLocalCollection(String id, {required bool album}) => push(
    '$_branchPrefix/local-collection'
    '?kind=${album ? 'album' : 'artist'}'
    '&id=${Uri.encodeQueryComponent(id)}',
  );
  void openUserPlaylist(String id) => push('$_branchPrefix/user-playlist/$id');
  void openPodcastEpisode(String guid) =>
      push('$_branchPrefix/podcast-episode/${Uri.encodeComponent(guid)}');
  void openPodcastCategories() => push('$_branchPrefix/podcast-categories');
  void openPodcastCategory(String slug, {String? name}) => push(
    '$_branchPrefix/podcast-category/${Uri.encodeComponent(slug)}',
    extra: name,
  );
  void openSpotifyImport() => push('$_branchPrefix/spotify-import');

  /// Open a YouTube Music playlist/album track list.
  void openYtPlaylist(String browseId, {String? name, CoverHeroRef? hero}) =>
      push(
        '$_branchPrefix/yt-playlist/${Uri.encodeComponent(browseId)}',
        extra: (name, hero),
      );

  /// Open a YouTube Music artist page.
  void openYtArtist(String browseId, {String? name}) => push(
    '$_branchPrefix/yt-artist/${Uri.encodeComponent(browseId)}',
    extra: name,
  );

  /// The moods & genres index.
  void openYtMoods() => push('$_branchPrefix/yt-moods');

  /// One mood/genre category.
  void openYtCategory({
    required String browseId,
    required String params,
    String? name,
  }) => push(
    '$_branchPrefix/yt-category/${Uri.encodeComponent(browseId)}',
    extra: {'params': params, 'name': name},
  );

  /// Dispatch a YouTube feed item by type. Songs play immediately (there's
  /// no track detail screen); collections open their track list.
  void openYtItem(FeedItem item, {CoverHeroRef? hero}) {
    switch (item.type) {
      case 'playlist':
      case 'album':
        openYtPlaylist(item.id, name: item.title, hero: hero);
      case 'artist':
        openYtArtist(item.id, name: item.title);
      default:
        // Songs deliberately do not land here: playing one is the caller's
        // job, because it needs the surrounding list to build a queue from
        // and this extension only knows how to navigate. Logged rather than
        // ignored — a silent `break` here is what made tapping a liked song
        // do nothing at all, with no error to find.
        debugPrint('[deeplink] openYtItem: nothing to open for ${item.type}');
    }
  }
}
