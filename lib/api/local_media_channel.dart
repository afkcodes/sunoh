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
import 'local_sort.dart';

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

/// One folder on the device that holds music, and how much.
///
/// Derived from the file paths rather than asked for separately: MediaStore
/// has no folder table, and the path is already on every row.
class LocalFolder {
  const LocalFolder({
    required this.path,
    required this.name,
    required this.trackCount,
  });

  /// Absolute directory path. This is the identity used by the ignore list,
  /// so it is stored verbatim and never normalised or prettified.
  final String path;

  /// Last path segment, for display. Folders are usually recognisable by
  /// their own name; the full path is long and mostly noise.
  final String name;

  final int trackCount;
}

/// Everything one scan produced.
class LocalScan {
  const LocalScan({
    required this.songs,
    required this.albums,
    required this.artists,
    this.folders = const [],
    this.meta = const {},
  });
  const LocalScan.empty()
    : songs = const [],
      albums = const [],
      artists = const [],
      folders = const [],
      meta = const {};

  final List<FeedItem> songs;
  final List<LocalCollection> albums;
  final List<LocalCollection> artists;

  /// Sortable per-track fields, keyed by song id. See [LocalTrackMeta].
  final Map<String, LocalTrackMeta> meta;

  /// Every folder the scan saw, **including ones left out**, largest first.
  ///
  /// The excluded ones have to be here or there is no way back: a folder
  /// missing from the library would vanish from the list that lets you add
  /// it.
  final List<LocalFolder> folders;
}

/// Where a folder sits, written the way a person would read it.
///
/// The full path is useless as a subtitle: on a real device every music folder
/// starts `/storage/emulated/0/Download/...`, so a row that elides the tail
/// shows the same string for every folder and disambiguates nothing. The
/// distinguishing part is at the end, and the last segment is already the
/// row's title — so this drops the storage prefix and the name, leaving the
/// parent chain that actually tells two same-named folders apart.
String folderLocation(String path) {
  var p = path;
  for (final prefix in const [
    '/storage/emulated/0',
    '/sdcard',
    '/mnt/sdcard',
  ]) {
    if (p == prefix) return 'Internal storage';
    if (p.startsWith('$prefix/')) {
      p = p.substring(prefix.length);
      break;
    }
  }
  final i = p.lastIndexOf('/');
  final parent = i <= 0 ? '' : p.substring(1, i);
  return parent.isEmpty ? 'Internal storage' : parent;
}

/// Sortable fields MediaStore gives us that [FeedItem] has no room for.
///
/// Kept beside the songs rather than added to FeedItem: that DTO is shared by
/// every source, and a track number means nothing to a YouTube result. Keyed
/// by song id in [LocalScan.meta].
class LocalTrackMeta {
  const LocalTrackMeta({
    required this.disc,
    required this.track,
    required this.dateAdded,
    this.genre,
  });

  /// Disc number, 1 when the file does not say.
  final int disc;

  /// Track number within the disc, 0 when the file does not say.
  final int track;

  /// Epoch seconds, as MediaStore reports it.
  final int dateAdded;

  final String? genre;

  /// MediaStore packs multi-disc albums into one integer as
  /// `disc * 1000 + track`, so track 1 of disc 2 arrives as 2001. Anything
  /// below 1000 is a plain track number on a single-disc release.
  factory LocalTrackMeta.fromRow(Map<Object?, Object?> row) {
    final raw = _intOf(row['track']);
    final genre = (row['genre'] ?? '').toString().trim();
    return LocalTrackMeta(
      disc: raw >= 1000 ? raw ~/ 1000 : 1,
      track: raw >= 1000 ? raw % 1000 : raw,
      dateAdded: _intOf(row['dateAdded']),
      genre: genre.isEmpty ? null : genre,
    );
  }

  static int _intOf(Object? v) =>
      v is int ? v : int.tryParse((v ?? '').toString()) ?? 0;
}

