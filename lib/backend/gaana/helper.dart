// Shapes raw Gaana search/home payloads into sunoh sections (src/gaana/helper.ts).
import '../common.dart' show isValidTitle;
import 'mapper.dart';
import 'util.dart';

/// Maps one raw entity by its Gaana `entity_type` (TR/AL/PL/AR); anything else
/// passes through unchanged.
Object? gaanaDataSanitizer(Map data) {
  final type = data['entity_type'];
  if (type == 'TR') return mapGaanaSong(data);
  if (type == 'AL') return mapGaanaAlbum(data);
  if (type == 'PL') return mapGaanaPlaylist(data);
  if (type == 'AR') return mapGaanaArtist(data);
  return data;
}

const _searchTypes = {
  'Track': 'TR',
  'Album': 'AL',
  'Playlist': 'PL',
  'Artist': 'AR',
};

List<Json> gaanaSearchMapper(Object? data) {
  if (!truthy(data)) return [];
  final groups = get(data, 'gr');
  final out = <Json>[];
  for (final group in (groups is List ? groups : const [])) {
    final heading = or(get(group, 'stxt'), get(group, 'ty'));
    final gd = get(group, 'gd');
    final items = [
      for (final item in (gd is List ? gd : const []))
        // Search hits use short keys; rebuild the entity shape the mappers
        // already understand rather than teaching them a second format.
        gaanaDataSanitizer({
          'entity_id': get(item, 'id'),
          'name': get(item, 'ti'),
          'seokey': get(item, 'seo'),
          'artwork': get(item, 'aw'),
          'entity_type': _searchTypes[get(item, 'ty')] ?? get(item, 'ty'),
          'language': get(item, 'language'),
          'entity_info': [
            {
              'key': 'artist',
              'value': [
                for (final name in '${or(get(item, 'sti'), '')}'.split(','))
                  {'name': name.trim(), 'artist_id': '', 'seokey': ''},
              ],
            },
          ],
        }),
    ];
    if (items.isNotEmpty) {
      out.add({'heading': heading, 'data': items, 'source': 'gaana'});
    }
  }
  return out;
}

/// Home/occasion section metadata; sections without a real heading are
/// dropped (banners, upsell tiles).
List<Json> gaanaSectionMapper(Object? sections) {
  final out = <Json>[];
  for (final s in (sections is List ? sections : const [])) {
    final heading = or(get(s, 'ga_header'), get(s, 'entity_description'));
    if (!isValidTitle(heading)) continue;
    out.add({
      'heading': heading,
      'source': 'gaana',
      'url': get(s, 'url'),
      'seokey': get(s, 'seokey_url'),
      'entities': or(get(s, 'entities'), get(get(s, 'content'), 'entities')),
    });
  }
  return out;
}

List<Json> gaanaHomeMapper(Object? data) {
  if (data is! Map) throw ArgumentError('home payload is not an object');
  return gaanaSectionMapper(data['home']);
}
