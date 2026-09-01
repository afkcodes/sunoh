// Tests for the Music / Podcasts / Audiobooks browse nodes.
//
// These run against a stubbed HTTP adapter rather than the offline Dio the
// other Auto tests use, because what matters here is how real feed *shapes*
// are turned into rows — a section of songs, a section of collections, a
// section that mixes them, and a section of something we cannot route.
//
// The last case is the one that bites in a car: an unroutable row is dropped,
// and a section of nothing but unroutable rows would otherwise render as a
// blank screen that looks like a network failure.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunoh/api/dto.dart';
import 'package:sunoh/api/sunoh_api.dart';
import 'package:sunoh/audio/auto_catalog.dart';
import 'package:sunoh/audio/auto_feeds.dart';

/// Serves canned JSON for whatever path is asked for.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.byPath);
  final Map<String, Object?> byPath;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = byPath[options.path];
    if (body == null) {
      return ResponseBody.fromString('{"status":"error"}', 404);
    }
    return ResponseBody.fromString(
      jsonEncode({'status': 'success', 'data': body}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object?> _item(String id, String type, {String title = 'x'}) => {
  'id': id,
  'title': title,
  'type': type,
  'image': [],
  'source': 'saavn',
};

Map<String, Object?> _section(
  String heading,
  List<Map<String, Object?>> items,
) => {'heading': heading, 'data': items};

void main() {
  AutoFeeds feedsFor(List<Map<String, Object?>> sections) {
    final dio = Dio(BaseOptions(baseUrl: 'https://stub'))
      ..httpClientAdapter = _StubAdapter({'/music/home': sections});
    return AutoFeeds(api: SunohApi(dio), catalog: AutoCatalog());
  }

  test('a section of songs becomes one playable queue', () async {
    final feeds = feedsFor([
      _section('Top songs', [
        _item('a', 'song'),
        _item('b', 'song'),
        _item('c', 'song'),
      ]),
    ]);
    final sections = await feeds.sections('sunoh:f:music');
    expect(sections, hasLength(1));
    expect(sections.single.title, 'Top songs');

    final rows = await feeds.sectionItems(sections.single.id);
    expect(rows, hasLength(3));
    expect(rows.every((r) => r.playable == true), isTrue);
  });

  test(
    'a mixed section keeps songs playable and collections browsable',
    () async {
      final feeds = feedsFor([
        _section('Trending', [
          _item('col1', 'playlist'),
          _item('s1', 'song'),
          _item('col2', 'album'),
          _item('s2', 'song'),
        ]),
      ]);
      final sections = await feeds.sections('sunoh:f:music');
      final rows = await feeds.sectionItems(sections.single.id);

      expect(rows, hasLength(4));
      expect(rows.where((r) => r.playable == true), hasLength(2));
      expect(rows.where((r) => r.playable == false), hasLength(2));

      // Mixed content must hint list for BOTH kinds. With browsable hinted as a
      // grid the car renders collections as full-width artwork tiles between
      // compact song rows, and the list visibly stutters between row heights.
      for (final row in rows.where((r) => r.playable == false)) {
        expect(
          row.extras?['android.media.browse.CONTENT_STYLE_BROWSABLE_HINT'],
          1,
        );
        expect(
          row.extras?['android.media.browse.CONTENT_STYLE_PLAYABLE_HINT'],
          1,
        );
      }
    },
  );

  test('songs in a mixed section are numbered among themselves', () async {
    // The second song is queue index 1, not 3 — the collections between them
    // are not part of the queue.
    final feeds = feedsFor([
      _section('Mixed', [
        _item('col1', 'playlist'),
        _item('s1', 'song'),
        _item('col2', 'album'),
        _item('s2', 'song'),
      ]),
    ]);
    final sections = await feeds.sections('sunoh:f:music');
    final sectionId = sections.single.id;
    final rows = await feeds.sectionItems(sectionId);
    final songRows = rows.where((r) => r.playable == true).toList();

    expect(songRows[0].id, 'sunoh:s:$sectionId#0');
    expect(songRows[1].id, 'sunoh:s:$sectionId#1');
  });

  test('audiobook genre shelves are browsable, not dropped', () async {
    // These carry type `audiobook_category` and appear in the real audiobooks
    // feed as "Browse genres". Unhandled, every row is dropped and the whole
    // section renders blank in the car.
    expect(
      AutoCatalog.collectionIdFor(
        const FeedItem(
          id: '104',
          title: 'Literature & Fiction',
          type: 'audiobook_category',
          image: [],
          source: 'saavn',
        ),
      ),
      'sunoh:c:cat:104:saavn',
    );
  });

  test('a section of only unroutable rows is not listed at all', () async {
    final feeds = feedsFor([
      _section('Fine', [_item('s1', 'song')]),
      _section('Unroutable', [
        _item('u1', 'some_future_type'),
        _item('u2', 'another_unknown'),
      ]),
    ]);
    final sections = await feeds.sections('sunoh:f:music');
    expect(sections.map((s) => s.title), ['Fine']);
  });

  test(
    'a feed whose request fails renders empty rather than throwing',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://stub'))
        ..httpClientAdapter = _StubAdapter(const {});
      final feeds = AutoFeeds(api: SunohApi(dio), catalog: AutoCatalog());
      expect(await feeds.sections('sunoh:f:music'), isEmpty);
    },
  );
}
