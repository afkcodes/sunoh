// YouTube Music search + browse, spoken directly from Dart.
//
// Split of responsibility with the native side:
//
//   - `/youtubei/v1/player` (stream resolution) is gated behind a BotGuard
//     bot check for the music catalog, needs a PO token minted in a WebView,
//     and therefore lives in Kotlin — see ytmusic_channel.dart.
//   - `/youtubei/v1/search` and `/browse` are NOT gated. They answer plain
//     unauthenticated requests, so there's no reason to cross the platform
//     channel (or port InnerTube's renderer models to Kotlin) for them.
//
// Responses are InnerTube's renderer tree: deeply nested, positional, and
// full of optional keys. Every accessor here is defensive — a shape change
// upstream should cost us a missing row, not an exception.

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/env.dart';
import 'dto.dart';
import 'yt_auth_channel.dart';
import 'yt_locale.dart';

/// Renderer-tree parsing. See the file header there for why it is split out.
part 'ytmusic_renderers.dart';

/// The signed-in surface: account identity and your own library.
part 'ytmusic_account.dart';

/// Supplies the headers for one authenticated InnerTube call, or an empty map
/// when signed out.
typedef AuthHeaders = Future<Map<String, String>> Function();

/// The YouTube Music web client. No API key or auth needed for search/browse.
const _kClientName = 'WEB_REMIX';
const _kClientVersion = '1.20260101.01.00';
const _kBase = Env.ytMusicBase;

/// `params` filters pinning search to one result type. Opaque
/// protobuf-derived values from the web client.
const _kSongsOnlyParams = 'EgWKAQIIAWoKEAoQAxAEEAkQBQ%3D%3D';
const _kArtistsOnlyParams = 'EgWKAQIgAWoKEAoQAxAEEAkQBQ%3D%3D';
const _kAlbumsOnlyParams = 'EgWKAQIYAWoKEAoQAxAEEAkQBQ%3D%3D';

/// A mood/genre chip from `FEmusic_moods_and_genres`.
class YtCategoryChip {
  const YtCategoryChip({
    required this.title,
    required this.browseId,
    required this.params,
    this.color,
  });
  final String title;
  final String browseId;
  final String params;

  /// ARGB int supplied by YouTube for the chip's stripe. Used as a tint so
  /// the grid doesn't read as 38 identical grey pills.
  final int? color;
}

/// One grid from the moods & genres page ("Moods & moments", "Genres").
class YtCategoryGroup {
  const YtCategoryGroup({required this.title, required this.chips});
  final String title;
  final List<YtCategoryChip> chips;
}

/// A YouTube Music playlist/album with its tracks.
class YtPlaylistDetail {
  const YtPlaylistDetail({
    required this.id,
    required this.title,
    required this.tracks,
    this.subtitle,
    this.description,
    this.artwork,
  });
  final String id;
  final String title;
  final String? subtitle;
  final String? description;
  final String? artwork;
  final List<FeedItem> tracks;
}

/// A YouTube Music artist page.
class YtArtistDetail {
  const YtArtistDetail({
    required this.id,
    required this.name,
    required this.topSongs,
    required this.sections,
    this.subtitle,
    this.description,
    this.artwork,
    this.radioVideoId,
    this.radioPlaylistId,
    this.shuffleVideoId,
    this.shufflePlaylistId,
  });
  final String id;
  final String name;
  final String? subtitle;
  final String? description;
  final String? artwork;
  final List<FeedItem> topSongs;
  final List<HomeSection> sections;

  /// Seed for the artist's endless station (`startRadioButton`). Both halves
  /// are needed — /next keys the queue off the pair.
  final String? radioVideoId;
  final String? radioPlaylistId;

  /// Seed for "play all, shuffled" (`playButton`).
  final String? shuffleVideoId;
  final String? shufflePlaylistId;

  bool get hasRadio =>
      (radioPlaylistId ?? '').isNotEmpty && (radioVideoId ?? '').isNotEmpty;
}

