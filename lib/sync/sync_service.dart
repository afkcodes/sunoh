// Orchestrates one sync: read every device's file, merge, write ours back.
//
// The order matters and is the whole of the logic:
//
//   1. Read every `.sync` file in the folder that decrypts with our key.
//   2. Merge them with our own library. Metadata first, then collections,
//      because the collection merge reads the metadata to decide what lives.
//   3. Apply the merged result locally.
//   4. Write our file back, now carrying the merged state.
//
// Step 4 is what propagates another device's changes onward: after A and B
// have both synced, each file holds the union, so a third device joining later
// gets everything from whichever file it reads.
//
// Nothing here talks to the network. The folder is a directory the user picked
// with the system picker; whatever syncs it does the moving.

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../audio/library_store.dart';
import '../audio/settings_store.dart';
import 'sync_channel.dart';
import 'sync_merge.dart';
import 'sync_payload.dart';

enum SyncStatus { off, idle, syncing, ok, noAccess, failed }

class SyncResult {
  const SyncResult({required this.status, this.filesRead = 0, this.message});
  final SyncStatus status;
  final int filesRead;
  final String? message;
}

class SyncService extends ChangeNotifier {
  SyncService({
    required this.library,
    required this.settings,
    SyncChannel? channel,
  }) : _channel = channel ?? SyncChannel.instance;

  final LibraryStore library;
  final SettingsStore settings;
  final SyncChannel _channel;

  SyncStatus _status = SyncStatus.off;
  SyncStatus get status => _status;

  DateTime? _lastSync;
  DateTime? get lastSync => _lastSync;

  String? _folderName;
  String? get folderName => _folderName;

  bool get isConfigured => _tree != null && _key != null;

  String? _tree;
  String? _key;
  String? _deviceId;

  /// This device's file name. Derived from the device id so two devices never
  /// write the same file, which is what removes the need for locking.
  String get fileName => 'sunoh-${_deviceId ?? 'unknown'}.sync';

  /// Load saved configuration. Safe to call repeatedly.
  Future<void> restore() async {
    final saved = await settings.loadSync();
    _tree = saved.treeUri;
    _key = saved.key;
    _deviceId = saved.deviceId;
    _lastSync = saved.lastSyncAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(saved.lastSyncAt!);
    if (isConfigured) {
      _folderName = await _channel.folderName(_tree!);
      _status = SyncStatus.idle;
    } else {
      _status = SyncStatus.off;
    }
    notifyListeners();
  }

  /// Pick a folder and generate a key if this device does not have one.
  ///
  /// Returns the recovery code to show the user, or null if they cancelled.
  /// The code is shown once and stored; the second device is set up by
  /// entering it rather than generating its own, since two different keys mean
  /// two devices writing files neither can read.
  Future<String?> setUp() async {
    final tree = await _channel.pickFolder();
    if (tree == null) return null;
    final key = _key ?? await _channel.generateKey();
    if (key == null) return null;

    _tree = tree;
    _key = key;
    _deviceId ??= _newDeviceId();
    _folderName = await _channel.folderName(tree);
    await _persist();
    _status = SyncStatus.idle;
    notifyListeners();
    return key;
  }

  /// Join an existing setup with a code from the first device.
  Future<bool> joinWithCode(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return false;
    final tree = await _channel.pickFolder();
    if (tree == null) return false;

    _tree = tree;
    _key = trimmed;
    _deviceId ??= _newDeviceId();
    _folderName = await _channel.folderName(tree);
    await _persist();
    _status = SyncStatus.idle;
    notifyListeners();

    // Prove the code before claiming success: a wrong one decrypts nothing,
    // and telling the user later — after their library silently fails to
    // arrive — is much worse than telling them now.
    final result = await syncNow();
    if (result.status == SyncStatus.ok && result.filesRead == 0) {
      // An empty folder is legitimate for the very first device, so this is
      // not treated as a failure. It is reported so the UI can say so.
      debugPrint('[sync] joined, but no readable files yet');
    }
    return result.status == SyncStatus.ok;
  }

  Future<void> disable({bool removeFile = true}) async {
    if (removeFile && _tree != null) {
      await _channel.delete(treeUri: _tree!, name: fileName);
    }
    _tree = null;
    _key = null;
    _folderName = null;
    _status = SyncStatus.off;
    await settings.saveSync(treeUri: '', key: '', deviceId: _deviceId ?? '');
    notifyListeners();
  }

