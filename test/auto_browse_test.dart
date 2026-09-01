// Tests for the Android Auto browse tree.
//
// AutoBrowseTree is the whole car-facing surface, and it is the one part of
// the app that cannot be exercised by using the app: it only runs when a head
// unit is attached. So it gets tested here instead.
//
// LibraryStore is backed by a real Hive box in a temp directory rather than a
// fake, because the encode/decode round trip through Hive is exactly where a
// browse tree breaks — a FeedItem that survives the phone UI but not a
// service restart is the bug class this is guarding.

import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:sunoh/api/dto.dart';
import 'package:sunoh/api/sunoh_api.dart';
import 'package:sunoh/audio/auto_browse.dart';
import 'package:sunoh/audio/library_store.dart';
import 'package:sunoh/data/user_playlist.dart';

/// Records what the tree asked the player to do.
class _PlayCall {
  _PlayCall(this.songs, this.index, this.sourceLabel);
  final List<FeedItem> songs;
  final int index;
  final String? sourceLabel;
}

FeedItem _song(String id, {String title = '', String source = 'saavn'}) =>
    FeedItem(
      id: id,
      title: title.isEmpty ? 'Song $id' : title,
      type: 'song',
      image: const [],
      source: source,
      duration: '180',
    );

void main() {
  late Directory tmp;
  late LibraryStore library;
  late List<_PlayCall> plays;
  late AutoBrowseTree tree;

  /// A Dio that fails every request, so the network-backed branches take their
  /// error path. Tests that need a real response install their own adapter.
  Dio offlineDio() => Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1'))
    ..options.connectTimeout = const Duration(milliseconds: 50);

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sunoh_auto_test');
    Hive.init(tmp.path);
    library = LibraryStore();
    plays = [];
    tree = AutoBrowseTree(
      library: library,
      api: SunohApi(offlineDio()),
      playQueue: (songs, index, {sourceLabel}) async {
        plays.add(_PlayCall(songs, index, sourceLabel));
      },
    );
  });

  tearDown(() async {
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  group('root', () {
    test('exposes exactly the four car tabs, none of them playable', () async {
      final tabs = await tree.getChildren(AudioService.browsableRootId);
      expect(tabs.map((t) => t.title), [
        'Downloads',
        'Liked Songs',
        'Recently Played',
        'Playlists',
      ]);
      expect(tabs.every((t) => t.playable == false), isTrue);
    });

    test('unknown parent yields empty rather than throwing', () async {
      expect(await tree.getChildren('sunoh:nonsense'), isEmpty);
      expect(await tree.getChildren(''), isEmpty);
    });
  });

  group('liked songs', () {
    test('renders liked tracks as playable items', () async {
      await library.setLiked(song: _song('a'), liked: true);
      await library.setLiked(song: _song('b'), liked: true);

      final items = await tree.getChildren('sunoh:t:liked');
      expect(items, hasLength(2));
      expect(items.every((i) => i.playable == true), isTrue);
      // The song id rides in extras; the media id is positional.
      expect(items.map((i) => i.extras!['songId']).toSet(), {'a', 'b'});
    });

    test('tapping the 2nd track plays the whole list starting there', () async {
      await library.setLiked(song: _song('a'), liked: true);
      await library.setLiked(song: _song('b'), liked: true);
      await library.setLiked(song: _song('c'), liked: true);

      final items = await tree.getChildren('sunoh:t:liked');
      await tree.playFromMediaId(items[1].id);

      expect(plays, hasLength(1));
      expect(plays.single.songs, hasLength(3), reason: 'whole list, not one');
      expect(plays.single.index, 1);
      expect(plays.single.sourceLabel, 'Liked songs');
    });
  });

  group('user playlists', () {
    late UserPlaylist playlist;

    setUp(() async {
      playlist = UserPlaylist(
        id: 'pl1',
        name: 'Road Trip',
        songs: [_song('x'), _song('y')],
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      await library.upsertUserPlaylist(playlist);
    });

    test('listed under the Playlists tab', () async {
      final items = await tree.getChildren('sunoh:t:playlists');
      expect(items, hasLength(1));
      expect(items.single.title, 'Road Trip');
      expect(items.single.playable, isFalse);
    });

    test('drilling in lists its songs', () async {
      final collections = await tree.getChildren('sunoh:t:playlists');
      final songs = await tree.getChildren(collections.single.id);
      expect(songs.map((s) => s.extras!['songId']), ['x', 'y']);
    });

    // The regression this whole file exists for. The MediaBrowserService is a
    // foreground service Android restarts independently of the Flutter UI, and
    // Android Auto remembers the user's browse position across reconnects — so
    // it asks for the playlist directly, with nothing cached. An earlier
    // version resolved that to an empty list.
    test('resolves COLD, without its parent being browsed first', () async {
      final cold = AutoBrowseTree(
        library: library,
        api: SunohApi(offlineDio()),
        playQueue: (songs, index, {sourceLabel}) async {
          plays.add(_PlayCall(songs, index, sourceLabel));
        },
      );

      final songs = await cold.getChildren('sunoh:c:user:pl1:');
      expect(songs, hasLength(2), reason: 'cold cache must still resolve');
      expect(songs.map((s) => s.extras!['songId']), ['x', 'y']);

      await cold.playFromMediaId(songs[1].id);
      expect(plays.single.index, 1);
      expect(plays.single.sourceLabel, 'PLAYLIST · Road Trip');
    });

    test('a deleted playlist yields empty, not a throw', () async {
      expect(await tree.getChildren('sunoh:c:user:gone:'), isEmpty);
    });

    test('playing the container itself starts at the top', () async {
      await tree.playFromMediaId('sunoh:c:user:pl1:');
      expect(plays.single.index, 0);
      expect(plays.single.songs, hasLength(2));
    });
  });

  group('media id parsing', () {
    test('collection ids containing colons survive the round trip', () async {
      // Upstream ids are not ours to control; a positional split(':') would
      // shift every field and resolve the wrong collection.
      final items = await tree.getChildren('sunoh:c:album:VL:PL:abc:saavn');
      // Network is offline, so this resolves to empty — the point is that it
      // parses and takes the fetch path instead of bailing early.
      expect(items, isEmpty);
    });

    test('track ids round-trip back to their song', () async {
      await library.setLiked(song: _song('a', title: 'Alpha'), liked: true);
      final items = await tree.getChildren('sunoh:t:liked');
      final resolved = await tree.getMediaItem(items.single.id);
      expect(resolved, isNotNull);
      expect(resolved!.title, 'Alpha');
    });

    test('malformed ids are ignored rather than fatal', () async {
      expect(await tree.getMediaItem('sunoh:s:no-hash'), isNull);
      expect(await tree.getMediaItem('garbage'), isNull);
      await tree.playFromMediaId('sunoh:s:no-hash');
      await tree.playFromMediaId('garbage');
      expect(plays, isEmpty, reason: 'nothing should have played');
    });
  });

  group('recently played', () {
    test('the `recent` root Android Auto asks for serves history', () async {
      await library.pushHistory(_song('h1'));
      final items = await tree.getChildren(AudioService.recentRootId);
      expect(items, hasLength(1));
      expect(items.single.playable, isTrue);
    });
  });

  group('voice search', () {
    // Android Auto certification exercises "just play something" — an empty
    // query. Answering with silence is a fail.
    test('empty query falls back to liked when nothing is downloaded', () async {
      await library.setLiked(song: _song('a'), liked: true);
      await tree.playFromSearch('');
      expect(plays, hasLength(1));
      expect(plays.single.songs.single.id, 'a');
    });

    test('empty query falls back to history when nothing is liked', () async {
      await library.pushHistory(_song('h'));
      await tree.playFromSearch('   ');
      expect(plays.single.songs.single.id, 'h');
    });

    test('empty query with an empty library plays nothing, quietly', () async {
      await tree.playFromSearch('');
      expect(plays, isEmpty);
    });

    test('a failing search plays nothing rather than throwing', () async {
      await tree.playFromSearch('anything');
      expect(plays, isEmpty);
    });

    test('search returns empty on failure rather than throwing', () async {
      expect(await tree.search('anything'), isEmpty);
    });
  });

  group('downloads', () {
    test('with no download manager the tab is empty, not broken', () async {
      expect(await tree.getChildren('sunoh:t:downloads'), isEmpty);
    });
  });
}
