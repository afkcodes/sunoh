// Shared plumbing for the lyric providers.
//
// They are all raced against each other by [LyricsRepository], so a provider
// that hangs holds up the whole lookup. The deadline here is deliberately far
// shorter than the app's stream-oriented timeouts: a lyric that arrives after
// the second chorus is of no use to anyone, and the fallbacks behind it are
// the better answer.

import 'package:dio/dio.dart';

import '../../config/env.dart';

/// Long enough for a mirror having a slow day, short enough that a dead one
/// doesn't hold the whole race.
const Duration kLyricsTimeout = Duration(seconds: 6);

/// The sources here are volunteer-run and several ask integrators to identify
/// themselves so they can tell real traffic from a scraper.
const String kLyricsAgent = 'sunoh/1.0 (${Env.webBase})';

/// One client for every provider, so the connection pool and DNS cache are
/// shared across the six of them.
final Dio _client = Dio(
  BaseOptions(
    connectTimeout: const Duration(seconds: 3),
    receiveTimeout: kLyricsTimeout,
    sendTimeout: kLyricsTimeout,
    headers: {'User-Agent': kLyricsAgent, 'Accept': 'application/json'},
    // Every provider hands back something different — JSON, TTML, bare LRC —
    // and each parses its own body, so nothing is decoded on the way in.
    responseType: ResponseType.plain,
    // A 404 is a miss, not an exception. Every non-200 collapses to null below.
    validateStatus: (status) => status != null && status >= 200 && status < 300,
  ),
);

/// Body of a successful GET, or null for any failure at all — a miss, a dead
/// host, a timeout. Providers fall through on null and the race carries on.
Future<String?> lyricsGet(String url, {Map<String, String>? headers}) async {
  try {
    final response = await _client.get<String>(
      url,
      options: headers == null ? null : Options(headers: headers),
    );
    return response.data;
  } on Object {
    return null;
  }
}

/// [lyricsGet] with a bearer token and the headers Apple's own web player
/// sends alongside one — the catalog API answers a token with no `Origin` at
/// all the same way it answers a wrong one, with a 403.
Future<String?> lyricsGetAuthorized(String url, String bearer) => lyricsGet(
  url,
  headers: {
    'Authorization': 'Bearer $bearer',
    'Origin': Env.appleMusicWebBase,
    'Referer': '${Env.appleMusicWebBase}/',
  },
);
