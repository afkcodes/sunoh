import 'package:flutter_test/flutter_test.dart';
import 'package:sunoh/api/dto.dart';
import 'package:sunoh/screens/library_filter.dart';

FeedItem _item(
  String id,
  String title, {
  String? sub,
  List<String>? artists,
  String type = 'song',
}) => FeedItem(
  id: id,
  title: title,
  type: type,
  image: const [],
  subtitle: sub,
  artists: artists == null
      ? null
      : [for (final n in artists) ApiArtistRef(id: n, name: n)],
);

List<String> _ids(List<FeedItem> l) => [for (final i in l) i.id];

void main() {
  final items = [
    _item('1', 'Tum Hi Ho', artists: ['Arijit Singh']),
    _item('2', 'Halo', sub: 'Beyoncé', type: 'album'),
    _item('3', 'Café del Mar', type: 'playlist'),
  ];

  test('folding ignores case and accents', () {
    expect(foldForSearch('BeyONcé'), 'beyonce');
    expect(foldForSearch('Ñandú'), 'nandu');
  });

  test('matches title case-insensitively', () {
    expect(_ids(filterLibraryItems(items, foldForSearch('TUM'))), ['1']);
  });

  test('matches subtitle accent-insensitively, both directions', () {
    expect(_ids(filterLibraryItems(items, foldForSearch('beyonce'))), ['2']);
    expect(_ids(filterLibraryItems(items, foldForSearch('cafe'))), ['3']);
    expect(_ids(filterLibraryItems(items, foldForSearch('Café'))), ['3']);
  });

  test('matches artist names', () {
    expect(_ids(filterLibraryItems(items, foldForSearch('arijit'))), ['1']);
  });

  test('empty query keeps everything, no match gives empty', () {
    expect(filterLibraryItems(items, ''), same(items));
    expect(filterLibraryItems(items, 'zzz'), isEmpty);
  });

  test('filtering a chip bucket only searches that bucket', () {
    final albums = items.where((i) => i.type == 'album').toList();
    expect(filterLibraryItems(albums, 'tum'), isEmpty);
    expect(_ids(filterLibraryItems(albums, 'halo')), ['2']);
  });

  test('memo returns the same list until an input changes', () {
    final memo = LibraryListMemo<int>();
    var runs = 0;
    List<int> run(Object q) => memo.get([items, q], () {
      runs++;
      return [runs];
    });
    final a = run('a');
    expect(run('a'), same(a));
    expect(runs, 1);
    run('b');
    expect(runs, 2);
  });
}