/// Which folders the on-device library takes music from.
///
/// One rule beats two lists. An include-only list cannot express "everything
/// except the ringtones", and — worse — it silently drops music added later,
/// because a folder that did not exist when the list was made is not on it. An
/// exclude-only list cannot express "just this one folder" without naming
/// every sibling. Both failures are silent, which is the worst kind.
///
/// So: a default for the device, plus per-folder overrides, resolved by taking
/// the nearest rule up the path. A folder with no rule of its own follows its
/// parent, and a folder whose parents have no rule follows the default — which
/// is how a folder created tomorrow gets the behaviour its parent has today.
class FolderRules {
  const FolderRules({
    this.defaultIncluded = true,
    this.overrides = const <String, bool>{},
  });

  /// What a folder does when nothing above it says otherwise. True — take
  /// everything — is the default so a fresh install finds all the music on the
  /// phone without this screen ever being opened.
  final bool defaultIncluded;

  /// Absolute folder path to whether it, and everything under it, is taken.
  /// Only folders that differ from what they would inherit appear here, so the
  /// map stays the shortest description of the choice.
  final Map<String, bool> overrides;

  bool get isDefault => defaultIncluded && overrides.isEmpty;

  /// Whether music in [folder] belongs in the library.
  bool allows(String folder) => _resolve(folder);

  /// What [folder] would be with no rule of its own — what a tick on it would
  /// have to disagree with to be worth storing.
  bool inherited(String folder) => _resolve(_parent(folder));

  bool _resolve(String? from) {
    var p = from;
    while (p != null && p.isNotEmpty) {
      final rule = overrides[p];
      if (rule != null) return rule;
      p = _parent(p);
    }
    return defaultIncluded;
  }

  /// The nearest enclosing directory, or null at the top of a volume.
  ///
  /// Stopping at index 0 rather than returning '/' keeps the walk off a root
  /// that no rule can name: every path here is absolute, so a '/' rule would
  /// be a second way to say [defaultIncluded].
  static String? _parent(String path) {
    final i = path.lastIndexOf('/');
    return i <= 0 ? null : path.substring(0, i);
  }

  /// Set [folder] and everything under it.
  ///
  /// Only this folder's own rule changes. A rule that agrees with what the
  /// folder already inherits is dropped rather than stored, because setting
  /// something to what it already was is not a decision worth recording.
  FolderRules set(String folder, {required bool included}) {
    final next = {...overrides};
    if (included == inherited(folder)) {
      next.remove(folder);
    } else {
      next[folder] = included;
    }
    return FolderRules(defaultIncluded: defaultIncluded, overrides: next);
  }

  /// Change the device-wide default — what folders with nothing above them
  /// follow, including folders that do not exist yet.
  FolderRules withDefault({required bool included}) =>
      FolderRules(defaultIncluded: included, overrides: overrides);

  // Rules are never tidied away for being redundant, and that is deliberate.
  //
  // A rule can be redundant now and load-bearing after one tap somewhere else:
  // "leave this album out" says nothing while the whole device is off, and is
  // the only thing keeping it out the moment its folder is turned back on.
  // Dropping it in between silently resurrects music the user removed, and the
  // resurrection happens far from the tap that caused it.
  //
  // The cost is a rule set that can hold entries changing nothing today. They
  // cannot change an answer — resolution takes the nearest rule, and a
  // redundant one gives what would have been inherited anyway — and there are
  // only ever as many as the user has touched folders.

  bool sameAs(FolderRules other) {
    if (defaultIncluded != other.defaultIncluded) return false;
    if (overrides.length != other.overrides.length) return false;
    for (final e in overrides.entries) {
      if (other.overrides[e.key] != e.value) return false;
    }
    return true;
  }

  /// Stored as one list of strings so a Hive dump stays readable and a
  /// half-written value degrades to "take everything" rather than to nothing.
  /// Paths are absolute, so they cannot collide with the default marker.
  List<String> encode() => [
    defaultIncluded ? 'default+' : 'default-',
    for (final e in overrides.entries) '${e.value ? '+' : '-'}${e.key}',
  ];

  static FolderRules decode(Iterable<String> raw) {
    var byDefault = true;
    final overrides = <String, bool>{};
    for (final line in raw) {
      if (line == 'default+') {
        byDefault = true;
      } else if (line == 'default-') {
        byDefault = false;
      } else if (line.length > 2 && (line[0] == '+' || line[0] == '-')) {
        overrides[line.substring(1)] = line[0] == '+';
      }
    }
    return FolderRules(defaultIncluded: byDefault, overrides: overrides);
  }
}

