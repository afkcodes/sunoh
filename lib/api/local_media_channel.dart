// Dart side of the on-device music scan.
//
// The native half (android/.../localmedia/LocalMediaBridge.kt) reads
// MediaStore and hands back plain maps; this turns them into the same
// [FeedItem] every other source produces, so local tracks flow through the
// existing queue, player, search and Android Auto without special cases.
//
// Android-only. Every method degrades to an empty result elsewhere so callers
// need no platform checks.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'dto.dart';

/// A group of on-device tracks sharing an album or an artist.
///
/// Built during the scan, while album and artist are still separate MediaStore
/// columns. Deriving them later from a formatted subtitle would misgroup any
/// track whose title or artist contains the separator.
class LocalCollection {
  const LocalCollection({
    required this.id,
    required this.name,
    required this.songs,
    this.subtitle,
  });

  final String id;
  final String name;
  final String? subtitle;
  final List<FeedItem> songs;

  /// Artwork of the first track that has any — on a compilation the first
  /// track often has none while later ones do.
  String? get artwork {
    for (final s in songs) {
      final art = s.artwork;
      if (art != null && art.isNotEmpty) return art;
    }
    return null;
  }
}

/// Everything one scan produced.
class LocalScan {
  const LocalScan({
    required this.songs,
    required this.albums,
    required this.artists,
  });
  const LocalScan.empty()
    : songs = const [],
      albums = const [],
      artists = const [];

  final List<FeedItem> songs;
  final List<LocalCollection> albums;
  final List<LocalCollection> artists;
}

/// The `source` marker carried by every on-device track.
///
/// `StreamResolver` keys its local-file tier off this, and the UI uses it to
/// label provenance. Any change here has to change both.
const String kLocalSource = 'local';

class LocalMediaChannel {
  LocalMediaChannel._();
  static final LocalMediaChannel instance = LocalMediaChannel._();

  static const MethodChannel _channel = MethodChannel(
    'codes.afk.sunoh/localmedia',
  );

  bool get _supported => defaultTargetPlatform == TargetPlatform.android;

  /// Every music file on the device, newest first.
  ///
  /// Returns an empty list rather than throwing on any failure — a denied
  /// permission, an unreadable volume, a platform that isn't Android. The
  /// caller distinguishes "no music" from "not allowed" by checking the
  /// permission itself, not by catching from here.
  Future<LocalScan> scan() async {
    if (!_supported) return const LocalScan.empty();
    try {
      final raw = await _channel.invokeListMethod<Object?>('scan');
      if (raw == null) return const LocalScan.empty();
      return _group(raw);
    } on PlatformException catch (e) {
      debugPrint('[local] scan failed: ${e.message}');
      return const LocalScan.empty();
    } catch (e) {
      debugPrint('[local] scan error: $e');
      return const LocalScan.empty();
    }
  }