/// How far past the first page of the personalized home feed to read.
///
/// Four is enough to reach the rows a signed-in account actually recognises as
/// theirs without turning one home render into a dozen requests.
const int _kHomeExtraPages = 4;

class YtMusicApi {
  YtMusicApi(this._dio, {this.locale = YtLocale.fallback, AuthHeaders? auth})
    : _auth = auth ?? YtAuthChannel.instance.headers;
  final Dio _dio;

  /// Where the signed-in session's headers come from, injectable so a test can
  /// drive both the anonymous and authenticated paths without a device.
  final AuthHeaders _auth;

  /// Region and interface language for every request. `gl` in particular
  /// decides which charts and home rows come back, so a wrong value is the
  /// difference between Indian and American content.
  final YtLocale locale;

  Map<String, dynamic> get _context => {
    'context': {
      'client': {
        'clientName': _kClientName,
        'clientVersion': _kClientVersion,
        'hl': locale.language,
        'gl': locale.country,
      },
    },
  };

  Options _optionsWith(Map<String, String> auth) => Options(
    headers: {
      'Content-Type': 'application/json',
      'X-Youtube-Client-Name': '67',
      'X-Youtube-Client-Version': _kClientVersion,
      // Not configuration: InnerTube validates the origin, and the SAPISIDHASH
      // is computed over this exact string on the native side. It is part of
      // the request contract rather than something a build points elsewhere.
      'Origin': 'https://music.youtube.com',
      ...auth,
    },
    validateStatus: (s) => s != null && s < 500,
  );

