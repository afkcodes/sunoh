// The merge half of the unified home feed (port of unifiedHomeController in
// sunoh-api src/music/controller.ts). Pure so it can be tested without any
// network: the controller only fetches the two provider feeds and hands them
// here.
import '../common.dart';
import '../gaana/util.dart' show get, or;
import 'shared.dart';

// Headings from either provider that mean the same shelf. Matching sections
// are merged into one tile row instead of showing "Top Charts" twice.
const _categoryMap = {
  'new releases': 'New Releases',
  'top charts': 'Top Charts',
  'city top charts': 'Top Charts',
  'trending now': 'Trending',
  'trending songs': 'Trending',
  'top picks': 'Recommended',
  'gaana recommends': 'Recommended',
  'editorial picks': 'Editorial Picks',
  'radio stations': 'Radio',
  'radio': 'Radio',
};

const _priority = ['Trending', 'Top Charts', 'New Releases', 'Recommended'];

bool _titled(Object? item) =>
    item != null && isValidTitle(or(get(item, 'title'), get(item, 'name')));

List<Object?> _titledItems(Object? data) => [
  for (final i in data as List)
    if (_titled(i)) i,
];

/// Merges the Saavn and Gaana home feeds: same-named shelves are combined
/// (Saavn first, then Gaana interleaved item by item), the rest are
/// alternated Saavn / Gaana after the prioritised shelves.
List<Rec> mergeHomeSections(List<Object?> saavn, List<Object?> gaana) {
  final merged = <String, Rec>{};
  final others = <Rec>[];

  void collect(List<Object?> sections, {required bool interleave}) {
    for (final section in sections) {
      if (section is! Map || section['data'] is! List) continue;
      final cat =
          _categoryMap[(section['heading'] as String).toLowerCase().trim()];
      final items = _titledItems(section['data']);
      if (cat == null) {
        if (items.isNotEmpty) {
          others.add({...section.cast<String, Object?>(), 'data': items});
        }
        continue;
      }
      final target = merged.putIfAbsent(
        cat,
        () => {'heading': cat, 'data': <Object?>[], 'source': unifiedSource},
      );
      final existing = target['data']! as List<Object?>;
      if (!interleave) {
        existing.addAll(items);
        continue;
      }
      final out = <Object?>[];
      final n = existing.length > items.length ? existing.length : items.length;
      for (var i = 0; i < n; i++) {
        if (i < existing.length) out.add(existing[i]);
        if (i < items.length) out.add(items[i]);
      }
      target['data'] = out;
    }
  }

  collect(saavn, interleave: false);
  collect(gaana, interleave: true);

  final result = <Rec>[];
  for (final p in _priority) {
    final s = merged.remove(p);
    if (s != null) result.add(s);
  }
  result.addAll(merged.values);

  // Sections with no counterpart alternate between providers; a section from
  // any other source is dropped, as on the server.
  final saavnOthers = [
    for (final s in others)
      if (s['source'] == 'saavn') s,
  ];
  final gaanaOthers = [
    for (final s in others)
      if (s['source'] == 'gaana') s,
  ];
  final n = saavnOthers.length > gaanaOthers.length
      ? saavnOthers.length
      : gaanaOthers.length;
  for (var i = 0; i < n; i++) {
    if (i < saavnOthers.length) result.add(saavnOthers[i]);
    if (i < gaanaOthers.length) result.add(gaanaOthers[i]);
  }
  return result;
}
