import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:sunoh/api/ytmusic_api.dart';
import 'package:sunoh/audio/yt_like_store.dart';
import 'package:sunoh/audio/yt_like_sync.dart';

// ── Fake InnerTube ──────────────────────────────────────────────────────

class _Call {
  _Call(this.path, this.body);
  final String path;
  final Map<String, dynamic> body;
}

typedef _Handler = (int, Map<String, dynamic>) Function(_Call call);

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);
  final _Handler handler;
  final calls = <_Call>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    // The base URL is a compile-time define, empty under `flutter test`.
    final segs = Uri.parse(options.path).pathSegments;
    final at = segs.indexOf('v1');
    final path = segs.skip(at + 1).join('/');
    final call = _Call(path, Map<String, dynamic>.from(options.data as Map));
    calls.add(call);
    final (status, data) = handler(call);
    return ResponseBody.fromString(
      jsonEncode(data),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

YtMusicLikeRemote _remote(_FakeAdapter a) {
  final dio = Dio()..httpClientAdapter = a;
  return YtMusicLikeRemote(YtMusicApi(dio, auth: () async => {}));
}

Map<String, dynamic> _libraryWith(List<(String, String)> playlists) => {
  'contents': {
    'singleColumnBrowseResultsRenderer': {
      'tabs': [
        {
          'tabRenderer': {
            'content': {
              'sectionListRenderer': {
                'contents': [
                  {
                    'gridRenderer': {
                      'items': [
                        for (final (id, title) in playlists)
                          {
                            'musicTwoRowItemRenderer': {
                              'title': {
                                'runs': [
                                  {'text': title},
                                ],
                              },
                              'navigationEndpoint': {
                                'browseEndpoint': {'browseId': id},
                              },
                            },
                          },
                      ],
                    },
                  },
                ],
              },
            },
          },
        },
      ],
    },
  },
};

Map<String, dynamic> _playlistRows(Map<String, String> videoToSet) => {
  'contents': {
    'twoColumnBrowseResultsRenderer': {
      'secondaryContents': {
        'sectionListRenderer': {
          'contents': [
            {
              'musicPlaylistShelfRenderer': {
                'contents': [
                  for (final e in videoToSet.entries)
                    {
                      'musicResponsiveListItemRenderer': {
                        'playlistItemData': {
                          'videoId': e.key,
                          'playlistSetVideoId': e.value,
                        },
                      },
                    },
                ],
              },
            },
          ],
        },
      },
    },
  },
};

// ── A scripted account for the engine tests ─────────────────────────────

class _FakeRemote implements YtLikeRemote {
  final log = <String>[];
  String? existing;
  bool playlistExists = true;
  int failures = 0; // next N rate() calls throw
  final members = <String, String>{};

  @override
  Future<bool> rate(String v, {required bool like}) async {
    if (failures > 0) {
      failures--;
      throw StateError('offline');
    }
    log.add('${like ? 'like' : 'unlike'}:$v');
    return true;
  }

  @override
  Future<String?> findPlaylist(String title) async {
    log.add('find');
    return existing;
  }

  @override
  Future<String?> createPlaylist(String t, String d) async {
    log.add('create');
    playlistExists = true;
    return 'PLnew';
  }

  @override
  Future<Map<String, String>?> entries(String id) async =>
      playlistExists ? Map.of(members) : null;

  @override
  Future<bool> addVideo(String id, String v) async {
    log.add('add:$v');
    members[v] = 'set-$v';
    return true;
  }

  @override
  Future<bool> removeVideo(String id, String v, String s) async {
    log.add('remove:$v:$s');
    members.remove(v);
    return true;
  }
}

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ytsync_test');
    Hive.init(dir.path);
  });
  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  group('queue persistence', () {
    test('round-trips ops and the playlist id', () async {
      final store = YtLikeStore();
      await store.saveOps(const [YtLikeOp('aaaa1111', true)]);
      await store.savePlaylistId('PL1');
      await Hive.close();
      final again = YtLikeStore();
      final ops = await again.loadOps();
      expect(ops.single.videoId, 'aaaa1111');
      expect(ops.single.like, isTrue);
      expect(await again.loadPlaylistId(), 'PL1');
    });

    test('like then unlike before delivery cancels out', () async {
      // Offline, so the like stays queued when the unlike arrives.
      final fake = _FakeRemote()..failures = 99;
      final s = YtLikeSync(
        store: YtLikeStore(),
        remote: () => fake,
        isSignedIn: () => true,
        retries: 1,
        backoff: Duration.zero,
      );
      await s.enqueue('vid1', like: true);
      await s.enqueue('vid1', like: false);
      expect(await YtLikeStore().loadOps(), isEmpty);
    });

    test('signed out queues nothing', () async {
      final s = YtLikeSync(
        store: YtLikeStore(),
        remote: _FakeRemote.new,
        isSignedIn: () => false,
      );
      await s.enqueue('vid1', like: true);
      expect(await YtLikeStore().loadOps(), isEmpty);
    });

    test('an offline like survives and syncs later', () async {
      final fake = _FakeRemote()..failures = 99;
      final s = YtLikeSync(
        store: YtLikeStore(),
        remote: () => fake,
        isSignedIn: () => true,
        retries: 2,
        backoff: Duration.zero,
      );
      await s.enqueue('vid1', like: true);
      await s.drain();
      expect(fake.log, isEmpty);
      expect((await YtLikeStore().loadOps()).length, 1);

      fake.failures = 0;
      await s.drain();
      expect(fake.log, ['like:vid1', 'find', 'create', 'add:vid1']);
      expect(await YtLikeStore().loadOps(), isEmpty);
      expect(await YtLikeStore().loadPlaylistId(), 'PLnew');
    });
  });

  group('engine', () {
    YtLikeSync make(_FakeRemote r, {void Function()? first}) => YtLikeSync(
      store: YtLikeStore(),
      remote: () => r,
      isSignedIn: () => true,
      onFirstLikeSynced: first,
      retries: 1,
      backoff: Duration.zero,
    );

    test('reuses an existing Sunoh Tracks instead of creating one', () async {
      final r = _FakeRemote()..existing = 'PLold';
      await make(r).enqueue('vid1', like: true);
      expect(r.log, ['like:vid1', 'find', 'add:vid1']);
      expect(await YtLikeStore().loadPlaylistId(), 'PLold');
    });

    test('does not add a track twice', () async {
      final r = _FakeRemote()..members['vid1'] = 's1';
      await YtLikeStore().savePlaylistId('PL1');
      await make(r).enqueue('vid1', like: true);
      expect(r.log, ['like:vid1']);
    });

    test('unlike removes using the setVideoId from the playlist', () async {
      final r = _FakeRemote()..members['vid1'] = 'setA';
      await YtLikeStore().savePlaylistId('PL1');
      await make(r).enqueue('vid1', like: false);
      expect(r.log, ['unlike:vid1', 'remove:vid1:setA']);
    });

    test('recreates the playlist when YouTube says it is gone', () async {
      final r = _FakeRemote()..playlistExists = false;
      await YtLikeStore().savePlaylistId('PLdead');
      await make(r).enqueue('vid1', like: true);
      expect(r.log, ['like:vid1', 'find', 'create', 'add:vid1']);
      expect(await YtLikeStore().loadPlaylistId(), 'PLnew');
    });

    test('announces the first synced like once', () async {
      final r = _FakeRemote();
      var n = 0;
      final s = make(r, first: () => n++);
      await s.enqueue('vid1', like: true);
      await s.drain();
      await s.enqueue('vid2', like: true);
      await s.drain();
      expect(n, 1);
    });
  });

  group('InnerTube shapes', () {
    test(
      'finds the playlist by exact title and strips the VL prefix',
      () async {
        final a = _FakeAdapter(
          (_) => (
            200,
            _libraryWith([
              ('VLPLother', 'Sunoh Tracks 2'),
              ('VLPLmine', 'Sunoh Tracks'),
            ]),
          ),
        );
        expect(await _remote(a).findPlaylist('Sunoh Tracks'), 'PLmine');
        expect(a.calls.single.path, 'browse');
      },
    );

    test('returns null when no playlist has that title', () async {
      final a = _FakeAdapter((_) => (200, _libraryWith([('VLPL1', 'Gym')])));
      expect(await _remote(a).findPlaylist('Sunoh Tracks'), isNull);
    });

    test('create sends a private playlist and reads the id', () async {
      final a = _FakeAdapter((_) => (200, {'playlistId': 'PLfresh'}));
      expect(
        await _remote(a).createPlaylist('Sunoh Tracks', 'desc'),
        'PLfresh',
      );
      expect(a.calls.single.path, 'playlist/create');
      expect(a.calls.single.body['privacyStatus'], 'PRIVATE');
    });

    test('entries map videoId to setVideoId; 404 means gone', () async {
      final a = _FakeAdapter(
        (c) => (200, _playlistRows({'vidA': 'setA', 'vidB': 'setB'})),
      );
      final e = await _remote(a).entries('PL1');
      expect(e, {'vidA': 'setA', 'vidB': 'setB'});
      expect(a.calls.single.body['browseId'], 'VLPL1');

      final gone = _FakeAdapter((_) => (404, {'error': {}}));
      expect(await _remote(gone).entries('PL1'), isNull);
    });

    test('rate, add and remove payloads', () async {
      final a = _FakeAdapter((_) => (200, {}));
      final r = _remote(a);
      expect(await r.rate('vidA', like: true), isTrue);
      await r.rate('vidA', like: false);
      await r.addVideo('PL1', 'vidA');
      await r.removeVideo('PL1', 'vidA', 'setA');
      expect(a.calls.map((c) => c.path), [
        'like/like',
        'like/removelike',
        'browse/edit_playlist',
        'browse/edit_playlist',
      ]);
      expect(a.calls[0].body['target'], {'videoId': 'vidA'});
      final add = (a.calls[2].body['actions'] as List).single as Map;
      expect(add['action'], 'ACTION_ADD_VIDEO');
      expect(add['addedVideoId'], 'vidA');
      final rm = (a.calls[3].body['actions'] as List).single as Map;
      expect(rm['action'], 'ACTION_REMOVE_VIDEO');
      expect(rm['setVideoId'], 'setA');
    });

    test('a server error throws so the queue retries', () async {
      final a = _FakeAdapter((_) => (503, {}));
      expect(_remote(a).rate('vidA', like: true), throwsA(anything));
    });
  });
}