  /// Map rows to FeedItems and bucket them in one pass.
  ///
  /// Insertion order is preserved throughout: the query returns newest-first,
  /// so albums come out most-recently-added first, which is what someone
  /// looking for music they just copied over expects.
  static LocalScan _group(List<Object?> rows) {
    final songs = <FeedItem>[];
    final albums = <String, List<FeedItem>>{};
    final albumNames = <String, String>{};
    final albumArtistSets = <String, Set<String>>{};
    final artists = <String, List<FeedItem>>{};
    final artistNames = <String, String>{};

    for (final row in rows) {
      if (row is! Map) continue;
      final r = row.cast<Object?, Object?>();
      final song = _toFeedItem(r);
      if (song == null) continue;
      songs.add(song);

      final artist = _clean((r['artist'] ?? '').toString());
      final album = _clean((r['album'] ?? '').toString());

      if (album != null) {
        // Keyed on MediaStore's ALBUM_ID, which is what actually corresponds
        // to one album on disk.
        //
        // An earlier version keyed on album + track artist, reasoning that two
        // artists' "Greatest Hits" are not one album. True, but it splits every
        // soundtrack and compilation — where the track artist differs per
        // track — into one entry per singer, which is by far the more common
        // case: one film soundtrack showed up four times, once per playback
        // singer.
        final key = (r['albumId'] ?? '').toString();
        if (key.isNotEmpty && key != '0') {
          albums
              .putIfAbsent(key, () {
                albumNames[key] = album;
                return <FeedItem>[];
              })
              .add(song);
          // Every artist on the album, so the subtitle can say "Various
          // artists" rather than pick whichever track happened to come first.
          albumArtistSets.putIfAbsent(key, () => <String>{}).add(artist ?? '');
        }
      }

      if (artist != null) {
        final key = artist.toLowerCase();
        artists
            .putIfAbsent(key, () {
              artistNames[key] = artist;
              return <FeedItem>[];
            })
            .add(song);
      }
    }

    debugPrint(
      '[local] scanned ${songs.length} tracks, '
      '${albums.length} albums, ${artists.length} artists',
    );
    return LocalScan(
      songs: songs,
      albums: [
        for (final e in albums.entries)
          LocalCollection(
            id: e.key,
            name: albumNames[e.key] ?? '',
            subtitle: _albumArtist(albumArtistSets[e.key]),
            songs: e.value,
          ),
      ],
      artists: [
        for (final e in artists.entries)
          LocalCollection(
            id: e.key,
            name: artistNames[e.key] ?? '',
            subtitle: '${e.value.length} songs',
            songs: e.value,
          ),
      ],
    );
  }

  /// The artist line for an album: the one artist if it has a single one,
  /// otherwise "Various artists". Naming one singer off a soundtrack that has
  /// six is worse than naming none.
  static String? _albumArtist(Set<String>? artists) {
    final named = (artists ?? const <String>{})
        .where((a) => a.isNotEmpty)
        .toList();
    if (named.isEmpty) return null;
    return named.length == 1 ? named.first : 'Various artists';
  }

  /// One MediaStore row as a FeedItem.
  ///
  /// The file path rides in `url`: that is what `StreamResolver` hands mpv,
  /// and it is also the only field that makes a local track playable, so a row
  /// without one is dropped.
  static FeedItem? _toFeedItem(Map<Object?, Object?> row) {
    final id = row['id']?.toString();
    final path = row['path']?.toString();
    if (id == null || id.isEmpty || path == null || path.isEmpty) return null;

    final artist = (row['artist'] ?? '').toString().trim();
    final album = (row['album'] ?? '').toString().trim();
    final artPath = row['artPath']?.toString();
    final duration = (row['durationSec'] as num?)?.toInt() ?? 0;

    return FeedItem(
      id: id,
      title: (row['title'] ?? 'Unknown').toString(),
      type: 'song',
      source: kLocalSource,
      url: path,
      // Album art is a cached file on disk, not a URL. `ApiImage.link` is
      // just a string to everything downstream, and `SunohArt` renders a
      // path with Image.file — see its `imageUrl` handling.
      image: [
        if (artPath != null && artPath.isNotEmpty)
          ApiImage(quality: 'high', link: artPath),
      ],
      subtitle: _subtitleFor(artist, album),
      duration: duration > 0 ? duration.toString() : null,
      artists: artist.isEmpty
          ? null
          : [
              ApiArtistRef(
                id: (row['artistId'] ?? '').toString(),
                name: artist,
              ),
            ],
      releaseDate: _yearOf(row['year']),
    );
  }

  /// MediaStore leaves unknown fields as the literal `<unknown>` rather than
  /// empty, which would otherwise show up as a track's artist.
  static String? _subtitleFor(String artist, String album) {
    final a = _clean(artist);
    final b = _clean(album);
    if (a != null && b != null) return '$a · $b';
    return a ?? b;
  }

  static String? _clean(String value) {
    final v = value.trim();
    if (v.isEmpty || v == '<unknown>') return null;
    return v;
  }

  static String? _yearOf(Object? raw) {
    final year = (raw as num?)?.toInt() ?? 0;
    return year > 0 ? year.toString() : null;
  }
}