  /// Every call goes through here, which is why authentication is applied
  /// here and nowhere else: signing in changes what search, browse and next
  /// return, and a caller that had to remember to ask for it would eventually
  /// forget on one path and serve a signed-in user someone else's home page.
  ///
  /// Signed out, [auth] is empty and the request is byte-for-byte what it was
  /// before any of this existed.
  Future<Map<String, dynamic>?> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final auth = await _auth();
    final res = await _dio.post<Map<String, dynamic>>(
      '$_kBase/$path?prettyPrint=false',
      data: _withVisitorData(body, auth['X-Goog-Visitor-Id']),
      options: _optionsWith(auth),
    );
    return res.data;
  }

  /// InnerTube wants `visitorData` in the request context as well as in the
  /// header. Injected here rather than in [_context] so the call sites stay as
  /// they are, and so an anonymous request keeps the exact body it had.
  static Map<String, dynamic> _withVisitorData(
    Map<String, dynamic> body,
    String? visitorData,
  ) {
    if (visitorData == null || visitorData.isEmpty) return body;
    final context = body['context'];
    if (context is! Map) return body;
    final client = context['client'];
    if (client is! Map) return body;
    return {
      ...body,
      'context': {
        ...context.cast<String, dynamic>(),
        'client': {
          ...client.cast<String, dynamic>(),
          'visitorData': visitorData,
        },
      },
    };
  }

  // ── Public API ────────────────────────────────────────────────────────

  /// Full-text song search. Items carry `source: 'youtube'` and the videoId
  /// as `id`, which routes them to StreamResolver's native YouTube tier.
  Future<List<FeedItem>> searchSongs(String query) async {
    if (query.trim().isEmpty) return const [];
    final body = await _post('search', {
      ..._context,
      'query': query,
      'params': _kSongsOnlyParams,
    });
    if (body == null) return const [];
    final out = <FeedItem>[];
    for (final shelf in _searchShelves(body)) {
      for (final raw in _asList(shelf['contents'])) {
        final item = _parseResponsiveItem(_asMap(raw));
        if (item != null) out.add(item);
      }
    }
    return out;
  }

  /// Artist results. Their ids are channel ids that open the artist page.
  Future<List<FeedItem>> searchArtists(String query) =>
      _searchFiltered(query, _kArtistsOnlyParams);

  /// Album results.
  Future<List<FeedItem>> searchAlbums(String query) =>
      _searchFiltered(query, _kAlbumsOnlyParams);

  Future<List<FeedItem>> _searchFiltered(String query, String params) async {
    if (query.trim().isEmpty) return const [];
    try {
      final body = await _post('search', {
        ..._context,
        'query': query,
        'params': params,
      });
      if (body == null) return const [];
      final out = <FeedItem>[];
      for (final shelf in _searchShelves(body)) {
        for (final raw in _asList(shelf['contents'])) {
          final item = _parseResponsiveItem(_asMap(raw));
          if (item != null) out.add(item);
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// The YouTube Music home feed.
  ///
  /// `FEmusic_home` alone returns only two or three shelves when
  /// unauthenticated, and its continuation token yields zero more (verified
  /// against query-param and body-style continuations, with and without
  /// visitorData) — the deeper feed is behind sign-in. So we compose the
  /// other public browse pages instead, which need no auth and carry the
  /// bulk of the interesting rows.
  ///
  /// Fetched concurrently; any page that fails contributes nothing rather
  /// than failing the feed.
  Future<List<HomeSection>> home() async {
    final pages = await Future.wait([
      // Only the personalized page is paged. The editorial ones below are
      // fixed shelves that do not grow with scrolling, so a continuation
      // would cost a round trip to learn there is nothing more.
      _browseSections('FEmusic_home', extraPages: _kHomeExtraPages),
      _browseSections('FEmusic_explore'),
      _browseSections('FEmusic_charts'),
      _browseSections('FEmusic_new_releases'),
    ]);

    // Dedupe by heading — `New albums & singles` shows up on both explore
    // and new-releases, and the charts page repeats some of home's rows.
    final seen = <String>{};
    final out = <HomeSection>[];
    for (final section in pages.expand((p) => p)) {
      final key = section.heading.trim().toLowerCase();
      if (key.isEmpty || !seen.add(key)) continue;
      // Moods & genres arrives as a carousel of chips; we render those as
      // their own row from `moodsAndGenres()`, so drop the duplicate.
      if (key.contains('moods') || key.contains('genres')) continue;
      out.add(section);
    }
    return out;
  }

  /// One browse page, plus up to [extraPages] continuations.
  ///
  /// YouTube Music serves its home feed a few shelves at a time and the web
  /// client fetches the rest as the page is scrolled. Reading only the first
  /// response is why this returned three rows where music.youtube.com shows
  /// thirty.
  ///
  /// Paging is capped rather than exhaustive. The feed is effectively endless,
  /// each page is a network round trip, and rows nobody scrolls to cost the
  /// same as rows they do. A page that fails ends the walk and keeps what came
  /// before it, so a flaky continuation costs the tail of the feed rather than
  /// the whole thing.
  Future<List<HomeSection>> _browseSections(
    String browseId, {
    int extraPages = 0,
  }) async {
    try {
      final body = await _post('browse', {..._context, 'browseId': browseId});
      if (body == null) return const [];
      final sections = [..._carouselSections(_singleColumnShelves(body))];

      var token = extraPages > 0 ? _continuationOf(body) : null;
      for (var page = 0; page < extraPages && token != null; page++) {
        final next = await _post('browse', {
          ..._context,
          'continuation': token,
        });
        if (next == null) break;
        final shelves = _continuationShelves(next);
        if (shelves.isEmpty) break;
        sections.addAll(_carouselSections(shelves));
        token = _continuationOf(next);
      }
      debugPrint(
        '[ytmusic] $browseId: ${sections.length} sections '
        'over ${extraPages > 0 ? 'up to ${extraPages + 1}' : '1'} page(s)',
      );
      return sections;
    } catch (_) {
      return const [];
    }
  }

  /// An artist page: header, top songs, and the discography carousels.
  Future<YtArtistDetail?> artist(String browseId) async {
    final body = await _post('browse', {..._context, 'browseId': browseId});
    if (body == null) {
      // ignore: avoid_print
      print('[ytmusic] artist $browseId: empty response');
      return null;
    }

    // Artist pages come in two shapes and YouTube serves both:
    //
    //   - the classic one, with `musicImmersiveHeaderRenderer` at the top
    //     level and a single-column body, and
    //   - the newer two-column layout (the same one playlists use), where
    //     the header is a `musicResponsiveHeaderRenderer` inside the
    //     primary column.
    //
    // Handling only the first meant some artists parsed to null and the
    // screen showed "not available".
    final header = _artistHeader(body);
    final name = _runsText(_asMap(header?['title']));
    if (name.isEmpty) {
      // ignore: avoid_print
      print(
        '[ytmusic] artist $browseId: no name. '
        'top=${body.keys.toList()} '
        'header=${_asMap(body['header'])?.keys.toList()} '
        'contents=${_asMap(body['contents'])?.keys.toList()}',
      );
      return null;
    }

    final thumbs = header == null ? const <ApiImage>[] : _thumbnails(header);
    final artistArt = _largestArt(thumbs);
    final description = _runsText(_asMap(header?['description']));
    final listeners = _runsText(_asMap(header?['monthlyListenerCount']));

    // The classic header names these buttons; the two-column one puts them
    // in a `buttons` list. Fall back to scanning that, picking the seed out
    // by its playlist prefix — radio mixes are RD*, everything else is the
    // plain "play all".
    var radio = _watchSeed(_asMap(header?['startRadioButton']));
    var play = _watchSeed(_asMap(header?['playButton']));
    if (radio == null || play == null) {
      for (final b in _asList(header?['buttons'])) {
        final seed = _watchSeed(_asMap(b));
        if (seed == null) continue;
        if (seed.$2.startsWith('RD')) {
          radio ??= seed;
        } else {
          play ??= seed;
        }
      }
    }

    // Top songs arrive as a list shelf; everything else as carousels.
    final topSongs = <FeedItem>[];
    final sections = <HomeSection>[];
    for (final shelf in _artistShelves(body)) {
      final list = _asMap(shelf['musicShelfRenderer']);
      if (list != null) {
        for (final raw in _asList(list['contents'])) {
          final item = _parseResponsiveItem(_asMap(raw));
          if (item != null) topSongs.add(item);
        }
        continue;
      }
      sections.addAll(_carouselSections([shelf]));
    }

    return YtArtistDetail(
      id: browseId,
      name: name,
      subtitle: listeners.isEmpty ? null : listeners,
      description: description.isEmpty ? null : description,
      artwork: artistArt,
      topSongs: topSongs,
      sections: sections,
      radioVideoId: radio?.$1,
      radioPlaylistId: radio?.$2,
      shuffleVideoId: play?.$1,
      shufflePlaylistId: play?.$2,
    );
  }

  /// Tracks for a station / queue, via `/next`.
  ///
  /// Radio playlists are generated server-side and can't be browsed like a
  /// normal playlist — `/next` with the (videoId, playlistId) seed is the
  /// only way to materialise one.
  Future<List<FeedItem>> radioQueue({
    required String videoId,
    required String playlistId,
  }) async {
    final body = await _post('next', {
      ..._context,
      'videoId': videoId,
      'playlistId': playlistId,
      'isAudioOnly': true,
    });
    if (body == null) return const [];
    final tabs = _asList(
      _dig(body, [
        'contents',
        'singleColumnMusicWatchNextResultsRenderer',
        'tabbedRenderer',
        'watchNextTabbedResultsRenderer',
        'tabs',
      ]),
    );
    for (final tab in tabs) {
      final items = _asList(
        _dig(_asMap(tab), [
          'tabRenderer',
          'content',
          'musicQueueRenderer',
          'content',
          'playlistPanelRenderer',
          'contents',
        ]),
      );
      final out = <FeedItem>[];
      for (final raw in items) {
        final r = _asMap(_asMap(raw)?['playlistPanelVideoRenderer']);
        if (r == null) continue;
        final id = r['videoId'] as String?;
        final title = _runsText(_asMap(r['title']));
        if (id == null || id.isEmpty || title.isEmpty) continue;
        final byline = _runsText(_asMap(r['longBylineText'])).split(' • ');
        out.add(
          FeedItem(
            id: id,
            title: title,
            type: 'song',
            source: 'youtube',
            image: _thumbnails(r),
            subtitle: byline.isEmpty ? null : byline.first,
            duration: _durationToSeconds(
              _runsText(_asMap(r['lengthText'])),
            )?.toString(),
          ),
        );
      }
      if (out.isNotEmpty) return out;
    }
    return const [];
  }

  /// The artist header, from whichever layout this page uses.
  Map<String, dynamic>? _artistHeader(Map<String, dynamic> body) {
    final immersive = _asMap(
      _dig(body, ['header', 'musicImmersiveHeaderRenderer']),
    );
    if (immersive != null) return immersive;

    // Two-column layout: header lives in the primary column.
    for (final tab in _asList(
      _dig(body, ['contents', 'twoColumnBrowseResultsRenderer', 'tabs']),
    )) {
      for (final sec in _asList(
        _dig(_asMap(tab), [
          'tabRenderer',
          'content',
          'sectionListRenderer',
          'contents',
        ]),
      )) {
        final m = _asMap(sec);
        final h =
            _asMap(m?['musicResponsiveHeaderRenderer']) ??
            _asMap(m?['musicImmersiveHeaderRenderer']);
        if (h != null) return h;
      }
    }
    // Some variants put a plain header renderer at the top level.
    return _asMap(_dig(body, ['header', 'musicHeaderRenderer'])) ??
        _asMap(_dig(body, ['header', 'musicVisualHeaderRenderer']));
  }

  /// Content shelves for an artist page, from either layout.
  List<Map<String, dynamic>> _artistShelves(Map<String, dynamic> body) {
    final single = _singleColumnShelves(body);
    if (single.isNotEmpty) return single;
    final out = <Map<String, dynamic>>[];
    for (final sec in _asList(
      _dig(body, [
        'contents',
        'twoColumnBrowseResultsRenderer',
        'secondaryContents',
        'sectionListRenderer',
        'contents',
      ]),
    )) {
      final m = _asMap(sec);
      if (m != null) out.add(m);
    }
    return out;
  }

  /// `(videoId, playlistId)` from a header button's watch endpoint.
  (String, String)? _watchSeed(Map<String, dynamic>? button) {
    final we = _asMap(
      _dig(button, ['buttonRenderer', 'navigationEndpoint', 'watchEndpoint']),
    );
    final v = we?['videoId'] as String?;
    final p = we?['playlistId'] as String?;
    if (v == null || p == null || v.isEmpty || p.isEmpty) return null;
    return (v, p);
  }

  /// Mood and genre chip grids (`FEmusic_moods_and_genres`).
  Future<List<YtCategoryGroup>> moodsAndGenres() async {
    final body = await _post('browse', {
      ..._context,
      'browseId': 'FEmusic_moods_and_genres',
    });
    if (body == null) return const [];
    final groups = <YtCategoryGroup>[];
    for (final sec in _singleColumnShelves(body)) {
      final grid = _asMap(sec['gridRenderer']);
      if (grid == null) continue;
      final title = _runsText(
        _asMap(_dig(grid, ['header', 'gridHeaderRenderer', 'title'])),
      );
      final chips = <YtCategoryChip>[];
      for (final raw in _asList(grid['items'])) {
        final btn = _asMap(_asMap(raw)?['musicNavigationButtonRenderer']);
        if (btn == null) continue;
        final label = _runsText(_asMap(btn['buttonText']));
        final endpoint = _asMap(_dig(btn, ['clickCommand', 'browseEndpoint']));
        final browseId = endpoint?['browseId'] as String?;
        final params = endpoint?['params'] as String?;
        if (label.isEmpty || browseId == null || params == null) continue;
        chips.add(
          YtCategoryChip(
            title: label,
            browseId: browseId,
            params: params,
            color: (_dig(btn, ['solid', 'leftStripeColor']) as num?)?.toInt(),
          ),
        );
      }
      if (chips.isNotEmpty) {
        groups.add(
          YtCategoryGroup(
            title: title.isEmpty ? 'Browse' : title,
            chips: chips,
          ),
        );
      }
    }
    return groups;
  }

  /// Contents of one mood/genre category — carousels of playlists.
  Future<List<HomeSection>> category(String browseId, String params) async {
    final body = await _post('browse', {
      ..._context,
      'browseId': browseId,
      'params': params,
    });
    if (body == null) return const [];
    return _carouselSections(_singleColumnShelves(body));
  }

  /// A playlist/album and its tracks.
  ///
  /// Playlist detail uses a two-column layout: the header (title, art,
  /// description) sits in the primary column and the track list in
  /// `secondaryContents` — unlike home/search, which are single-column.
  Future<YtPlaylistDetail?> playlist(String browseId) async {
    final body = await _post('browse', {..._context, 'browseId': browseId});
    if (body == null) return null;
    final two = _asMap(
      _dig(body, ['contents', 'twoColumnBrowseResultsRenderer']),
    );
    if (two == null) return null;

    // Header — primary column.
    String title = '';
    String? subtitle;
    String? description;
    String? artwork;
    final tabs = _asList(two['tabs']);
    for (final tab in tabs) {
      final contents = _asList(
        _dig(_asMap(tab), [
          'tabRenderer',
          'content',
          'sectionListRenderer',
          'contents',
        ]),
      );
      for (final sec in contents) {
        final h = _asMap(_asMap(sec)?['musicResponsiveHeaderRenderer']);
        if (h == null) continue;
        title = _runsText(_asMap(h['title']));
        subtitle = _runsText(_asMap(h['subtitle']));
        description = _runsText(_asMap(h['description']));
        artwork = _largestArt(_thumbnails(h));
      }
    }

    // Tracks — secondary column.
    final tracks = <FeedItem>[];
    final secContents = _asList(
      _dig(two, ['secondaryContents', 'sectionListRenderer', 'contents']),
    );
    for (final sec in secContents) {
      final shelf =
          _asMap(_asMap(sec)?['musicPlaylistShelfRenderer']) ??
          _asMap(_asMap(sec)?['musicShelfRenderer']);
      if (shelf == null) continue;
      for (final raw in _asList(shelf['contents'])) {
        final item = _parseResponsiveItem(_asMap(raw));
        if (item != null) tracks.add(item);
      }
    }

    // Album and playlist track rows carry no thumbnail of their own — the
    // art is shared and rendered once in the header — so every row would
    // otherwise fall back to a generated cover. Backfill from the header.
    final headerArt = artwork;
    final withArt = headerArt == null
        ? tracks
        : [
            for (final t in tracks)
              t.image.isNotEmpty
                  ? t
                  : _withImages(t, [
                      ApiImage(
                        quality: '${_kMaxArtSize}x$_kMaxArtSize',
                        link: headerArt,
                      ),
                    ]),
          ];

    if (title.isEmpty && withArt.isEmpty) return null;
    return YtPlaylistDetail(
      id: browseId,
      title: title.isEmpty ? 'Playlist' : title,
      subtitle: (subtitle ?? '').isEmpty ? null : subtitle,
      description: (description ?? '').isEmpty ? null : description,
      artwork: artwork,
      tracks: withArt,
    );
  }

  /// FeedItem is immutable and has no copyWith, so rebuild it with the
  /// supplied artwork and every other field carried across untouched.
  FeedItem _withImages(FeedItem item, List<ApiImage> image) => FeedItem(
    id: item.id,
    title: item.title,
    type: item.type,
    image: image,
    subtitle: item.subtitle,
    source: item.source,
    language: item.language,
    url: item.url,
    duration: item.duration,
    songCount: item.songCount,
    playCount: item.playCount,
    releaseDate: item.releaseDate,
    artists: item.artists,
    token: item.token,
    stationType: item.stationType,
    mediaUrls: item.mediaUrls,
  );
}
