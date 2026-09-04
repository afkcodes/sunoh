// Word-timed lyrics via a public proxy in front of Apple Music's own
// catalogue and lyrics.
//
// Ported from BitChord (https://github.com/kushagrasinghx/BitChord), GPL-3.0.
//
// A second, independent route to the same Apple TTML `better_lyrics.dart`
// carries — useful exactly when that one's host is the one having a bad day.
//
// Apple's own search wants a bearer token, which its web player mints from a
// token embedded in its own JS bundle: there is no key to request, only that
// bundle to read. So this scrapes it the same way the player itself does at
// load time, and keeps it until Apple says no.

import 'dart:async';
import 'dart:convert';

import '../../config/env.dart';
import '../../data/lyric_line.dart';
import 'enhanced_lrc.dart';
import 'lyrics_http.dart';
import 'ttml_lyrics.dart';

const int _toleranceSeconds = 10;

String? _cachedToken;

/// One in-flight scrape at a time. Without it every track that starts before
/// the first token lands mints its own, and a cold start with a full queue
/// hits Apple's bundle six times over.
Future<String?>? _tokenInFlight;

Future<List<LyricLine>?> fetchPaxSenix({
  required String title,
  required String artist,
  required int durationMs,
  String? album,
}) async {
  if (Env.paxsenixBase.isEmpty || Env.appleMusicApiBase.isEmpty) return null;

  final query = [
    _cleaned(title),
    _cleaned(artist),
  ].where((s) => s.isNotEmpty).join(' ');
  final results = await _search(query);
  if (results == null || results.isEmpty) return null;

  final seconds = durationMs ~/ 1000;
  Map<String, dynamic>? best;
  var bestScore = -1.0;
  for (final track in results) {
    final trackSeconds = _durationSecondsOf(track);
    if (seconds > 0 &&
        trackSeconds != null &&
        (trackSeconds - seconds).abs() > _toleranceSeconds) {
      continue;
    }
    final score = _score(track, title, artist);
    if (score > bestScore) {
      best = track;
      bestScore = score;
    }
  }
  final id = best?['id'] as String?;
  return id == null ? null : _fetchLyrics(id);
}

double _score(Map<String, dynamic> track, String title, String artist) {
  final attributes = (track['attributes'] as Map?)?.cast<String, dynamic>();
  final name = (attributes?['name'] as String? ?? '').trim().toLowerCase();
  final artistName = (attributes?['artistName'] as String? ?? '')
      .trim()
      .toLowerCase();
  final wantedTitle = title.trim().toLowerCase();
  final wantedArtist = artist.trim().toLowerCase();

  var score = 0.0;
  if (name == wantedTitle) {
    score += 80;
  } else if (name.contains(wantedTitle) || wantedTitle.contains(name)) {
    score += 40;
  }
  if (artistName.contains(wantedArtist) || wantedArtist.contains(artistName)) {
    score += 40;
  }
  return score;
}

int? _durationSecondsOf(Map<String, dynamic> track) {
  final attributes = (track['attributes'] as Map?)?.cast<String, dynamic>();
  final ms = (attributes?['durationInMillis'] as num?)?.toInt();
  return ms == null ? null : ms ~/ 1000;
}

final RegExp _noise = RegExp(
  r'\s*[(\[](official|video|audio|lyrics?|visualizer|hd|hq|4k|remaster\w*|'
  r'live|version|feat\.?|ft\.?)[^)\]]*[)\]]',
  caseSensitive: false,
);

String _cleaned(String value) => value.replaceAll(_noise, '').trim();

Future<List<Map<String, dynamic>>?> _search(String query) async {
  final token = await _token();
  if (token == null) return null;

  final url = Uri.parse('${Env.appleMusicApiBase}/search').replace(
    queryParameters: {
      'term': query,
      'types': 'songs',
      'limit': '10',
      'l': 'en-US',
    },
  );
  final body = await lyricsGetAuthorized(url.toString(), token);
  if (body == null) {
    // The bundle rotates; a rejected token is worth exactly one retry with a
    // fresh scrape before this source gives up for the track.
    _cachedToken = null;
    return null;
  }
  try {
    final json = jsonDecode(body);
    final data = ((json as Map?)?['results'] as Map?)?['songs'];
    final list = (data as Map?)?['data'];
    if (list is! List) return null;
    return list.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
  } on Object {
    return null;
  }
}

/// The proxy itself needs no auth; only the Apple catalogue search does.
Future<List<LyricLine>?> _fetchLyrics(String appleId) async {
  final url = Uri.parse(
    '${Env.paxsenixBase}/apple-music/lyrics',
  ).replace(queryParameters: {'id': appleId});

  final body = await lyricsGet(url.toString());
  if (body == null) return null;
  Map<String, dynamic> json;
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return null;
    json = decoded.cast<String, dynamic>();
  } on Object {
    return null;
  }

  final ttml = (json['ttmlContent'] as String?)?.trim();
  if (ttml != null && ttml.isNotEmpty) {
    final lines = parseTtml(ttml);
    if (lines.isNotEmpty) return lines;
  }
  // Multi-person first: it names who sings each line, which the plain elrc
  // has already thrown away.
  for (final key in const ['elrcMultiPerson', 'elrc']) {
    final elrc = (json[key] as String?)?.trim();
    if (elrc == null || elrc.isEmpty) continue;
    final lines = parseEnhancedLrc(elrc);
    if (lines.isNotEmpty) return lines;
  }
  return null;
}

Future<String?> _token() {
  final cached = _cachedToken;
  if (cached != null) return Future.value(cached);
  return _tokenInFlight ??= _scrapeToken().whenComplete(() {
    _tokenInFlight = null;
  });
}

/// Apple's web player carries its own bearer token inside one of its JS
/// bundles rather than minting one per session, so getting one is a matter of
/// reading the same file the player itself loads: the home page names its main
/// script, and the token sits in that script as a complete JWT — three
/// dot-separated segments, not just the leading fragment a looser match would
/// stop at.
Future<String?> _scrapeToken() async {
  if (Env.appleMusicWebBase.isEmpty) return null;
  final home = await lyricsGet('${Env.appleMusicWebBase}/us/new');
  if (home == null) return null;
  final script = RegExp(r'/assets/index~[^"]+\.js').firstMatch(home)?.group(0);
  if (script == null) return null;

  final bundle = await lyricsGet('${Env.appleMusicWebBase}$script');
  if (bundle == null) return null;
  final token = RegExp(
    r'eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+',
  ).firstMatch(bundle)?.group(0);
  return _cachedToken = token;
}
