// The on-device music library: permission, scan, and the state the browse
// screens read.
//
// MediaStore is the source of truth, so nothing here is persisted. A scan is
// cheap enough to run on demand, and stale data is worse than a short wait —
// a track deleted on the phone should disappear from the app rather than
// linger as a row that fails to play.
//
// Grouping into albums and artists happens in `LocalMediaChannel`, where the
// raw MediaStore columns are still separate; this class only holds the result
// and owns the permission dance.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../api/dto.dart';
import '../api/local_media_channel.dart';
import '../api/local_sort.dart';
import 'settings_store.dart';

/// Why the local library is empty, when it is.
enum LocalLibraryStatus {
  /// Never scanned in this session.
  idle,
  scanning,

  /// Scanned successfully. [LocalLibrary.songs] may still be empty if the
  /// device genuinely has no music — a distinction the UI has to make, since
  /// the remedy differs.
  ready,

  /// Audio access refused. Recoverable by asking again.
  denied,

  /// Refused with "don't ask again". Only Settings can undo this, so the UI
  /// has to offer that rather than a retry that can never succeed.
  permanentlyDenied,
}

class LocalLibrary extends ChangeNotifier {
  LocalLibrary({LocalMediaChannel? channel, SettingsStore? settings})
    : _channel = channel ?? LocalMediaChannel.instance,
      _settings = settings ?? SettingsStore();

  final LocalMediaChannel _channel;
  final SettingsStore _settings;

  FolderRules _rules = const FolderRules();

  LocalSort _sort = LocalSort.dateAdded;
  bool _sortAscending = false;

  /// How the songs list is ordered. Albums and artists are unaffected —
  /// inside an album, track order wins regardless (see [sortAlbumTracks]).
  LocalSort get sort => _sort;
  bool get sortAscending => _sortAscending;

  /// Which folders the library takes music from.
  FolderRules get folderRules => _rules;

  /// Every folder holding music, including ones left out, largest first.
  List<LocalFolder> get folders => _scan.folders;

  /// Replace the folder rules, then rescan.
  ///
  /// Takes the whole rule set rather than one folder at a time because the
  /// screen applies a selection: changing six folders one call at a time would
  /// mean six rescans, five of them showing a library nobody asked to see.
  ///
  /// A rescan rather than filtering in memory: the album and artist groupings
  /// are built from the raw MediaStore rows, where album and artist are still
  /// separate columns, and rebuilding them from already-mapped items would
  /// mean parsing a display string back apart. The scan is cheap on a warm
  /// album-art cache.
  /// Change the order. No rescan: [songs] sorts what is already in memory.
  /// Rescan when music is added to or removed from the phone.
  ///
  /// Only while there is already a library loaded: a change notification is
  /// not a reason to ask for storage permission, and scanning before the user
  /// has opened the library once would be work nobody asked for.
  void watchDevice() {
    _channel.onLibraryChanged(() {
      if (_scan.songs.isEmpty && _status != LocalLibraryStatus.ready) return;
      debugPrint('[local] device library changed — rescanning');
      unawaited(load(force: true));
    });
  }

  Future<void> setSort(LocalSort sort, {required bool ascending}) async {
    if (_sort == sort && _sortAscending == ascending) return;
    _sort = sort;
    _sortAscending = ascending;
    notifyListeners();
    await _settings.saveLocalSort(sort.key, ascending: ascending);
  }

  Future<void> setFolderRules(FolderRules rules) async {
    if (rules.sameAs(_rules)) return;
    _rules = rules;
    await _settings.saveFolderRules(rules);
    notifyListeners();
    await load(force: true);
  }

  LocalLibraryStatus _status = LocalLibraryStatus.idle;
  LocalLibraryStatus get status => _status;

  LocalScan _scan = const LocalScan.empty();

  /// Genre and folder groupings, built once per scan.
  ///
  /// Derived rather than scanned: both are a regroup of songs we already have,
  /// and doing it on every read would put an O(n) walk inside `build`.
  List<LocalCollection> _genres = const [];
  List<LocalCollection> _folderGroups = const [];

  /// Songs grouped by tag genre. Empty below Android 11, where MediaStore has
  /// no GENRE column at all — the tab hides itself rather than showing one
  /// bogus "Unknown" bucket holding the entire library.
  List<LocalCollection> get genres => _genres;

  /// Songs grouped by the folder they sit in — the way a library organised on
  /// disk rather than by tags is actually navigated.
  List<LocalCollection> get folderGroups => _folderGroups;