/// The last segment of a folder path — what a person calls the folder.
String folderNameOf(String path) {
  final i = path.lastIndexOf('/');
  return i < 0 ? path : path.substring(i + 1);
}

/// The directory part of a file path, or empty when there isn't one.
String folderOf(String path) {
  final i = path.lastIndexOf('/');
  return i <= 0 ? '' : path.substring(0, i);
}

/// The `source` marker carried by every on-device track.
///
/// `StreamResolver` keys its local-file tier off this, and the UI uses it to
/// label provenance. Any change here has to change both.
const String kLocalSource = 'local';

class LocalMediaChannel {
  LocalMediaChannel._();
  static final LocalMediaChannel instance = LocalMediaChannel._();

  /// Called when the device's audio collection changes. The native side
  /// debounces the burst a file copy produces, so this fires once per settled
  /// change rather than once per file.
  void onLibraryChanged(void Function() handler) {
    if (!_supported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'libraryChanged') handler();
    });
  }

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
  /// [rules] decide which folders count — see [FolderRules]. The default takes
  /// the whole device, so a fresh install finds everything without being
  /// configured first.
  ///
  /// Filtering happens here rather than in the query because the folder list
  /// the user picks from has to show every folder on the device, including the
  /// ones currently left out, and a filtered query could not report those.
  Future<LocalScan> scan({FolderRules rules = const FolderRules()}) async {
    if (!_supported) return const LocalScan.empty();
    try {
      final raw = await _channel.invokeListMethod<Object?>('scan');
      if (raw == null) return const LocalScan.empty();
      return _group(raw, rules);
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
  static LocalScan _group(List<Object?> rows, FolderRules rules) {
    final songs = <FeedItem>[];
    final albums = <String, List<FeedItem>>{};
    final albumNames = <String, String>{};
    final albumArtistSets = <String, Set<String>>{};
    final artists = <String, List<FeedItem>>{};
    final artistNames = <String, String>{};
    // Counted over every row, included or not — see LocalScan.folders.
    final folderCounts = <String, int>{};
    final meta = <String, LocalTrackMeta>{};

    for (final row in rows) {
      if (row is! Map) continue;
      final r = row.cast<Object?, Object?>();
      final song = _toFeedItem(r);
      if (song == null) continue;

      final folder = folderOf(song.url ?? '');
      if (folder.isNotEmpty) {
        folderCounts[folder] = (folderCounts[folder] ?? 0) + 1;
      }
      // Left out of the library, but still counted above so the folder can be
      // found and put back.
      if (!rules.allows(folder)) continue;

      songs.add(song);
      meta[song.id] = LocalTrackMeta.fromRow(r);

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
      '${albums.length} albums, ${artists.length} artists, '
      '${folderCounts.length} folders '
      '(${rules.isDefault ? 'all' : '${rules.overrides.length} rule(s), '
                'default ${rules.defaultIncluded ? 'in' : 'out'}'})',
    );
    return LocalScan(
      meta: meta,
      songs: songs,
      albums: [
        for (final e in albums.entries)
          LocalCollection(
            id: e.key,
            name: albumNames[e.key] ?? '',
            subtitle: _albumArtist(albumArtistSets[e.key]),
            // Track order is not a preference inside an album: the scan
            // returns rows newest-file-first, so an album opened from the
            // device library was listing its songs in the order they were
            // copied onto the phone. Applied here so every consumer gets it —
            // the detail screen, Android Auto, "play album".
            songs: sortAlbumTracks(e.value, meta),
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
      folders: _foldersFrom(folderCounts),
    );
  }

  /// Folders sorted by size, largest first: the one worth excluding is
  /// usually the one with three hundred notification tones in it.
  static List<LocalFolder> _foldersFrom(Map<String, int> counts) {
    final out = [
      for (final e in counts.entries)
        LocalFolder(
          path: e.key,
          name: e.key.substring(e.key.lastIndexOf('/') + 1),
          trackCount: e.value,
        ),
    ]..sort((a, b) => b.trackCount.compareTo(a.trackCount));
    return out;
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
