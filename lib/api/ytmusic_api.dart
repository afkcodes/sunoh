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

import 'dto.dart';

/// The YouTube Music web client. No API key or auth needed for search/browse.
const _kClientName = 'WEB_REMIX';
const _kClientVersion = '1.20260101.01.00';
const _kBase = 'https://music.youtube.com/youtubei/v1';

/// `params` filter pinning search to songs only. Opaque protobuf-derived
/// value from the web client.
const _kSongsOnlyParams = 'EgWKAQIIAWoKEAoQAxAEEAkQBQ%3D%3D';

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

class YtMusicApi {
  YtMusicApi(this._dio);
  final Dio _dio;

  Map<String, dynamic> _context({String? country}) => {
        'context': {
          'client': {
            'clientName': _kClientName,
            'clientVersion': _kClientVersion,
            'hl': 'en',
            'gl': country ?? 'IN',
          },
        },
      };

  Options get _options => Options(
        headers: {
          'Content-Type': 'application/json',
          'X-Youtube-Client-Name': '67',
          'X-Youtube-Client-Version': _kClientVersion,
          'Origin': 'https://music.youtube.com',
        },
        validateStatus: (s) => s != null && s < 500,
      );

  Future<Map<String, dynamic>?> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '$_kBase/$path?prettyPrint=false',
      data: body,
      options: _options,
    );
    return res.data;
  }

  // ── Public API ────────────────────────────────────────────────────────

  /// Full-text song search. Items carry `source: 'youtube'` and the videoId
  /// as `id`, which routes them to StreamResolver's native YouTube tier.
  Future<List<FeedItem>> searchSongs(String query, {String? country}) async {
    if (query.trim().isEmpty) return const [];
    final body = await _post('search', {
      ..._context(country: country),
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

  /// The YouTube Music home feed as carousel sections.
  Future<List<HomeSection>> home({String? country}) async {
    final body = await _post('browse', {
      ..._context(country: country),
      'browseId': 'FEmusic_home',
    });
    if (body == null) return const [];
    return _carouselSections(_singleColumnShelves(body));
  }

  /// Mood and genre chip grids (`FEmusic_moods_and_genres`).
  Future<List<YtCategoryGroup>> moodsAndGenres({String? country}) async {
    final body = await _post('browse', {
      ..._context(country: country),
      'browseId': 'FEmusic_moods_and_genres',
    });
    if (body == null) return const [];
    final groups = <YtCategoryGroup>[];
    for (final sec in _singleColumnShelves(body)) {
      final grid = _asMap(sec['gridRenderer']);
      if (grid == null) continue;
      final title = _runsText(_asMap(
          _dig(grid, ['header', 'gridHeaderRenderer', 'title'])));
      final chips = <YtCategoryChip>[];
      for (final raw in _asList(grid['items'])) {
        final btn = _asMap(_asMap(raw)?['musicNavigationButtonRenderer']);
        if (btn == null) continue;
        final label = _runsText(_asMap(btn['buttonText']));
        final endpoint =
            _asMap(_dig(btn, ['clickCommand', 'browseEndpoint']));
        final browseId = endpoint?['browseId'] as String?;
        final params = endpoint?['params'] as String?;
        if (label.isEmpty || browseId == null || params == null) continue;
        chips.add(YtCategoryChip(
          title: label,
          browseId: browseId,
          params: params,
          color: (_dig(btn, ['solid', 'leftStripeColor']) as num?)?.toInt(),
        ));
      }
      if (chips.isNotEmpty) {
        groups.add(YtCategoryGroup(
          title: title.isEmpty ? 'Browse' : title,
          chips: chips,
        ));
      }
    }
    return groups;
  }

  /// Contents of one mood/genre category — carousels of playlists.
  Future<List<HomeSection>> category(
    String browseId,
    String params, {
    String? country,
  }) async {
    final body = await _post('browse', {
      ..._context(country: country),
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
  Future<YtPlaylistDetail?> playlist(String browseId,
      {String? country}) async {
    final body = await _post('browse', {
      ..._context(country: country),
      'browseId': browseId,
    });
    if (body == null) return null;
    final two = _asMap(_dig(body, [
      'contents',
      'twoColumnBrowseResultsRenderer',
    ]));
    if (two == null) return null;

    // Header — primary column.
    String title = '';
    String? subtitle;
    String? description;
    String? artwork;
    final tabs = _asList(two['tabs']);
    for (final tab in tabs) {
      final contents = _asList(_dig(_asMap(tab), [
        'tabRenderer',
        'content',
        'sectionListRenderer',
        'contents',
      ]));
      for (final sec in contents) {
        final h = _asMap(_asMap(sec)?['musicResponsiveHeaderRenderer']);
        if (h == null) continue;
        title = _runsText(_asMap(h['title']));
        subtitle = _runsText(_asMap(h['subtitle']));
        description = _runsText(_asMap(h['description']));
        final thumbs = _thumbnails(h);
        if (thumbs.isNotEmpty) artwork = thumbs.last.link;
      }
    }

    // Tracks — secondary column.
    final tracks = <FeedItem>[];
    final secContents = _asList(_dig(two, [
      'secondaryContents',
      'sectionListRenderer',
      'contents',
    ]));
    for (final sec in secContents) {
      final shelf = _asMap(_asMap(sec)?['musicPlaylistShelfRenderer']) ??
          _asMap(_asMap(sec)?['musicShelfRenderer']);
      if (shelf == null) continue;
      for (final raw in _asList(shelf['contents'])) {
        final item = _parseResponsiveItem(_asMap(raw));
        if (item != null) tracks.add(item);
      }
    }

    if (title.isEmpty && tracks.isEmpty) return null;
    return YtPlaylistDetail(
      id: browseId,
      title: title.isEmpty ? 'Playlist' : title,
      subtitle: (subtitle ?? '').isEmpty ? null : subtitle,
      description: (description ?? '').isEmpty ? null : description,
      artwork: artwork,
      tracks: tracks,
    );
  }

  // ── Renderer navigation ───────────────────────────────────────────────

  List<HomeSection> _carouselSections(List<Map<String, dynamic>> shelves) {
    final sections = <HomeSection>[];
    for (final shelf in shelves) {
      final carousel = _asMap(shelf['musicCarouselShelfRenderer']);
      if (carousel == null) continue;
      final heading = _runsText(_asMap(_dig(carousel, [
        'header',
        'musicCarouselShelfBasicHeaderRenderer',
        'title',
      ])));
      final items = <FeedItem>[];
      for (final raw in _asList(carousel['contents'])) {
        final m = _asMap(raw);
        if (m == null) continue;
        final item = _parseTwoRowItem(m) ?? _parseResponsiveItem(m);
        if (item != null) items.add(item);
      }
      if (items.isNotEmpty) {
        sections.add(HomeSection(
          heading: heading.isEmpty ? 'YouTube Music' : heading,
          items: items,
          source: 'youtube',
        ));
      }
    }
    return sections;
  }

  List<Map<String, dynamic>> _searchShelves(Map<String, dynamic> body) {
    final tabs = _asList(_dig(body, [
      'contents',
      'tabbedSearchResultsRenderer',
      'tabs',
    ]));
    for (final tab in tabs) {
      final shelves = <Map<String, dynamic>>[];
      for (final c in _asList(_dig(_asMap(tab), [
        'tabRenderer',
        'content',
        'sectionListRenderer',
        'contents',
      ]))) {
        final shelf = _asMap(_asMap(c)?['musicShelfRenderer']);
        if (shelf != null) shelves.add(shelf);
      }
      if (shelves.isNotEmpty) return shelves;
    }
    return const [];
  }

  List<Map<String, dynamic>> _singleColumnShelves(Map<String, dynamic> body) {
    final tabs = _asList(_dig(body, [
      'contents',
      'singleColumnBrowseResultsRenderer',
      'tabs',
    ]));
    for (final tab in tabs) {
      final contents = _asList(_dig(_asMap(tab), [
        'tabRenderer',
        'content',
        'sectionListRenderer',
        'contents',
      ]));
      if (contents.isNotEmpty) {
        return contents.map(_asMap).whereType<Map<String, dynamic>>().toList();
      }
    }
    return const [];
  }

  // ── Item parsing ──────────────────────────────────────────────────────

  /// `musicResponsiveListItemRenderer` — search results, playlist tracks.
  FeedItem? _parseResponsiveItem(Map<String, dynamic>? wrapper) {
    final r = _asMap(wrapper?['musicResponsiveListItemRenderer']);
    if (r == null) return null;

    final videoId = _videoIdOf(r);
    if (videoId == null) return null;

    final cols = _asList(r['flexColumns']);
    final title = _flexColumnText(cols, 0);
    if (title.isEmpty) return null;

    // Column 1 is a runs list joined by " • ": artist • album • duration.
    // Every one of those is navigable, so "has a navigationEndpoint" does
    // NOT mean "is an artist" — that mistake put album names in the artist
    // line. Discriminate on the endpoint's pageType instead.
    final subRuns = _flexColumnRuns(cols, 1);
    final artistNames = <String>[];
    String? album;
    String? duration;
    for (final run in subRuns) {
      final text = (run['text'] ?? '').toString();
      final trimmed = text.trim();
      if (trimmed.isEmpty || trimmed == '•') continue;

      final secs = _durationToSeconds(trimmed);
      if (secs != null) {
        duration = '$secs';
        continue;
      }

      switch (_pageTypeOf(_asMap(run['navigationEndpoint']))) {
        case 'MUSIC_PAGE_TYPE_ARTIST':
          artistNames.add(trimmed);
        case 'MUSIC_PAGE_TYPE_ALBUM':
          album ??= trimmed;
        case _:
          // Un-navigable runs are usually the primary artist on tracks
          // that have no artist channel (common for Art Tracks).
          if (artistNames.isEmpty && album == null) artistNames.add(trimmed);
      }
    }

    // Column 2 carries play counts on search rows.
    final third = _flexColumnText(cols, 2).trim();
    final plays = third.toLowerCase().contains('play') ? third : null;

    return FeedItem(
      id: videoId,
      title: title,
      type: 'song',
      source: 'youtube',
      image: _thumbnails(r),
      subtitle: artistNames.isEmpty ? album : artistNames.join(', '),
      duration: duration,
      playCount: plays,
      artists: artistNames
          .map((n) => ApiArtistRef(id: '', name: n))
          .toList(growable: false),
    );
  }

  /// `musicTwoRowItemRenderer` — home / category carousel cards.
  FeedItem? _parseTwoRowItem(Map<String, dynamic> wrapper) {
    final r = _asMap(wrapper['musicTwoRowItemRenderer']);
    if (r == null) return null;

    final title = _runsText(_asMap(r['title']));
    if (title.isEmpty) return null;
    final subtitle = _runsText(_asMap(r['subtitle']));

    final nav = _asMap(r['navigationEndpoint']);
    final videoId = _asMap(nav?['watchEndpoint'])?['videoId'] as String?;
    final browseId = _asMap(nav?['browseEndpoint'])?['browseId'] as String?;

    // Type from the endpoint's declared pageType rather than guessing from
    // the id prefix — YouTube uses several prefixes per kind.
    final String id;
    final String type;
    if (videoId != null && videoId.isNotEmpty) {
      id = videoId;
      type = 'song';
    } else if (browseId != null && browseId.isNotEmpty) {
      id = browseId;
      type = switch (_pageTypeOf(nav)) {
        'MUSIC_PAGE_TYPE_ARTIST' => 'artist',
        'MUSIC_PAGE_TYPE_ALBUM' => 'album',
        _ => 'playlist',
      };
    } else {
      return null;
    }

    return FeedItem(
      id: id,
      title: title,
      type: type,
      source: 'youtube',
      image: _thumbnails(r),
      subtitle: subtitle.isEmpty ? null : subtitle,
    );
  }

  // ── Field extraction ──────────────────────────────────────────────────

  String? _pageTypeOf(Map<String, dynamic>? navigationEndpoint) => _dig(
        navigationEndpoint,
        [
          'browseEndpoint',
          'browseEndpointContextSupportedConfigs',
          'browseEndpointContextMusicConfig',
          'pageType',
        ],
      ) as String?;

  String? _videoIdOf(Map<String, dynamic> r) {
    final fromPlaylistData =
        _asMap(r['playlistItemData'])?['videoId'] as String?;
    if (fromPlaylistData != null && fromPlaylistData.isNotEmpty) {
      return fromPlaylistData;
    }
    final overlayId = _dig(r, [
      'overlay',
      'musicItemThumbnailOverlayRenderer',
      'content',
      'musicPlayButtonRenderer',
      'playNavigationEndpoint',
      'watchEndpoint',
      'videoId',
    ]);
    if (overlayId is String && overlayId.isNotEmpty) return overlayId;
    return null;
  }

  /// Thumbnails, from either renderer shape.
  ///
  /// The renderers disagree on the key: list rows nest under `thumbnail`,
  /// carousel cards under `thumbnailRenderer`. Checking only one silently
  /// yields no art and the UI falls back to generated covers — which looks
  /// like a styling bug rather than a parsing one. Try both.
  List<ApiImage> _thumbnails(Map<String, dynamic> r) {
    for (final key in const ['thumbnail', 'thumbnailRenderer']) {
      final thumbs = _asList(_dig(r, [
        key,
        'musicThumbnailRenderer',
        'thumbnail',
        'thumbnails',
      ]));
      if (thumbs.isEmpty) continue;
      final out = <ApiImage>[];
      for (final t in thumbs) {
        final m = _asMap(t);
        final url = m?['url'] as String?;
        if (url == null || url.isEmpty) continue;
        final w = (m?['width'] as num?)?.toInt();
        out.add(ApiImage(
          quality: w == null ? '' : '${w}x$w',
          link: _upscale(url, w),
        ));
      }
      if (out.isNotEmpty) return out;
    }
    return const [];
  }

  /// Ask Google's image CDN for a larger rendition.
  ///
  /// Thumbnail URLs carry their size in a `=w60-h60-...` suffix, and the
  /// sizes the API volunteers are small (60px for search rows) — badly
  /// pixelated at our tile sizes. Rewriting the suffix is the documented
  /// way to request a bigger one. Left untouched when there's no suffix.
  String _upscale(String url, int? width) {
    if (width == null || width >= 544) return url;
    final i = url.lastIndexOf('=w');
    if (i < 0) return url;
    return '${url.substring(0, i)}=w544-h544-l90-rj';
  }

  String _flexColumnText(List<dynamic> cols, int index) =>
      _flexColumnRuns(cols, index)
          .map((r) => (r['text'] ?? '').toString())
          .join();

  List<Map<String, dynamic>> _flexColumnRuns(List<dynamic> cols, int index) {
    if (index >= cols.length) return const [];
    return _asList(_dig(_asMap(cols[index]), [
      'musicResponsiveListItemFlexColumnRenderer',
      'text',
      'runs',
    ])).map(_asMap).whereType<Map<String, dynamic>>().toList();
  }

  String _runsText(Map<String, dynamic>? node) => _asList(node?['runs'])
      .map(_asMap)
      .whereType<Map<String, dynamic>>()
      .map((r) => (r['text'] ?? '').toString())
      .join();

  /// `3:42` / `1:02:11` -> total seconds. Null when [text] isn't a duration.
  int? _durationToSeconds(String text) {
    if (!RegExp(r'^\d{1,2}(:\d{2}){1,2}$').hasMatch(text)) return null;
    final parts = text.split(':').map(int.parse).toList();
    return switch (parts.length) {
      2 => parts[0] * 60 + parts[1],
      3 => parts[0] * 3600 + parts[1] * 60 + parts[2],
      _ => null,
    };
  }

  // ── Safe traversal ────────────────────────────────────────────────────

  static Map<String, dynamic>? _asMap(Object? v) =>
      v is Map ? v.cast<String, dynamic>() : null;

  static List<dynamic> _asList(Object? v) => v is List ? v : const [];

  /// Walk a path of string keys, returning null the moment anything isn't a
  /// map. Keeps the renderer navigation above readable.
  static Object? _dig(Map<String, dynamic>? node, List<String> path) {
    Object? cur = node;
    for (final key in path) {
      final m = _asMap(cur);
      if (m == null) return null;
      cur = m[key];
    }
    return cur;
  }
}
