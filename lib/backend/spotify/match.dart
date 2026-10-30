// Match a Spotify track to a Saavn song (port of sunoh-api spotify/match.ts).
//
// Scoring, thresholds and the query ladder are identical to the server. What
// is dropped is the Redis cache (the app has none) and what changes is only
// the transport: the search runs in-process against the Saavn port.
import 'dart:math' as math;

import '../common.dart';
import '../saavn/saavn.dart' as saavn;
import 'types.dart';

/// Below this the fuzzy match is not trusted: reported as `matched:false` with
/// the candidate still attached.
const minAcceptScore = 0.55;

/// Phone-friendly version of the server's 8 workers. Each in-flight track runs
/// up to four sequential Saavn searches.
const matchConcurrency = 8;

typedef SaavnSearch = Future<List<Map<String, Object?>>> Function(String q);

// Dart has no Unicode normaliser without a package, and NFKD followed by
// stripping combining marks is only used here to fold Latin letters to ASCII.
// Letters NFKD does not decompose (d-stroke, l-stroke, sharp s, ...) are left
// out on purpose: JS turns them into a space too.
const _accented = {
  'a': 'àáâãäåāăąǎǟǡǻȁȃȧ',
  'c': 'çćĉċč',
  'd': 'ď',
  'e': 'èéêëēĕėęěȅȇȩ',
  'g': 'ĝğġģǧǵ',
  'h': 'ĥȟ',
  'i': 'ìíîïĩīĭįǐȉȋ',
  'j': 'ĵǰ',
  'k': 'ķǩ',
  'l': 'ĺļľ',
  'n': 'ñńņňǹ',
  'o': 'òóôõöōŏőǒǫȍȏȯ',
  'r': 'ŕŗřȑȓ',
  's': 'śŝşšș',
  't': 'ţťț',
  'u': 'ùúûüũūŭůűųǔǖǘǚǜȕȗ',
  'w': 'ŵ',
  'y': 'ýÿŷȳ',
  'z': 'źżž',
};
final _fold = {
  for (final e in _accented.entries)
    for (final r in e.value.runes) r: e.key,
  // NFKD ligatures.
  0xFB00: 'ff', 0xFB01: 'fi', 0xFB02: 'fl',
};

String _asciiFold(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    if (r >= 0x300 && r <= 0x36F) continue; // combining marks
    if (r >= 0xFF01 && r <= 0xFF5E) {
      b.writeCharCode(r - 0xFEE0); // fullwidth forms
    } else {
      final f = _fold[r];
      f != null ? b.write(f) : b.writeCharCode(r);
    }
  }
  return b.toString();
}

