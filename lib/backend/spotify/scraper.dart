// Spotify playlist fetch without a browser (replaces sunoh-api scraper.ts).
//
// The server drives headless Chrome and scrolls open.spotify.com. A phone
// cannot, so this uses the same data the web player itself reads:
//
//   1. GET open.spotify.com/embed/playlist/<id>. Server-rendered, no auth,
//      and its `__NEXT_DATA__` carries (a) the first 100 tracks and (b) an
//      anonymous web-player access token in `settings.session`.
//   2. POST that token to api-partner.spotify.com/pathfinder/v2/query with
//      the web player's persisted `fetchPlaylist` query. Pages through the
//      whole playlist (tested at 350 tracks, no cap) and, unlike the embed,
//      returns album names and cover art.
//   3. If step 2 fails (the persisted-query hash rotates when Spotify ships a
//      new web player) fall back to the embed's 100 tracks, minus album.
//
// Rejected: api.spotify.com/v1 with the embed token (shared-app quota, answers
// 429 with a ~17 h retry-after), get_access_token (403 "URL Blocked" since the
// TOTP requirement), oEmbed (metadata only, no tracks).
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../upstream.dart';
import 'types.dart';

/// Pulls any playlist input down to a bare id: web URLs (with or without
/// `?si=`), `spotify:playlist:` URIs, or a raw id.
String? extractPlaylistId(String? input) {
  if (input == null) return null;
  final s = input.trim();
  if (s.isEmpty) return null;
  final url = RegExp(r'playlist/([a-zA-Z0-9]+)').firstMatch(s);
  if (url != null) return url[1];
  final uri = RegExp(r'^spotify:playlist:([a-zA-Z0-9]+)').firstMatch(s);
  if (uri != null) return uri[1];
  if (RegExp(r'^[a-zA-Z0-9]{16,40}$').hasMatch(s)) return s;
  return null;
}

/// The web player's persisted `fetchPlaylist` query. Read from the web-player
/// bundle; it changes on some Spotify releases, in which case the embed
/// fallback below keeps imports working (capped at 100 tracks).
const _fetchPlaylistHash =
    '21ea11a6ac75a5f3e01fd365d29c18e0a4a8b7dc09f89bbb5d73910190c6acaf';
const _pathfinder = 'https://api-partner.spotify.com/pathfinder/v2/query';

/// The server's scroll loop stopped at 1000 tracks; same ceiling here.
const _maxTracks = 1000;
const _pageSize = 200;

/// Test seam: tests inject a Dio with a fake adapter.
Dio? spotifyDioOverride;

/// Returns null when the playlist cannot be read (private, removed, upstream
/// failure), which the controller reports as the server's 502.
Future<SpotifyPlaylist?> fetchSpotifyPlaylist(String playlistId) async {
  final dio =
      spotifyDioOverride ?? upstreamDio(timeout: const Duration(seconds: 30));
  try {
    final res = await dio.get<String>(
      'https://open.spotify.com/embed/playlist/$playlistId',
      options: Options(responseType: ResponseType.plain),
    );
    final page = parseEmbedPage(res.data ?? '');
    if (page == null) return null;

    List<SpotifyTrack>? tracks;
    Map<String, Object?>? meta;
    final token = page.token;
    if (token != null) {
      try {
        final g = await _fetchGraphql(dio, token, playlistId);
        tracks = g.tracks;
        meta = g.meta;
      } catch (e) {
        debugPrint(
          '[spotify] graphql failed (${e.runtimeType}); using embed tracks',
        );
      }
    }
    final embedTracks = page.tracks;
    if (tracks == null || (tracks.isEmpty && embedTracks.isNotEmpty)) {
      tracks = embedTracks;
    }
    return SpotifyPlaylist(
      id: playlistId,
      name: _str(meta?['name']) ?? page.name,
      description: _str(meta?['description']) ?? page.description,
      owner: _str(meta?['owner']) ?? page.owner,
      artworkUrl: _str(meta?['artworkUrl']) ?? page.artworkUrl,
      url: 'https://open.spotify.com/playlist/$playlistId',
      tracks: tracks,
    );
  } catch (e) {
    debugPrint('[spotify] fetch failed (${e.runtimeType})');
    return null;
  }
}

String? _str(Object? v) => v is String && v.trim().isNotEmpty ? v : null;

class EmbedPage {
  EmbedPage({
    required this.name,
    required this.tracks,
    this.token,
    this.description,
    this.owner,
    this.artworkUrl,
  });
  final String name;
  final String? description;
  final String? owner;
  final String? artworkUrl;
  final String? token;
  final List<SpotifyTrack> tracks;
}

/// Extracts playlist metadata, tracks and the anonymous token from the embed
/// HTML. Null when there is no playlist entity (404 page, layout change).
EmbedPage? parseEmbedPage(String html) {
  final m = RegExp(
    r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>',
    dotAll: true,
  ).firstMatch(html);
  if (m == null) return null;
  final Object? root = jsonDecode(m[1]!);
  final state = _path(root, ['props', 'pageProps', 'state']);
  final entity = _path(state, ['data', 'entity']);
  if (entity is! Map || entity['trackList'] is! List) return null;
  final cover = _path(entity, ['coverArt', 'sources']);
  final tracks = <SpotifyTrack>[];
  for (final t in entity['trackList'] as List) {
    final track = _embedTrack(t);
    if (track != null) tracks.add(track);
  }
  final token = _path(state, ['settings', 'session', 'accessToken']);
  return EmbedPage(
    name: _str(entity['name']) ?? _str(entity['title']) ?? 'Unknown Playlist',
    // The embed's `subtitle` is the owner's name ("Spotify").
    owner: _str(entity['subtitle']),
    artworkUrl: largestSourceUrl(cover),
    token: token is String && token.isNotEmpty ? token : null,
    tracks: tracks,
  );
}

