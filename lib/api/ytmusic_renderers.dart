// Turning InnerTube's renderer tree into our DTOs.
//
// Split from ytmusic_api.dart, which was carrying both halves of the job in
// one 1076-line file: the transport and endpoint list on one side, and this on
// the other. They change for entirely different reasons — an endpoint moves
// when we want new content, these move when YouTube reshuffles its renderers —
// and the split is along that seam.
//
// A `part` rather than its own library, deliberately: these read the private
// helpers they sit beside and are private themselves. Nothing here is API.
//
// Everything is defensive. The tree is deeply nested, positional, and full of
// optional keys, and a shape change upstream should cost a missing row, not an
// exception.

part of 'ytmusic_api.dart';
// ── Renderer navigation ───────────────────────────────────────────────

List<HomeSection> _carouselSections(List<Map<String, dynamic>> shelves) {
  final sections = <HomeSection>[];
  for (final shelf in shelves) {
    final carousel = _asMap(shelf['musicCarouselShelfRenderer']);
    if (carousel == null) continue;
    final heading = _runsText(
      _asMap(
        _dig(carousel, [
          'header',
          'musicCarouselShelfBasicHeaderRenderer',
          'title',
        ]),
      ),
    );
    final items = <FeedItem>[];
    for (final raw in _asList(carousel['contents'])) {
      final m = _asMap(raw);
      if (m == null) continue;
      final item = _parseTwoRowItem(m) ?? _parseResponsiveItem(m);
      if (item != null) items.add(item);
    }
    if (items.isNotEmpty) {
      sections.add(
        HomeSection(
          heading: heading.isEmpty ? 'YouTube Music' : heading,
          items: items,
          source: 'youtube',
        ),
      );
    }
  }
  return sections;
}

List<Map<String, dynamic>> _searchShelves(Map<String, dynamic> body) {
  final tabs = _asList(
    _dig(body, ['contents', 'tabbedSearchResultsRenderer', 'tabs']),
  );
  for (final tab in tabs) {
    final shelves = <Map<String, dynamic>>[];
    for (final c in _asList(
      _dig(_asMap(tab), [
        'tabRenderer',
        'content',
        'sectionListRenderer',
        'contents',
      ]),
    )) {
      final shelf = _asMap(_asMap(c)?['musicShelfRenderer']);
      if (shelf != null) shelves.add(shelf);
    }
    if (shelves.isNotEmpty) return shelves;
  }
  return const [];
}

List<Map<String, dynamic>> _singleColumnShelves(Map<String, dynamic> body) {
  final tabs = _asList(
    _dig(body, ['contents', 'singleColumnBrowseResultsRenderer', 'tabs']),
  );
  for (final tab in tabs) {
    final contents = _asList(
      _dig(_asMap(tab), [
        'tabRenderer',
        'content',
        'sectionListRenderer',
        'contents',
      ]),
    );
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
        artists.add(
          ApiArtistRef(
            id: (_asMap(nav?['browseEndpoint'])?['browseId'] ?? '').toString(),
            name: trimmed,
          ),
        );
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
    subtitle: artists.isEmpty ? album : artists.map((a) => a.name).join(', '),
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

String? _pageTypeOf(Map<String, dynamic>? navigationEndpoint) =>
    _dig(navigationEndpoint, [
          'browseEndpoint',
          'browseEndpointContextSupportedConfigs',
          'browseEndpointContextMusicConfig',
          'pageType',
        ])
        as String?;

String? _videoIdOf(Map<String, dynamic> r) {
  final fromPlaylistData = _asMap(r['playlistItemData'])?['videoId'] as String?;
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
      out.add(
        ApiImage(
          quality: upscaled.$2 == null ? '' : '${upscaled.$2}x${upscaled.$3}',
          link: upscaled.$1,
        ),
      );
    }
    if (out.isNotEmpty) return out;
  }
  return const [];
}

/// Pick the biggest rendition from a variant list.
///
/// Not `.last` — that only works while the API happens to return
/// ascending sizes, and a header rendered from the smallest variant is a
/// silent, hard-to-spot quality regression.
String? _largestArt(List<ApiImage> images) {
  if (images.isEmpty) return null;
  int width(ApiImage i) {
    final m = RegExp(r'(\d+)').firstMatch(i.quality);
    return m == null ? 0 : (int.tryParse(m.group(1)!) ?? 0);
  }

  final sorted = [...images]..sort((a, b) => width(b).compareTo(width(a)));
  return sorted.first.link;
}

/// Largest square dimension worth requesting.
///
/// Measured against the CDN: cover art tops out at 1200x1200 and any
/// larger request returns the identical bytes, so asking for more just
/// makes the URL look ambitious. 1200 also covers the expanded player's
/// 336pt hero at 3x density with room to spare.
const _kMaxArtSize = 1200;

/// Ask Google's image CDN for a larger rendition.
///
/// The sizes the API volunteers are small — 60px for search rows, 576
/// for chart covers — and get upscaled by the client, which is what made
/// hero images look blocky however large the display surface was.
///
/// Two suffix forms are in use and BOTH have to be handled. Supporting
/// only the first left every chart and playlist cover at its original
/// size, since those use the second:
///
///   =w544-h544-l90-rj   sized, with modifiers
///   =s576               square shorthand
///
/// The size is rewritten in place so any trailing modifiers survive, and
/// the aspect ratio is taken from the URL itself rather than the JSON,
/// so wide artist banners don't get squared into a portrait crop.
///
/// Returns the url plus the size it will actually be, so callers can
/// label it honestly.
(String, int?, int?) _upscale(String url, int? width, int? height) {
  if (width != null && width >= _kMaxArtSize) return (url, width, height);

  final square = RegExp(r'=s(\d+)').firstMatch(url);
  if (square != null) {
    return (
      url.replaceRange(square.start, square.end, '=s$_kMaxArtSize'),
      _kMaxArtSize,
      _kMaxArtSize,
    );
  }

  final sized = RegExp(r'=w(\d+)-h(\d+)').firstMatch(url);
  if (sized != null) {
    final w0 = int.tryParse(sized.group(1)!) ?? 0;
    final h0 = int.tryParse(sized.group(2)!) ?? 0;
    final h = (w0 > 0 && h0 > 0)
        ? (_kMaxArtSize * h0 / w0).round()
        : _kMaxArtSize;
    return (
      url.replaceRange(sized.start, sized.end, '=w$_kMaxArtSize-h$h'),
      _kMaxArtSize,
      h,
    );
  }

  return (url, width, height);
}

String _flexColumnText(List<dynamic> cols, int index) => _flexColumnRuns(
  cols,
  index,
).map((r) => (r['text'] ?? '').toString()).join();

List<Map<String, dynamic>> _flexColumnRuns(List<dynamic> cols, int index) {
  if (index >= cols.length) return const [];
  return _asList(
    _dig(_asMap(cols[index]), [
      'musicResponsiveListItemFlexColumnRenderer',
      'text',
      'runs',
    ]),
  ).map(_asMap).whereType<Map<String, dynamic>>().toList();
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

Map<String, dynamic>? _asMap(Object? v) =>
    v is Map ? v.cast<String, dynamic>() : null;

List<dynamic> _asList(Object? v) => v is List ? v : const [];

/// Walk a path of string keys, returning null the moment anything isn't a
/// map. Keeps the renderer navigation above readable.
Object? _dig(Map<String, dynamic>? node, List<String> path) {
  Object? cur = node;
  for (final key in path) {
    final m = _asMap(cur);
    if (m == null) return null;
    cur = m[key];
  }
  return cur;
}
