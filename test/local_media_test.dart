// Tests for the on-device music scan.
//
// These drive the real MethodChannel through a mock handler rather than
// calling internals, so the whole path is covered: the maps MediaStore
// actually produces, the FeedItem mapping, and the album/artist grouping.
//
// The shapes here are the ones a real library throws at you — missing tags,
// MediaStore's literal "<unknown>", the same album arriving under two ids —
// because that is where grouping goes wrong, not on tidy data.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunoh/api/dto.dart';
import 'package:sunoh/api/local_media_channel.dart';

const _channel = MethodChannel('codes.afk.sunoh/localmedia');

Map<String, Object?> _row({
  required String id,
  String title = 'Song',
  String artist = 'Artist',
  String album = 'Album',
  String albumId = '1',
  String path = '/music/song.mp3',
  int durationSec = 200,
  String? artPath,
  int year = 0,
}) => {
  'id': id,
  'title': title,
  'artist': artist,
  'album': album,
  'albumId': albumId,
  'artistId': '10',
  'durationSec': durationSec,
  'path': path,
  'track': 1,
  'year': year,
  'dateAdded': 0,
  'artPath': artPath,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void stub(Object? response) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          if (call.method != 'scan') return null;
          return response;
        });
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  group('mapping', () {
    test('a row becomes a playable local FeedItem', () async {
      stub([_row(id: '1', title: 'Velour Sky', path: '/music/velour.mp3')]);
      final scan = await LocalMediaChannel.instance.scan();

      expect(scan.songs, hasLength(1));
      final song = scan.songs.single;
      expect(song.title, 'Velour Sky');
      expect(song.type, 'song');
      expect(song.source, kLocalSource);
      // The path is what StreamResolver hands mpv — without it the track is
      // unplayable, which is why a row lacking one is dropped entirely.
      expect(song.url, '/music/velour.mp3');
      expect(song.duration, '200');
    });

    test('a row with no file path is dropped', () async {
      stub([_row(id: '1', path: ''), _row(id: '2', path: '/music/ok.mp3')]);
      final scan = await LocalMediaChannel.instance.scan();
      expect(scan.songs.map((s) => s.id), ['2']);
    });

    test('MediaStore\'s "<unknown>" is not shown as a real artist', () async {
      stub([_row(id: '1', artist: '<unknown>', album: '<unknown>')]);
      final scan = await LocalMediaChannel.instance.scan();

      expect(scan.songs.single.subtitle, isNull);
      expect(scan.albums, isEmpty, reason: 'no album to group under');
      expect(scan.artists, isEmpty);
    });

    test('album art rides as an image entry when present', () async {
      stub([
        _row(id: '1', artPath: '/cache/local_album_art/1.jpg'),
        _row(id: '2', artPath: null),
      ]);
      final scan = await LocalMediaChannel.instance.scan();

      expect(scan.songs[0].artwork, '/cache/local_album_art/1.jpg');
      expect(
        scan.songs[1].artwork,
        isNull,
        reason: 'falls back to generated art',
      );
    });
  });

  group('artwork for the OS', () {
    // The media notification and Android Auto both take a Uri, and both
    // silently show nothing for a scheme-less one. Local art is a bare
    // filesystem path, so it needs file:// added; network art must not be
    // touched.
    test('a local art path becomes a file:// uri', () async {
      stub([_row(id: '1', artPath: '/data/cache/local_album_art/7.jpg')]);
      final scan = await LocalMediaChannel.instance.scan();
      final uri = scan.songs.single.artworkUri;

      expect(uri, isNotNull);
      expect(uri!.scheme, 'file');
      expect(uri.toFilePath(), '/data/cache/local_album_art/7.jpg');
    });

    test('a network art url is left alone', () {
      const song = FeedItem(
        id: 'x',
        title: 'x',
        type: 'song',
        image: [ApiImage(quality: 'high', link: 'https://cdn/art.jpg')],
      );
      expect(song.artworkUri.toString(), 'https://cdn/art.jpg');
    });

    test('no artwork yields no uri', () {
      const song = FeedItem(id: 'x', title: 'x', type: 'song', image: []);
      expect(song.artworkUri, isNull);
    });
  });

  group('grouping', () {
    test('tracks bucket into albums and artists', () async {
      stub([
        _row(id: '1', album: 'Bone', artist: 'OKO'),
        _row(id: '2', album: 'Bone', artist: 'OKO'),
        _row(id: '3', album: 'Marble', artist: 'Niamh'),
      ]);
      final scan = await LocalMediaChannel.instance.scan();

      expect(scan.albums, hasLength(2));
      expect(scan.artists, hasLength(2));
      expect(scan.albums.first.name, 'Bone');
      expect(scan.albums.first.songs, hasLength(2));
    });

    test('the same album under two MediaStore ids is one album', () async {
      // Ripped twice, or synced from two sources: MediaStore hands back two
      // ALBUM_IDs for what the user sees as one album.
      stub([
        _row(id: '1', album: 'Bone', artist: 'OKO', albumId: '1'),
        _row(id: '2', album: 'Bone', artist: 'OKO', albumId: '99'),
      ]);
      final scan = await LocalMediaChannel.instance.scan();

      expect(scan.albums, hasLength(1));
      expect(scan.albums.single.songs, hasLength(2));
    });

    test('same album name by different artists stays separate', () async {
      // "Greatest Hits" is not one album.
      stub([
        _row(id: '1', album: 'Greatest Hits', artist: 'OKO'),
        _row(id: '2', album: 'Greatest Hits', artist: 'Niamh'),
      ]);
      final scan = await LocalMediaChannel.instance.scan();
      expect(scan.albums, hasLength(2));
    });

    test('grouping is case-insensitive but keeps the first spelling', () async {
      stub([
        _row(id: '1', album: 'Bone', artist: 'OKO'),
        _row(id: '2', album: 'BONE', artist: 'oko'),
      ]);
      final scan = await LocalMediaChannel.instance.scan();

      expect(scan.albums, hasLength(1));
      expect(scan.albums.single.name, 'Bone');
      expect(scan.artists, hasLength(1));
      expect(scan.artists.single.name, 'OKO');
    });

    test(
      'a title containing the subtitle separator does not misgroup',
      () async {
        // The subtitle renders as "artist · album", so anything deriving the
        // album back out of that string would split this row in the wrong place.
        stub([
          _row(id: '1', title: 'A · B', artist: 'X · Y', album: 'Real Album'),
        ]);
        final scan = await LocalMediaChannel.instance.scan();

        expect(scan.albums.single.name, 'Real Album');
        expect(scan.artists.single.name, 'X · Y');
      },
    );

    test('album collections expose the first available artwork', () async {
      // A compilation's first track often has no art while later ones do.
      stub([
        _row(id: '1', album: 'Comp', artist: 'V/A', artPath: null),
        _row(id: '2', album: 'Comp', artist: 'V/A', artPath: '/art/2.jpg'),
      ]);
      final scan = await LocalMediaChannel.instance.scan();
      expect(scan.albums.single.artwork, '/art/2.jpg');
    });

    test('newest-first order from the query is preserved', () async {
      stub([
        _row(id: '1', album: 'Newest', artist: 'A'),
        _row(id: '2', album: 'Older', artist: 'B'),
      ]);
      final scan = await LocalMediaChannel.instance.scan();
      expect(scan.albums.map((a) => a.name), ['Newest', 'Older']);
    });
  });

  group('failure', () {
    test('a platform error yields an empty scan, not a throw', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            throw PlatformException(code: 'scan_failed');
          });
      final scan = await LocalMediaChannel.instance.scan();
      expect(scan.songs, isEmpty);
      expect(scan.albums, isEmpty);
    });

    test('a null response yields an empty scan', () async {
      stub(null);
      final scan = await LocalMediaChannel.instance.scan();
      expect(scan.songs, isEmpty);
    });
  });
}
