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
        _row(id: '1', album: 'Bone', artist: 'OKO', albumId: '1'),
        _row(id: '2', album: 'Bone', artist: 'OKO', albumId: '1'),
        _row(id: '3', album: 'Marble', artist: 'Niamh', albumId: '2'),
      ]);
      final scan = await LocalMediaChannel.instance.scan();

      expect(scan.albums, hasLength(2));
      expect(scan.artists, hasLength(2));
      expect(scan.albums.first.name, 'Bone');
      expect(scan.albums.first.songs, hasLength(2));
    });

    test('a soundtrack stays one album despite per-track artists', () async {
      // The case that made this key on ALBUM_ID. Film soundtracks carry a
      // different playback singer per track, so keying on album + track artist
      // split one album into one entry per singer.
      stub([
        _row(id: '1', album: 'Tere Naam', artist: 'Alka Yagnik', albumId: '5'),
        _row(id: '2', album: 'Tere Naam', artist: 'Udit Narayan', albumId: '5'),
        _row(id: '3', album: 'Tere Naam', artist: 'Himesh', albumId: '5'),
      ]);
      final scan = await LocalMediaChannel.instance.scan();

      expect(scan.albums, hasLength(1));
      expect(scan.albums.single.songs, hasLength(3));
      // Naming one singer off a six-singer soundtrack is worse than naming none.
      expect(scan.albums.single.subtitle, 'Various artists');
    });

    test('a single-artist album is credited to that artist', () async {
      stub([
        _row(id: '1', album: 'Bone', artist: 'OKO', albumId: '7'),
        _row(id: '2', album: 'Bone', artist: 'OKO', albumId: '7'),
      ]);
      final scan = await LocalMediaChannel.instance.scan();
      expect(scan.albums.single.subtitle, 'OKO');
    });

    test('rows with no album id are not grouped as an album', () async {
      stub([_row(id: '1', album: 'Loose', albumId: '0')]);
      final scan = await LocalMediaChannel.instance.scan();
      expect(scan.songs, hasLength(1), reason: 'still playable');
      expect(scan.albums, isEmpty);
    });

    test('same album name by different artists stays separate', () async {
      // "Greatest Hits" is not one album.
      // Two different albums on disk, so two ALBUM_IDs.
      stub([
        _row(id: '1', album: 'Greatest Hits', artist: 'OKO', albumId: '1'),
        _row(id: '2', album: 'Greatest Hits', artist: 'Niamh', albumId: '2'),
      ]);
      final scan = await LocalMediaChannel.instance.scan();
      expect(scan.albums, hasLength(2));
    });

    test('artists group case-insensitively, keeping the first spelling', () {
      // Artists have no MediaStore id we can trust the way albums do — the
      // same name arrives capitalised differently across files.
      stub([
        _row(id: '1', album: 'Bone', artist: 'OKO', albumId: '1'),
        _row(id: '2', album: 'Bone', artist: 'oko', albumId: '1'),
      ]);
      return LocalMediaChannel.instance.scan().then((scan) {
        expect(scan.artists, hasLength(1));
        expect(scan.artists.single.name, 'OKO');
      });
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
        _row(id: '1', album: 'Newest', artist: 'A', albumId: '1'),
        _row(id: '2', album: 'Older', artist: 'B', albumId: '2'),
      ]);
      final scan = await LocalMediaChannel.instance.scan();
      expect(scan.albums.map((a) => a.name), ['Newest', 'Older']);
    });
  });

  group('folders', () {
    test('every folder is reported with a count, largest first', () async {
      stub([
        _row(id: '1', path: '/Music/a.mp3'),
        _row(id: '2', path: '/Music/b.mp3'),
        _row(id: '3', path: '/Ringtones/r.mp3'),
      ]);
      final scan = await LocalMediaChannel.instance.scan();

      expect(scan.folders.map((f) => f.path), ['/Music', '/Ringtones']);
      expect(scan.folders.first.trackCount, 2);
      expect(scan.folders.first.name, 'Music');
    });

    test('choosing nothing uses the whole device', () async {
      // The default. A fresh install has to find music without being
      // configured first, so an empty choice cannot mean an empty library.
      stub([
        _row(id: '1', path: '/Music/a.mp3'),
        _row(id: '2', path: '/WhatsApp/voice.mp3'),
      ]);
      final scan = await LocalMediaChannel.instance.scan();

      expect(scan.songs.map((s) => s.id), ['1', '2']);
    });

    test('choosing a folder leaves everything else out', () async {
      stub([
        _row(id: '1', path: '/Music/a.mp3'),
        _row(id: '2', path: '/WhatsApp/voice.mp3'),
      ]);
      final scan = await LocalMediaChannel.instance.scan(
        includedFolders: {'/Music'},
      );

      expect(scan.songs.map((s) => s.id), ['1']);
    });

    test('a chosen folder brings its subfolders with it', () async {
      // The reason this is an include list and not an exclude list: one
      // album-per-folder library is a hundred directories under one parent.
      stub([
        _row(id: '1', path: '/Music/Rock/Album/a.mp3'),
        _row(id: '2', path: '/Music/b.mp3'),
        _row(id: '3', path: '/Podcasts/c.mp3'),
      ]);
      final scan = await LocalMediaChannel.instance.scan(
        includedFolders: {'/Music'},
      );

      expect(scan.songs.map((s) => s.id), ['1', '2']);
    });

    test('a folder left out still appears in the folder list', () async {
      // Otherwise there is no way back: the folder you left out would vanish
      // from the list that lets you add it.
      stub([
        _row(id: '1', path: '/Music/a.mp3'),
        _row(id: '2', path: '/WhatsApp/voice.mp3'),
      ]);
      final scan = await LocalMediaChannel.instance.scan(
        includedFolders: {'/Music'},
      );

      expect(scan.folders.map((f) => f.path), contains('/WhatsApp'));
      expect(
        scan.folders.firstWhere((f) => f.path == '/WhatsApp').trackCount,
        1,
        reason: 'counts cover every row, chosen or not',
      );
    });

    test('leaving a folder out removes its albums and artists too', () async {
      stub([
        _row(
          id: '1',
          path: '/Music/a.mp3',
          album: 'Real',
          artist: 'A',
          albumId: '1',
        ),
        _row(
          id: '2',
          path: '/Tones/t.mp3',
          album: 'Tones',
          artist: 'System',
          albumId: '2',
        ),
      ]);
      final scan = await LocalMediaChannel.instance.scan(
        includedFolders: {'/Music'},
      );

      expect(scan.albums.map((a) => a.name), ['Real']);
      expect(scan.artists.map((a) => a.name), ['A']);
    });

    test('a sibling with the same prefix is not swept in', () async {
      // '/Music' must not silently take '/MusicVideos' with it.
      stub([
        _row(id: '1', path: '/Music/a.mp3'),
        _row(id: '2', path: '/MusicVideos/b.mp3'),
      ]);
      final scan = await LocalMediaChannel.instance.scan(
        includedFolders: {'/Music'},
      );

      expect(scan.songs.map((s) => s.id), ['1']);
    });

    test('a path with no directory part is not counted as a folder', () async {
      stub([_row(id: '1', path: 'bare.mp3')]);
      final scan = await LocalMediaChannel.instance.scan();

      expect(scan.songs, hasLength(1), reason: 'still playable');
      expect(scan.folders, isEmpty);
    });
  });

  group('isUnderAnyRoot', () {
    test('no roots means everything', () {
      expect(isUnderAnyRoot('/anywhere', const {}), isTrue);
    });

    test('the root itself counts', () {
      expect(isUnderAnyRoot('/Music', const {'/Music'}), isTrue);
    });

    test('a descendant counts at any depth', () {
      expect(isUnderAnyRoot('/Music/a/b/c', const {'/Music'}), isTrue);
    });

    test('a prefix that is not a path boundary does not count', () {
      expect(isUnderAnyRoot('/MusicVideos', const {'/Music'}), isFalse);
    });

    test('any one root is enough', () {
      expect(
        isUnderAnyRoot('/Podcasts/x', const {'/Music', '/Podcasts'}),
        isTrue,
      );
    });
  });

  group('folderLocation', () {
    test('drops the storage prefix and the folder name itself', () {
      expect(
        folderLocation('/storage/emulated/0/Download/Seal/Tere Naam'),
        'Download/Seal',
      );
    });

    test('two same-named folders read differently', () {
      // The whole reason the subtitle exists.
      expect(
        folderLocation('/storage/emulated/0/Download/Seal/Tere Naam'),
        isNot(folderLocation('/storage/emulated/0/Music/Tere Naam')),
      );
    });

    test('a folder at the storage root says where it is', () {
      expect(folderLocation('/storage/emulated/0/Music'), 'Internal storage');
    });

    test('a removable volume keeps its path', () {
      expect(
        folderLocation('/storage/1A2B-3C4D/Music/Rock'),
        'storage/1A2B-3C4D/Music',
      );
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