  void _regroup() {
    final byGenre = <String, List<FeedItem>>{};
    final byFolder = <String, List<FeedItem>>{};
    for (final song in _scan.songs) {
      final genre = _scan.meta[song.id]?.genre;
      if (genre != null && genre.isNotEmpty) {
        (byGenre[genre] ??= []).add(song);
      }
      final folder = folderOf(song.url ?? '');
      if (folder.isNotEmpty) (byFolder[folder] ??= []).add(song);
    }
    _genres = [
      for (final e in byGenre.entries)
        LocalCollection(
          id: e.key,
          name: e.key,
          subtitle: '${e.value.length} songs',
          songs: e.value,
        ),
    ]..sort((a, b) => b.songs.length.compareTo(a.songs.length));
    _folderGroups = [
      for (final e in byFolder.entries)
        LocalCollection(
          id: e.key,
          name: folderNameOf(e.key),
          subtitle: folderLocation(e.key),
          songs: e.value,
        ),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  /// Every on-device track, newest first.
  /// Sorted on read rather than at scan time: changing the order should not
  /// cost a MediaStore query, and the scan's own order is the raw material
  /// every ordering is derived from.
  List<FeedItem> get songs => sortLocalSongs(
    _scan.songs,
    _scan.meta,
    by: _sort,
    ascending: _sortAscending,
  );

  /// Unsorted, in scan order. For anything that wants "most recently added"
  /// without inheriting whatever the user picked.
  List<FeedItem> get songsByDateAdded => _scan.songs;
  List<LocalCollection> get albums => _scan.albums;
  List<LocalCollection> get artists => _scan.artists;

  bool get hasMusic => _scan.songs.isNotEmpty;
  bool get isScanning => _status == LocalLibraryStatus.scanning;

  /// Scan only if access has already been granted.
  ///
  /// This is what runs when the Library tab renders its device row. It must
  /// never raise the permission dialog: the user opened Library, not the
  /// device library, and a system prompt with no action behind it is the
  /// fastest way to get permanently denied. Once granted, though, the count
  /// should just be there.
  Future<void> loadIfPermitted() async {
    try {
      if (!await Permission.audio.status.isGranted) return;
    } catch (_) {
      return;
    }
    await _scanNow();
  }

  /// Request access if needed, then scan.
  ///
  /// Called when the user actually opens the device library — the point at
  /// which asking for permission is something they have asked for.
  Future<void> load({bool force = false}) async {
    if (_status == LocalLibraryStatus.scanning) return;
    if (!force && _status == LocalLibraryStatus.ready) return;
    if (!await _ensurePermission()) return;
    await _scanNow();
  }

  Future<void> _scanNow() async {
    if (_status == LocalLibraryStatus.scanning) return;
    _set(LocalLibraryStatus.scanning);
    _rules = await _settings.loadFolderRules();
    final (sortKey, asc) = await _settings.loadLocalSort();
    _sort = LocalSortLabel.fromKey(sortKey);
    _sortAscending = asc;
    _scan = await _channel.scan(rules: _rules);
    _regroup();
    _set(LocalLibraryStatus.ready);
  }

  /// Ask for audio access, mapping the outcome onto [LocalLibraryStatus].
  ///
  /// Android split this permission at 13: `READ_MEDIA_AUDIO` from 33 up,
  /// `READ_EXTERNAL_STORAGE` below. `permission_handler`'s `Permission.audio`
  /// resolves to whichever applies, so the split stays out of the app.
  Future<bool> _ensurePermission() async {
    try {
      var status = await Permission.audio.status;
      if (status.isGranted) return true;
      if (status.isPermanentlyDenied) {
        _set(LocalLibraryStatus.permanentlyDenied);
        return false;
      }
      status = await Permission.audio.request();
      if (status.isGranted) return true;
      _set(
        status.isPermanentlyDenied
            ? LocalLibraryStatus.permanentlyDenied
            : LocalLibraryStatus.denied,
      );
      return false;
    } catch (e) {
      debugPrint('[local] permission check failed: $e');
      _set(LocalLibraryStatus.denied);
      return false;
    }
  }

  /// Open the OS settings page, for the permanently-denied case where no
  /// in-app prompt can help.
  Future<void> openSettings() => openAppSettings();

  /// Tracks of one album or artist, by the id its [LocalCollection] carries.
  List<FeedItem> songsIn(String collectionId, {required bool album}) {
    for (final c in album ? _scan.albums : _scan.artists) {
      if (c.id == collectionId) return c.songs;
    }
    return const [];
  }

  /// Tracks whose title, artist or album matches [query]. Feeds the local
  /// section of the Search screen.
  List<FeedItem> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return [
      for (final s in _scan.songs)
        if (s.title.toLowerCase().contains(q) ||
            (s.subtitle ?? '').toLowerCase().contains(q))
          s,
    ];
  }

  void _set(LocalLibraryStatus status) {
    _status = status;
    notifyListeners();
  }
}