String norm(String? s) => _asciiFold((s ?? '').toLowerCase())
    .replaceAll(RegExp(r'[^a-z0-9 ]+'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

double titleSimilarity(String a, String b) {
  a = norm(a);
  b = norm(b);
  if (a.isEmpty || b.isEmpty) return 0;
  if (a == b) return 1;
  final ta = a.split(' ').toSet();
  final tb = b.split(' ').toSet();
  final inter = ta.where(tb.contains).toList();
  final union = {...ta, ...tb};
  final jaccard = union.isEmpty ? 0 : inter.length / union.length;
  final overlap =
      inter.join().length / math.max(a.replaceAll(' ', '').length, 1);
  return jaccard * 0.7 + overlap * 0.3;
}

double artistMatch(List<String> spotifyArtists, String saavnArtistsRaw) {
  final theirs = [
    for (final s in saavnArtistsRaw.split(','))
      if (norm(s).isNotEmpty) norm(s),
  ];
  if (spotifyArtists.isEmpty) return 0;
  var hits = 0;
  for (final a in spotifyArtists) {
    if (theirs.contains(norm(a))) hits++;
  }
  return hits / spotifyArtists.length;
}

/// JS `a || b || c` over strings: first non-empty.
String _firstNonEmpty(Iterable<Object?> xs) {
  for (final x in xs) {
    if (x is String && x.isNotEmpty) return x;
  }
  return '';
}

/// JS `parseInt(String(v), 10)`: leading integer, NaN (here 0) otherwise.
int _parseInt(Object? v) {
  final m = RegExp(r'^\s*[+-]?\d+').firstMatch('${v ?? ''}');
  return m == null ? 0 : int.parse(m[0]!.trim());
}

double score(SpotifyTrack spotify, Map<String, Object?> cand) {
  final t = titleSimilarity(
    spotify.name,
    _firstNonEmpty([cand['title'], cand['name']]),
  );
  final a = artistMatch(
    spotify.artists,
    _firstNonEmpty([cand['primaryArtists'], cand['music'], cand['singers']]),
  );
  // Saavn ships duration in seconds (a string sometimes); linear-decay penalty
  // against Spotify's ms, neutral 0.5 when either side is unknown.
  final durSpotify = spotify.durationMs;
  final durCand = _parseInt(cand['duration']) * 1000;
  var d = 0.5;
  if (durSpotify > 0 && durCand > 0) {
    final ratio = (durSpotify - durCand).abs() / math.max(durSpotify, 1);
    d = math.max(0, 1 - ratio);
  }
  return t * 0.55 + a * 0.3 + d * 0.15;
}

/// Candidate queries by specificity; later ones are fallbacks for tracks with
/// extra annotations or noisy artist lists.
List<String> buildQueries(SpotifyTrack t) {
  final cleaned = t.name
      .replaceFirst(RegExp(r'-\s*from\s+"[^"]+"', caseSensitive: false), '')
      .replaceAll(RegExp(r'\(.*?version\)', caseSensitive: false), '')
      .replaceAll(RegExp(r'\[.*?\]'), '')
      .replaceAll(RegExp('["“”]'), '')
      .replaceFirst(RegExp(r'-\s*remix.*', caseSensitive: false), '')
      .replaceFirst(RegExp('feat\\..*'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final primary = t.artists.isEmpty ? '' : t.artists.first;
  final two = t.artists.take(2).join(' ');
  final queries = ['$cleaned $two'.trim(), '$cleaned $primary'.trim(), cleaned];
  final seen = <String>{};
  return [
    for (final q in queries)
      if (q.isNotEmpty && seen.add(q)) q,
  ];
}

/// Songs search against the on-device Saavn port. Failures count as "no
/// candidates", as in the server (data functions throw StateError).
Future<List<Map<String, Object?>>> saavnSearch(String q) async {
  try {
    final res = await saavn.getSaavnSearchData(q, 'songs', 1, 10);
    if (res is Map && res['list'] is List) {
      return [
        for (final c in res['list'] as List)
          if (c is Map) c.cast<String, Object?>(),
      ];
    }
  } catch (_) {
    // Swallowed on purpose: one flaky search must not fail the whole import.
  }
  return const [];
}

Future<Map<String, Object?>> matchOne(
  SpotifyTrack spotify, {
  SaavnSearch search = saavnSearch,
}) async {
  Map<String, Object?>? best;
  var bestScore = -1.0;
  var bestQuery = '';
  var considered = 0;

  void consider(List<Map<String, Object?>> hits, String q) {
    considered += hits.length;
    for (final c in hits) {
      final s = score(spotify, c);
      if (s > bestScore) {
        bestScore = s;
        best = c;
        bestQuery = q;
      }
    }
  }

  final isrc = spotify.isrc;
  if (isrc != null && isrc.isNotEmpty) {
    consider(await search(isrc), 'isrc:$isrc');
  }
  // Fuzzy ladder always runs, even after an ISRC hit: ISRC sometimes lands on a
  // live/karaoke version and the scorer should pick between them.
  for (final q in buildQueries(spotify)) {
    final hits = await search(q);
    consider(hits, q);
    if (hits.isNotEmpty) break;
  }

  return {
    'spotify': spotify.toJson(),
    'saavn': best,
    'score': bestScore < 0 ? 0 : bestScore,
    'matched': best != null && bestScore >= minAcceptScore,
    'query': bestQuery,
    'candidatesConsidered': considered,
  };
}

/// Matches every track, [matchConcurrency] at a time, keeping input order.
Future<List<Map<String, Object?>>> matchTracks(
  List<SpotifyTrack> tracks, {
  SaavnSearch search = saavnSearch,
}) => promiseAllLimit(
  tracks,
  matchConcurrency,
  (t) => matchOne(t, search: search),
);