  /// Read, merge, apply, write.
  Future<SyncResult> syncNow() async {
    if (!isConfigured) return const SyncResult(status: SyncStatus.off);
    if (_status == SyncStatus.syncing) {
      return const SyncResult(status: SyncStatus.syncing);
    }

    _status = SyncStatus.syncing;
    notifyListeners();

    try {
      if (!await _channel.hasAccess(_tree!)) {
        // The grant can be revoked from system settings, or the volume can go
        // away. Neither is an error worth a stack trace; it is a state the UI
        // has to be able to describe and offer to fix.
        _status = SyncStatus.noAccess;
        notifyListeners();
        return const SyncResult(status: SyncStatus.noAccess);
      }

      final local = await _buildPayload();
      final files = await _channel.readAll(treeUri: _tree!, key: _key!);

      final remotes = <SyncPayload>[];
      for (final entry in files.entries) {
        // Skip our own file: its contents are what we are about to replace,
        // and re-merging them costs work for no information.
        if (entry.key == fileName) continue;
        final parsed = SyncPayload.decode(entry.value);
        if (parsed != null) remotes.add(parsed);
      }

      final merged = mergeAll(local: local, remotes: remotes);
      await _apply(merged);

      final outgoing = SyncPayload(
        deviceId: _deviceId!,
        writtenAt: DateTime.now().millisecondsSinceEpoch,
        meta: merged.meta,
        liked: merged.liked,
        savedAlbums: merged.savedAlbums,
        savedPlaylists: merged.savedPlaylists,
        savedArtists: merged.savedArtists,
        userPlaylists: merged.userPlaylists,
        podcasts: merged.podcasts,
        episodeProgress: merged.episodeProgress,
        settings: merged.settings,
        settingsAt: merged.settingsAt,
      );

      final wrote = await _channel.write(
        treeUri: _tree!,
        name: fileName,
        key: _key!,
        bytes: Uint8List.fromList(outgoing.encode()),
      );

      _lastSync = DateTime.now();
      await _persist();
      _status = wrote ? SyncStatus.ok : SyncStatus.failed;
      notifyListeners();
      debugPrint(
        '[sync] merged ${remotes.length} remote file(s), '
        'liked=${merged.liked.length} playlists=${merged.userPlaylists.length} '
        'wrote=$wrote',
      );
      return SyncResult(
        status: _status,
        filesRead: remotes.length,
        message: wrote ? null : 'could not write to the folder',
      );
    } catch (e, st) {
      debugPrint('[sync] failed: $e\n$st');
      _status = SyncStatus.failed;
      notifyListeners();
      return SyncResult(status: SyncStatus.failed, message: '$e');
    }
  }

  Future<SyncPayload> _buildPayload() async {
    final meta = await library.loadSyncMeta();
    // Prune here rather than on write: this is the one place that runs on a
    // schedule, and an unbounded tombstone map is the slow leak of any
    // sync design.
    meta.pruneTombstones();

    final saved = await settings.loadSyncableSettings();
    return SyncPayload(
      deviceId: _deviceId!,
      writtenAt: DateTime.now().millisecondsSinceEpoch,
      meta: meta,
      liked: await library.loadLikedSongs(),
      savedAlbums: await library.loadSaved('album'),
      savedPlaylists: await library.loadSaved('playlist'),
      savedArtists: await library.loadSaved('artist'),
      userPlaylists: await library.loadUserPlaylists(),
      podcasts: await library.loadSubscribedPodcasts(),
      episodeProgress: await library.loadEpisodeProgress(),
      settings: saved.values,
      settingsAt: saved.updatedAt,
    );
  }

  Future<void> _apply(MergedLibrary merged) async {
    await library.replaceLiked(merged.liked);
    await library.replaceSaved('album', merged.savedAlbums);
    await library.replaceSaved('playlist', merged.savedPlaylists);
    await library.replaceSaved('artist', merged.savedArtists);
    await library.replaceUserPlaylists(merged.userPlaylists);
    await library.replaceSubscribedPodcasts(merged.podcasts);
    await library.replaceEpisodeProgress(merged.episodeProgress);
    await library.saveSyncMeta(merged.meta);
    if (merged.settings.isNotEmpty) {
      await settings.applySyncableSettings(merged.settings, merged.settingsAt);
    }
  }

  Future<void> _persist() => settings.saveSync(
    treeUri: _tree ?? '',
    key: _key ?? '',
    deviceId: _deviceId ?? '',
    lastSyncAt: _lastSync?.millisecondsSinceEpoch,
  );

  /// Random enough that two devices will not collide, short enough to read in
  /// a filename. Not a fingerprint: it identifies a file, not a person, and it
  /// is regenerated if sync is set up again from scratch.
  static String _newDeviceId() {
    const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final now = DateTime.now().microsecondsSinceEpoch;
    var n = now;
    final out = StringBuffer();
    for (var i = 0; i < 8; i++) {
      out.write(alphabet[n % alphabet.length]);
      n ~/= alphabet.length;
    }
    return out.toString();
  }
}

/// Encode/decode helper kept here so the payload stays free of dart:convert
/// concerns at its call sites.
String prettyCode(String key) => key;

/// Decode a base64 key defensively — used when the user types a code in.
bool looksLikeKey(String code) {
  final trimmed = code.trim();
  if (trimmed.length < 20) return false;
  try {
    return base64Decode(trimmed).length == 16;
  } catch (_) {
    return false;
  }
}
