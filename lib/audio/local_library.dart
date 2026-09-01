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

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../api/dto.dart';
import '../api/local_media_channel.dart';
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

  /// Every on-device track, newest first.
  List<FeedItem> get songs => _scan.songs;
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
    _scan = await _channel.scan(rules: _rules);
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
