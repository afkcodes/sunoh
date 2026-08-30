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

  /// Artist results. Their ids are channel ids that open the artist page.
  Future<List<FeedItem>> searchArtists(String query, {String? country}) =>
      _searchFiltered(query, _kArtistsOnlyParams, country: country);

  /// Album results.
  Future<List<FeedItem>> searchAlbums(String query, {String? country}) =>
      _searchFiltered(query, _kAlbumsOnlyParams, country: country);

  Future<List<FeedItem>> _searchFiltered(
    String query,
    String params, {
    String? country,
  }) async {
    if (query.trim().isEmpty) return const [];
    try {
      final body = await _post('search', {
        ..._context(country: country),
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
  Future<List<HomeSection>> home({String? country}) async {
    final pages = await Future.wait([
      _browseSections('FEmusic_home', country: country),
      _browseSections('FEmusic_explore', country: country),
      _browseSections('FEmusic_charts', country: country),
      _browseSections('FEmusic_new_releases', country: country),
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

  Future<List<HomeSection>> _browseSections(
    String browseId, {
    String? country,
  }) async {
    try {
      final body = await _post('browse', {
        ..._context(country: country),
        'browseId': browseId,
      });
      if (body == null) return const [];
      return _carouselSections(_singleColumnShelves(body));
    } catch (_) {
      return const [];
    }
  }

  /// An artist page: header, top songs, and the discography carousels.
  Future<YtArtistDetail?> artist(String browseId, {String? country}) async {
    final body = await _post('browse', {
      ..._context(country: country),
      'browseId': browseId,
    });
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
      print('[ytmusic] artist $browseId: no name. '
          'top=${body.keys.toList()} '
          'header=${_asMap(body['header'])?.keys.toList()} '
          'contents=${_asMap(body['contents'])?.keys.toList()}');
      return null;
    }

    final thumbs = header == null ? const <ApiImage>[] : _thumbnails(header);
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
      artwork: thumbs.isEmpty ? null : thumbs.last.link,
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
    String? country,
  }) async {
    final body = await _post('next', {
      ..._context(country: country),
      'videoId': videoId,
      'playlistId': playlistId,
      'isAudioOnly': true,
    });
    if (body == null) return const [];
    final tabs = _asList(_dig(body, [
      'contents',
      'singleColumnMusicWatchNextResultsRenderer',
      'tabbedRenderer',
      'watchNextTabbedResultsRenderer',
      'tabs',
    ]));
    for (final tab in tabs) {
      final items = _asList(_dig(_asMap(tab), [
        'tabRenderer',
        'content',
        'musicQueueRenderer',
        'content',
        'playlistPanelRenderer',
        'contents',
      ]));
      final out = <FeedItem>[];
      for (final raw in items) {
        final r = _asMap(_asMap(raw)?['playlistPanelVideoRenderer']);
        if (r == null) continue;
        final id = r['videoId'] as String?;
        final title = _runsText(_asMap(r['title']));
        if (id == null || id.isEmpty || title.isEmpty) continue;
        final byline = _runsText(_asMap(r['longBylineText'])).split(' • ');
        out.add(FeedItem(
          id: id,
          title: title,
          type: 'song',
          source: 'youtube',
          image: _thumbnails(r),
          subtitle: byline.isEmpty ? null : byline.first,
          duration: _durationToSeconds(_runsText(_asMap(r['lengthText'])))
              ?.toString(),
        ));
      }
      if (out.isNotEmpty) return out;
    }
    return const [];
  }

  /// The artist header, from whichever layout this page uses.
  Map<String, dynamic>? _artistHeader(Map<String, dynamic> body) {
    final immersive =
        _asMap(_dig(body, ['header', 'musicImmersiveHeaderRenderer']));
    if (immersive != null) return immersive;

    // Two-column layout: header lives in the primary column.
    for (final tab in _asList(_dig(body, [
      'contents',
      'twoColumnBrowseResultsRenderer',
      'tabs',
    ]))) {
      for (final sec in _asList(_dig(_asMap(tab), [
        'tabRenderer',
        'content',
        'sectionListRenderer',
        'contents',
      ]))) {
        final m = _asMap(sec);
        final h = _asMap(m?['musicResponsiveHeaderRenderer']) ??
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
    for (final sec in _asList(_dig(body, [
      'contents',
      'twoColumnBrowseResultsRenderer',
      'secondaryContents',
      'sectionListRenderer',
      'contents',
    ]))) {
      final m = _asMap(sec);
      if (m != null) out.add(m);
    }
    return out;
  }

  /// `(videoId, playlistId)` from a header button's watch endpoint.
  (String, String)? _watchSeed(Map<String, dynamic>? button) {
    final we = _asMap(_dig(button, [
      'buttonRenderer',
      'navigationEndpoint',
      'watchEndpoint',
    ]));
    final v = we?['videoId'] as String?;
    final p = we?['playlistId'] as String?;
    if (v == null || p == null || v.isEmpty || p.isEmpty) return null;
    return (v, p);
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
                  : _withImages(t, [ApiImage(quality: '', link: headerArt)]),
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

    final cols = _asList(r['flexColumns']);
    final title = _flexColumnText(cols, 0);
    if (title.isEmpty) return null;

    final videoId = _videoIdOf(r);
    if (videoId == null) {
      // Not a track. List shelves also carry artists and albums (the
      // "Top artists" chart is 40 of them); without this they'd all be
      // dropped for lacking a videoId.
      final nav = _asMap(r['navigationEndpoint']);
      final browseId = _asMap(nav?['browseEndpoint'])?['browseId'] as String?;
      if (browseId == null || browseId.isEmpty) return null;
      final type = switch (_pageTypeOf(nav)) {
        'MUSIC_PAGE_TYPE_ARTIST' => 'artist',
        'MUSIC_PAGE_TYPE_ALBUM' => 'album',
        'MUSIC_PAGE_TYPE_PLAYLIST' => 'playlist',
        _ => null,
      };
      if (type == null) return null;
      final sub = _flexColumnText(cols, 1).trim();
      return FeedItem(
        id: browseId,
        title: title,
        type: type,
        source: 'youtube',
        image: _thumbnails(r),
        subtitle: sub.isEmpty ? null : sub,
      );
    }

    // Column 1 is a runs list joined by " • ": artist • album • duration.
    // Every one of those is navigable, so "has a navigationEndpoint" does
    // NOT mean "is an artist" — that mistake put album names in the artist
    // line. Discriminate on the endpoint's pageType instead.
    final subRuns = _flexColumnRuns(cols, 1);
    final artists = <ApiArtistRef>[];
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

      final nav = _asMap(run['navigationEndpoint']);
      switch (_pageTypeOf(nav)) {
        case 'MUSIC_PAGE_TYPE_ARTIST':
          // Keep the channel id, not just the name — it's what lets the
          // player's "View artist" open the artist page.
          artists.add(ApiArtistRef(
            id: (_asMap(nav?['browseEndpoint'])?['browseId'] ?? '').toString(),
            name: trimmed,
          ));
        case 'MUSIC_PAGE_TYPE_ALBUM':
          album ??= trimmed;
        case _:
          // Un-navigable runs are usually the primary artist on tracks
          // that have no artist channel (common for Art Tracks).
          if (artists.isEmpty && album == null) {
            artists.add(ApiArtistRef(id: '', name: trimmed));
          }
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
      subtitle: artists.isEmpty
          ? album
          : artists.map((a) => a.name).join(', '),
      duration: duration,
      playCount: plays,
      artists: List.unmodifiable(artists),
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

  /// Thumbnails, from any of the three shapes YouTube uses.
  ///
  /// The renderers disagree, and picking only one silently yields no art —
  /// the UI then falls back to generated covers, which reads as a styling
  /// bug rather than a parsing one:
  ///
  ///   list rows          thumbnail.musicThumbnailRenderer.thumbnail.thumbnails
  ///   carousel cards     thumbnailRenderer.musicThumbnailRenderer.…
  ///   queue rows         thumbnail.thumbnails   (no wrapper at all)
  ///
  /// The last is what `/next` returns for radio queues.
  List<ApiImage> _thumbnails(Map<String, dynamic> r) {
    final candidates = <List<String>>[
      ['thumbnail', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails'],
      ['thumbnailRenderer', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails'],
      ['thumbnail', 'thumbnails'],
    ];
    for (final path in candidates) {
      final thumbs = _asList(_dig(r, path));
      if (thumbs.isEmpty) continue;
      final out = <ApiImage>[];
      for (final t in thumbs) {
        final m = _asMap(t);
        final url = m?['url'] as String?;
        if (url == null || url.isEmpty) continue;
        final w = (m?['width'] as num?)?.toInt();
        final h = (m?['height'] as num?)?.toInt();
        final upscaled = _upscale(url, w, h);
        // Label with the size actually being requested, not the size the
        // API offered — FeedItem.artwork picks the highest number here, so
        // a stale label would have it choose a smaller image.
        out.add(ApiImage(
          quality: upscaled.$2 == null ? '' : '${upscaled.$2}x${upscaled.$3}',
          link: upscaled.$1,
        ));
      }
      if (out.isNotEmpty) return out;
    }
    return const [];
  }

  /// Largest square dimension worth requesting.
  ///
  /// Measured against the CDN: cover art tops out at 1200x1200 and any
  /// larger request returns the identical bytes, so asking for more just
  /// makes the URL look ambitious. 1200 also covers the expanded player's
  /// 336pt hero at 3x density with room to spare.
  static const _kMaxArtSize = 1200;

  /// Ask Google's image CDN for a larger rendition.
  ///
  /// Thumbnail URLs carry their size in a `=w60-h60-...` suffix, and the
  /// sizes the API volunteers are small — 60px for search rows, badly
  /// pixelated at our tile sizes. Rewriting the suffix is the documented
  /// way to request a bigger one.
  ///
  /// Height is scaled to preserve aspect rather than forced square. Artist
  /// images are wide banners (540x225 and up), and asking for `=w544-h544`
  /// returned a 363x544 portrait crop of one.
  ///
  /// Returns the url plus the size it will actually be, so callers can
  /// label it honestly.
  (String, int?, int?) _upscale(String url, int? width, int? height) {
    if (width == null || width >= _kMaxArtSize) return (url, width, height);
    final i = url.lastIndexOf('=w');
    if (i < 0) return (url, width, height);
    final h = (height != null && height > 0 && width > 0)
        ? (_kMaxArtSize * height / width).round()
        : _kMaxArtSize;
    return (
      '${url.substring(0, i)}=w$_kMaxArtSize-h$h-l90-rj',
      _kMaxArtSize,
      h,
    );
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
