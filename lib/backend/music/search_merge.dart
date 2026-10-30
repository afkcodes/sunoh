// The merge half of unified search (port of unifiedSearchController in
// sunoh-api src/music/controller.ts): Saavn results are the base, Gaana's
// sections are folded in and everything is de-duplicated by title + artist.
import '../common.dart';
import '../gaana/util.dart' show get, or;
import 'shared.dart';

String _alnum(String s) =>
    s.toLowerCase().trim().replaceAll(RegExp(r'[^a-z0-9]'), '');

String _text(Object? v) => v is String ? v : '';

/// Drops untitled items and items whose normalised title + first artist were
/// already seen. Saavn and Gaana both list the same hit, usually with
/// different punctuation, hence the alphanumeric-only key.
List<Object?> dedupeItems(Object? items) {
  if (items is! List) return [];
  final seen = <String>{};
  final out = <Object?>[];
  for (final item in items) {
    if (item is! Map) continue;
    final rawTitle = or(item['title'], item['name']);
    final title = _alnum(_text(or(rawTitle, '')));
    var artist = '';
    final artists = item['artists'];
    final subtitle = item['subtitle'];
    if (artists is List && artists.isNotEmpty) {
      artist = _alnum(_text(or(get(artists.first, 'name'), '')));
    } else if (subtitle is String) {
      artist = _alnum(subtitle.split(',').first);
    }
    final key = '${title}_$artist';
    if (title.isEmpty || !isValidTitle(rawTitle) || seen.contains(key)) {
      continue;
    }
    seen.add(key);
    out.add(item);
  }
  return out;
}

/// Section headings differ per provider ("Track", "Top Query"...); map them
/// onto one vocabulary before matching.
String normalizeHeading(Object? heading) {
  var h = (heading as String).toLowerCase().trim().replaceAll(' ', '');
  if (h == 'track' || h == 'song') h = 'songs';
  if (h == 'album') h = 'albums';
  if (h == 'playlist') h = 'playlists';
  if (h == 'artist') h = 'artists';
  if (h == 'topquery' || h == 'topresult') h = 'topresults';
  return h;
}

Rec _rec(Object? m) => Map<String, Object?>.from(m! as Map);

/// Folds [gaana] sections into [saavnResults] for a search of [type]. The
/// Saavn side is a section list for `all`, otherwise a `{list: [...]}` map;
/// returns the value to send as `data`.
Object? mergeSearchResults(
  Object? saavnResults,
  List<Object?> gaana,
  String type,
) {
  if (type == 'all' && saavnResults is List) {
    final sections = [for (final s in saavnResults) _rec(s)];
    final gaanaBy = <String, Object?>{};
    for (final g in gaana) {
      if (g is! Map || !truthyHeading(g['heading'])) continue;
      gaanaBy[normalizeHeading(g['heading'])] = g;
    }

    // Gaana's own "All" replaces Saavn's top result (or leads when Saavn has
    // none): its ranking of the exact query is the better hero.
    final gaanaAll = gaanaBy['all'] ?? gaanaBy['topresults'];
    if (gaanaAll != null) {
      final hero = <String, Object?>{
        'heading': 'Top Results',
        'data': dedupeItems(get(gaanaAll, 'data')),
        'source': 'gaana',
      };
      final top = sections.indexWhere(
        (s) => normalizeHeading(s['heading']) == 'topresults',
      );
      if (top != -1) {
        sections[top] = hero;
      } else {
        sections.insert(0, hero);
      }
    }

    for (final cat in const ['songs', 'albums', 'artists', 'playlists']) {
      final g = gaanaBy[cat];
      if (g == null) continue;
      final s = sections.where((s) => normalizeHeading(s['heading']) == cat);
      if (s.isNotEmpty) {
        final sec = s.first;
        sec['data'] = dedupeItems([
          ...(sec['data'] as List),
          ...dedupeItems(get(g, 'data')),
        ]);
        sec['source'] = unifiedSource;
      } else {
        sections.add({
          'heading': capitalizeFirstLetter(cat),
          'data': dedupeItems(get(g, 'data')),
          'source': 'gaana',
        });
      }
    }

    return [
      for (final s in sections) {...s, 'data': dedupeItems(s['data'])},
    ];
  }

  if (saavnResults is Map && saavnResults['list'] != null) {
    final result = _rec(saavnResults);
    if (type == 'playlists') {
      final list = dedupeItems(result['list']);
      for (final g in gaana) {
        final h = get(g, 'heading');
        if (h == 'Playlists' || h == 'Mix') {
          list.addAll(dedupeItems(get(g, 'data')));
        }
      }
      result['list'] = dedupeItems(list);
      result['source'] = unifiedSource;
      return result;
    }

    result['list'] = dedupeItems(result['list']);
    final want = normalizeHeading(type);
    for (final g in gaana) {
      if (g is Map &&
          truthyHeading(g['heading']) &&
          normalizeHeading(g['heading']) == want) {
        result['list'] = dedupeItems([
          ...(result['list'] as List),
          ...dedupeItems(g['data']),
        ]);
        result['source'] = unifiedSource;
        break;
      }
    }
    return result;
  }

  if (saavnResults is List) {
    return [
      for (final s in saavnResults)
        {..._rec(s), 'data': dedupeItems(get(s, 'data'))},
    ];
  }
  return saavnResults;
}

/// A heading that is present and non-empty (JS truthiness for a string).
bool truthyHeading(Object? h) => h is String && h.isNotEmpty;