SpotifyTrack? _embedTrack(Object? t) {
  if (t is! Map) return null;
  final id = RegExp(r'^spotify:track:(\w+)').firstMatch('${t['uri']}')?[1];
  final name = _str(t['title']);
  // Artists arrive as one "A, B" string.
  final artists = [
    for (final a in '${t['subtitle'] ?? ''}'.split(','))
      if (a.trim().isNotEmpty) a.trim(),
  ];
  if (id == null || name == null || artists.isEmpty) return null;
  final d = t['duration'];
  return SpotifyTrack(
    id: id,
    name: name.trim(),
    artists: artists,
    album: '',
    durationMs: d is num ? d.toInt() : 0,
    url: 'https://open.spotify.com/track/$id',
  );
}

Object? _path(Object? o, List<String> keys) {
  for (final k in keys) {
    if (o is! Map) return null;
    o = o[k];
  }
  return o;
}

class _Graphql {
  _Graphql(this.tracks, this.meta);
  final List<SpotifyTrack> tracks;
  final Map<String, Object?> meta;
}

Future<_Graphql> _fetchGraphql(Dio dio, String token, String id) async {
  final tracks = <String, SpotifyTrack>{};
  Map<String, Object?> meta = const {};
  var offset = 0;
  var total = 1;
  while (offset < total && offset < _maxTracks) {
    final res = await dio.post<Map<String, dynamic>>(
      _pathfinder,
      data: {
        'operationName': 'fetchPlaylist',
        'variables': {
          'uri': 'spotify:playlist:$id',
          'offset': offset,
          'limit': _pageSize,
          'enableWatchFeedEntrypoint': false,
        },
        'extensions': {
          'persistedQuery': {'version': 1, 'sha256Hash': _fetchPlaylistHash},
        },
      },
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    final pl = _path(res.data, ['data', 'playlistV2']);
    if (pl is! Map || pl['content'] is! Map) {
      throw StateError('playlist not available');
    }
    final content = pl['content'] as Map;
    if (offset == 0) meta = graphqlMeta(pl);
    total = (content['totalCount'] as num?)?.toInt() ?? 0;
    final items = content['items'];
    if (items is! List || items.isEmpty) break;
    for (final it in items) {
      final t = graphqlTrack(it);
      // Same first-wins de-dup on track id the scroll scraper had.
      if (t != null) tracks.putIfAbsent(t.id, () => t);
    }
    offset += items.length;
  }
  return _Graphql(tracks.values.toList(), meta);
}

Map<String, Object?> graphqlMeta(Map pl) {
  Object? owner;
  final members = _path(pl, ['members', 'items']);
  if (members is List) {
    for (final m in members) {
      if (m is Map && m['isOwner'] == true) {
        owner = _path(m, ['user', 'data', 'name']);
        break;
      }
    }
  }
  final img = _path(pl, ['images', 'items']);
  final src = img is List && img.isNotEmpty
      ? _path(img.first, ['sources'])
      : null;
  return {
    'name': pl['name'],
    'description': pl['description'],
    'owner': owner,
    'artworkUrl': largestSourceUrl(src),
  };
}

/// One `content.items[]` entry to a track; null for episodes, removed or
/// unavailable rows (the scraper skipped rows it could not read as well).
SpotifyTrack? graphqlTrack(Object? item) {
  final d = _path(item, ['itemV2', 'data']);
  if (d is! Map || d['__typename'] != 'Track') return null;
  final id = RegExp(r'^spotify:track:(\w+)').firstMatch('${d['uri']}')?[1];
  final name = _str(d['name']);
  final items = _path(d, ['artists', 'items']);
  final artists = [
    if (items is List)
      for (final a in items)
        if (_str(_path(a, ['profile', 'name'])) case final n?) n.trim(),
  ];
  if (id == null || name == null || artists.isEmpty) return null;
  final ms = _path(d, ['trackDuration', 'totalMilliseconds']);
  return SpotifyTrack(
    id: id,
    name: name.trim(),
    artists: artists,
    album: _str(_path(d, ['albumOfTrack', 'name']))?.trim() ?? '',
    durationMs: ms is num ? ms.toInt() : 0,
    url: 'https://open.spotify.com/track/$id',
  );
}

/// The widest URL in a Spotify `sources` list (`{url,width,height}`).
///
/// Spotify lists renditions in no guaranteed order (64, 300 and 640 px
/// variants), and `.first` took whichever came first, often the 64px one.
/// Entries with no width rank lowest; with none at all the first wins.
String? largestSourceUrl(Object? sources) {
  if (sources is! List) return null;
  String? best;
  var bestW = -1;
  for (final s in sources) {
    final url = _path(s, ['url']);
    if (url is! String || url.isEmpty) continue;
    final w = _path(s, ['width']);
    final width = w is num ? w.toInt() : 0;
    if (width > bestW) {
      best = url;
      bestW = width;
    }
  }
  return best;
}
