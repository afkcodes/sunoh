// What a signed-in YouTube account adds: who you are, and your own library.
//
// The personalized home feed is deliberately not here. `home()` already
// browses `FEmusic_home`, and once a session exists every call through `_post`
// carries its headers — so the same request that returns generic charts
// signed out returns Quick picks and Listen again signed in. Writing a second
// "personalized home" path would mean two ways to fetch one page, which drift.
//
// Only the endpoints that are meaningless without an account live here.

part of 'ytmusic_api.dart';

/// Library browse ids. Opaque to us; these are what the web client asks for.
const _kLikedSongs = 'FEmusic_liked_videos';
const _kLikedPlaylists = 'FEmusic_liked_playlists';
const _kLikedAlbums = 'FEmusic_liked_albums';
const _kLibraryArtists = 'FEmusic_library_corpus_track_artists';

extension YtMusicAccount on YtMusicApi {
  /// The signed-in account's display name, or null when the session is not
  /// usable. Worth calling right after sign-in for that second reason as much
  /// as the first: it is the cheapest proof that the cookie actually
  /// authenticates, rather than merely existing.
  Future<String?> accountName() async {
    try {
      final body = await _post('account/account_menu', _context);
      if (body == null) return null;
      final header = _findRenderer(body, 'activeAccountHeaderRenderer');
      final name = _nodeText(_asMap(header?['accountName']));
      return name.isEmpty ? null : name;
    } catch (_) {
      return null;
    }
  }

  /// Your own library: liked songs, playlists, albums and artists.
  ///
  /// Fetched concurrently, and a page that fails contributes nothing rather
  /// than failing the lot — the same rule the home feed follows, and it
  /// matters more here, because these four are independent and a signed-in
  /// user with no saved albums is not an error.
  Future<List<HomeSection>> library() async {
    final pages = await Future.wait([
      _libraryPage(_kLikedSongs, 'Liked songs'),
      _libraryPage(_kLikedPlaylists, 'Your playlists'),
      _libraryPage(_kLikedAlbums, 'Your albums'),
      _libraryPage(_kLibraryArtists, 'Your artists'),
    ]);
    return [for (final page in pages) ?page];
  }

  /// One library page as a single section.
  ///
  /// Library pages come back as grids and lists rather than the carousels the
  /// home feed uses, so the shelf parsing is different — but the heading is
  /// ours rather than YouTube's, because these pages title themselves things
  /// like "Playlists" that read wrong beside our own library's rows.
  Future<HomeSection?> _libraryPage(String browseId, String heading) async {
    try {
      final body = await _post('browse', {..._context, 'browseId': browseId});
      if (body == null) return null;
      final shelves = _singleColumnShelves(body);
      final items = _libraryItems(shelves);
      // Same 100-row ceiling the playlist screen hit: a library with more
      // liked songs than that served the first hundred and stopped. The token
      // is read off the shelf that holds the rows rather than off the page,
      // which on these pages also carries the sidebar's own continuations.
      String? more;
      for (final shelf in shelves) {
        more ??= _continuationOf(shelf);
      }
      for (final raw in await _continuationRows(more)) {
        final m = _asMap(raw);
        if (m == null) continue;
        final item = _parseTwoRowItem(m) ?? _parseResponsiveItem(m);
        if (item != null) items.add(item);
      }
      if (items.isEmpty) return null;
      return HomeSection(heading: heading, items: items, source: 'youtube');
    } catch (_) {
      return null;
    }
  }
}

/// Items out of a library page's grids and shelves.
///
/// Three shapes, because YouTube uses all three on these pages: a grid of
/// two-row cards (albums, playlists, artists), a list shelf of responsive
/// rows (liked songs), and occasionally a carousel like the home feed's.
List<FeedItem> _libraryItems(List<Map<String, dynamic>> shelves) {
  final items = <FeedItem>[];
  for (final shelf in shelves) {
    final containers = [
      _asMap(shelf['gridRenderer']),
      _asMap(shelf['musicShelfRenderer']),
      _asMap(shelf['musicCarouselShelfRenderer']),
    ];
    for (final container in containers) {
      if (container == null) continue;
      for (final raw in [
        ..._asList(container['items']),
        ..._asList(container['contents']),
      ]) {
        final m = _asMap(raw);
        if (m == null) continue;
        final item = _parseTwoRowItem(m) ?? _parseResponsiveItem(m);
        if (item != null) items.add(item);
      }
    }
  }
  return items;
}

/// The first renderer stored under [key], anywhere in the tree.
///
/// A hardcoded path was tried twice and moved twice: the account name sat
/// under `multiPageMenuRenderer.header` in the shape this was written against
/// and under `sections` in the one YouTube actually returns. Searching for the
/// renderer by name survives that reshuffling, which is the only thing that
/// can be relied on in a tree this volatile.
///
/// Depth-limited, because the response is large and the answer is always near
/// the top; an unbounded walk would be a lot of work to find nothing on the
/// day the renderer is renamed.
Map<String, dynamic>? _findRenderer(Object? node, String key, [int depth = 0]) {
  if (depth > 12) return null;
  if (node is Map) {
    final here = node[key];
    if (here is Map) return here.cast<String, dynamic>();
    for (final value in node.values) {
      final found = _findRenderer(value, key, depth + 1);
      if (found != null) return found;
    }
  } else if (node is List) {
    for (final value in node) {
      final found = _findRenderer(value, key, depth + 1);
      if (found != null) return found;
    }
  }
  return null;
}

/// Text out of a node that may carry either shape. InnerTube uses `runs` for
/// anything that could be styled and `simpleText` when it never is, and which
/// one a given field uses is not stable.
String _nodeText(Map<String, dynamic>? node) {
  if (node == null) return '';
  final runs = _runsText(node);
  if (runs.isNotEmpty) return runs;
  final simple = node['simpleText'];
  return simple is String ? simple : '';
}
