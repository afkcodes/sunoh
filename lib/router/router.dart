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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/models.dart';
import '../overlays/lyrics_screen.dart';
import '../overlays/queue_screen.dart';
import '../player/expanded_player.dart';
import '../providers/app_state_provider.dart';
import '../api/dto.dart';
import '../screens/detail_screens.dart';
import '../screens/home_screen.dart';
import '../screens/library_screen.dart';
import '../screens/liked_songs_screen.dart';
import '../screens/recently_played_screen.dart';
import '../screens/search_screen.dart';
import '../screens/section_screen.dart';
import '../screens/settings_screen.dart';
import '../shell/app_scaffold.dart';

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
      final known =
          ownedPrefixes.any((p) => loc == p || loc.startsWith('$p/'));
      if (known) return null;
      return '/home';
    },
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppScaffold(shell: navigationShell),
        branches: [
          StatefulShellBranch(
            navigatorKey: _homeKey,
            routes: [
              GoRoute(
                path: '/home',
                pageBuilder: (c, s) => _fade(const _RootScroll(HomeScreen()), s),
                routes: _detailRoutes(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _searchKey,
            routes: [
              GoRoute(
                path: '/search',
                pageBuilder: (c, s) => _fade(const _RootScroll(SearchScreen()), s),
                routes: _detailRoutes(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _libraryKey,
            routes: [
              GoRoute(
                path: '/library',
                pageBuilder: (c, s) => _fade(const _RootScroll(LibraryScreen()), s),
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
        // Asymmetric: slide-up + fade on open; fade-out only on close (Hero
        // contracts the album art back into the mini player — no double slide).
        pageBuilder: (c, s) => _playerTransition(const ExpandedPlayer(), s),
        routes: [
          GoRoute(
            path: 'queue',
            parentNavigatorKey: rootNavigatorKey,
            pageBuilder: (c, s) => _slideUp(const QueueScreen(), s),
          ),
          GoRoute(
            path: 'lyrics',
            parentNavigatorKey: rootNavigatorKey,
            pageBuilder: (c, s) => _slideUp(const LyricsScreen(), s),
          ),
        ],
      ),
    ],
  );
}

// Detail routes shared by every tab branch (fresh instances per branch).
// `?source=saavn|gaana|spotify` is read off the query string — the sunoh-api
// album/playlist endpoints route by provider hint.
List<RouteBase> _detailRoutes() => [
      GoRoute(
        path: 'album/:id',
        pageBuilder: (c, s) => _slideRight(
            AlbumScreen(
              id: s.pathParameters['id']!,
              kind: 'album',
              source: s.uri.queryParameters['source'],
            ),
            s),
      ),
      GoRoute(
        path: 'playlist/:id',
        pageBuilder: (c, s) => _slideRight(
            AlbumScreen(
              id: s.pathParameters['id']!,
              kind: 'playlist',
              source: s.uri.queryParameters['source'],
            ),
            s),
      ),
      GoRoute(
        path: 'artist/:id',
        pageBuilder: (c, s) => _slideRight(
            ArtistScreen(
              id: s.pathParameters['id']!,
              source: s.uri.queryParameters['source'],
            ),
            s),
      ),
      GoRoute(
        path: 'podcast/:id',
        pageBuilder: (c, s) => _slideRight(PodcastScreen(id: s.pathParameters['id']!), s),
      ),
      GoRoute(
        path: 'occasion/:slug',
        pageBuilder: (c, s) {
          // The originating FeedItem is passed via extras so the hero has
          // its title + artwork available before the detail fetch resolves
          // (avoids a flash of "?" in the hero).
          final item = s.extra is FeedItem ? s.extra as FeedItem : null;
          return _slideRight(
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
          return _slideRight(SectionScreen(section: section), s);
        },
      ),
      GoRoute(
        path: 'settings',
        pageBuilder: (c, s) => _slideRight(const SettingsScreen(), s),
      ),
      GoRoute(
        path: 'liked',
        pageBuilder: (c, s) => _slideRight(const LikedSongsScreen(), s),
      ),
      GoRoute(
        path: 'history',
        pageBuilder: (c, s) => _slideRight(const RecentlyPlayedScreen(), s),
      ),
    ];

/// Scroll + safe-area padding for the non-scrolling tab screens (Column roots).
class _RootScroll extends StatelessWidget {
  const _RootScroll(this.child);
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top, bottom: 140),
      child: child,
    );
  }
}

// ── Transition pages ────────────────────────────────────────────────────────
CustomTransitionPage<void> _fade(Widget child, GoRouterState state) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 200),
    transitionsBuilder: (c, a, sa, ch) => FadeTransition(opacity: a, child: ch),
  );
}

CustomTransitionPage<void> _slideRight(Widget child, GoRouterState state) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    transitionsBuilder: (c, a, sa, ch) {
      final curved = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
      return SlideTransition(
        position: Tween(begin: const Offset(0.06, 0), end: Offset.zero).animate(curved),
        child: FadeTransition(opacity: curved, child: ch),
      );
    },
  );
}

CustomTransitionPage<void> _slideUp(Widget child, GoRouterState state) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: Material(type: MaterialType.transparency, child: child),
    opaque: false,
    transitionDuration: const Duration(milliseconds: 340),
    reverseTransitionDuration: const Duration(milliseconds: 280),
    transitionsBuilder: (c, a, sa, ch) {
      final curved = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
      return SlideTransition(
        position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(curved),
        child: ch,
      );
    },
  );
}

/// Asymmetric transition used by `/player`: open = slide-up + fade. Close =
/// pure fade-out (no slide), so the Hero-flying album art is the visual focus
/// and the sheet appears to *contract* into the mini player rather than slide
/// away.
CustomTransitionPage<void> _playerTransition(Widget child, GoRouterState state) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: Material(type: MaterialType.transparency, child: child),
    opaque: false,
    transitionDuration: const Duration(milliseconds: 340),
    reverseTransitionDuration: const Duration(milliseconds: 320),
    transitionsBuilder: (c, a, sa, ch) {
      final closing = a.status == AnimationStatus.reverse;
      final curved =
          CurvedAnimation(parent: a, curve: Curves.easeOutCubic, reverseCurve: Curves.easeIn);
      if (closing) {
        return FadeTransition(opacity: curved, child: ch);
      }
      return SlideTransition(
        position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(curved),
        child: FadeTransition(opacity: curved, child: ch),
      );
    },
  );
}

// ── Navigation helpers ───────────────────────────────────────────────────────
extension SunohNav on BuildContext {
  String get _branchPrefix {
    final loc = GoRouterState.of(this).matchedLocation;
    if (loc.startsWith('/search')) return '/search';
    if (loc.startsWith('/library')) return '/library';
    return '/home';
  }

  /// Navigate to a detail (or, for a station, start playback + open the player).
  void openRef(DetailRef ref) {
    if (ref.kind == 'station') {
      // Reach the AppState from the nearest ProviderScope (extension is on
      // BuildContext, so we don't have a WidgetRef here).
      ProviderScope.containerOf(this).read(appStateProvider).playStation(ref.id);
      push('/player');
      return;
    }
    final src = ref.source;
    final query = (src == null || src.isEmpty)
        ? ''
        : '?source=${Uri.encodeQueryComponent(src)}';
    push('$_branchPrefix/${ref.kind}/${ref.id}$query');
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
}
