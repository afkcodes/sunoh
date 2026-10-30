// The "More from Artist" shelf the server's Gaana song controller added from
// Saavn. Gaana cannot import Saavn, so routes.dart installs this as
// gaana.saavnSongSections.
import 'package:flutter/foundation.dart';

import '../gaana/gaana.dart' as gaana;
import '../gaana/util.dart' show get, truthy;
import '../saavn/saavn.dart' as saavn;

/// Shelves for a Gaana song, sourced from Saavn.
///
/// Two shelves existed on the server. "More from Artist" is ported as it was:
/// confirm Saavn knows the artist, then take the first ten of that artist's
/// song search. "You Might Also Like" is deliberately NOT ported: it searched
/// Saavn for the song, asked the recommend endpoint and kept the answer only
/// `if Array.isArray(data.data)`, but that endpoint answers `{list, stationId}`,
/// never an array, so the shelf was always empty. Running the five requests to
/// reproduce an empty result would only cost the user time and Saavn quota.
Future<List<gaana.Json>> saavnSongSections(
  gaana.Json song,
  String? lang,
) async {
  final sections = <gaana.Json>[];
  final artists = song['artists'];
  final name = artists is List && artists.isNotEmpty
      ? get(artists.first, 'name')
      : null;
  if (name is! String || name.isEmpty) return sections;

  try {
    final artist = await saavn.getSaavnSearchData(name, 'artists', 1, 1, lang);
    final artistList = get(artist, 'list');
    if (artistList is List &&
        artistList.isNotEmpty &&
        truthy(get(artistList.first, 'id'))) {
      final songs = await saavn.getSaavnSearchData(name, 'songs', 1, 15, lang);
      final list = get(songs, 'list');
      if (list is List && list.isNotEmpty) {
        sections.add({
          'heading': 'More from Artist',
          'data': list.take(10).toList(),
          'source': 'saavn',
        });
      }
    }
  } catch (_) {
    // A missing shelf is not an error; the song itself still loads.
    debugPrint('[music] More from Artist unavailable from Saavn');
  }
  return sections;
}
