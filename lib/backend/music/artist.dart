// Unified artist (port of unifiedArtistController in sunoh-api
// src/music/controller.ts): prefer Saavn's richer artist page, falling back
// to resolving a Gaana artist by name on Saavn, then to Gaana's own page.
import '../gaana/gaana.dart' as gaana;
import '../gaana/util.dart' show get, truthy;
import '../local_backend.dart';
import '../saavn/saavn.dart' as saavn;
import 'shared.dart';

/// Saavn's artist payload for [id], or null when it has none (any failure
/// counts: the caller only wants to know whether Saavn knows this artist).
Future<Rec?> _saavnArtist(String id, Map<String, String> query) async {
  try {
    final r = await saavn.artistController(
      {'artistId': id},
      {...query, 'provider': 'saavn'},
    );
    final d = r.data;
    if (d is Map && truthy(d['id'])) return Map<String, Object?>.from(d);
  } catch (_) {
    // Treated as "not a Saavn artist".
  }
  return null;
}

Future<LocalReply> unifiedArtistController(
  Map<String, String> params,
  Map<String, String> query,
) => unifiedGuard('Unified artist fetch failed', () async {
  final artistId = params['artistId'] ?? '';
  final provider = query['provider'];
  final lang = query['lang'];
  final languages =
      firstNonEmpty([lang, query['languages']]) ?? 'hindi,english';

  if (provider == 'saavn') return saavn.artistController(params, query);

  final direct = await _saavnArtist(artistId, query);
  if (direct != null) {
    return unified(direct, 'Artist data fetched successfully');
  }

  // The id is probably a Gaana seokey: learn the artist's name from Gaana and
  // look the same artist up on Saavn.
  final detail = await gaana.gaanaFetch({
    'type': 'artistDetailNew',
    'seokey': artistId,
  }, languages: lang);
  final name = get(get(detail.data, 'artist'), 'name');
  if (truthy(name)) {
    final found = await saavn.getSaavnSearchData(
      '$name',
      'artists',
      1,
      1,
      languages,
    );
    final list = found is Map ? found['list'] : null;
    if (list is List && list.isNotEmpty) {
      final saavnId = get(list.first, 'id');
      final viaName = saavnId == null
          ? null
          : await _saavnArtist('$saavnId', query);
      if (viaName != null) {
        return unified(viaName, 'Artist data unified successfully');
      }
    }
  }

  return gaana.artistController(params, query);
});
