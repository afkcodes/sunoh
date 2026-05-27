// Library persistence — liked songs + recently-played history.
//
// Backed by a Hive `'library'` box, two keys:
//   - `liked_songs`: List of FeedItem JSON, newest-first (i.e. the most
//     recently liked song is at index 0).
//   - `history`:    List of FeedItem JSON, newest-first, capped at
//     `_maxHistory` entries.
//
// Both are stored as JSON lists rather than HiveObjects so the schema can
// evolve without migrations — `FeedItem.toJson` / `fromJson` already round-
// trip everything the UI needs.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../api/dto.dart';
import '../data/user_playlist.dart';

class LibraryStore {
  LibraryStore();

  static const _boxName = 'library';
  static const _kLikedSongs = 'liked_songs';
  static const _kHistory = 'history';
  static const _kSavedAlbums = 'saved_albums';
  static const _kSavedPlaylists = 'saved_playlists';
  static const _kSavedArtists = 'saved_artists';
  // User-created playlists (local only). Distinct from `saved_playlists`
  // which holds API-sourced playlists the user has bookmarked.
  static const _kUserPlaylists = 'user_playlists';

  /// Max items kept in the played-history list. Older entries get evicted
  /// LRU-style. 50 is enough for "Recently Played" sections without growing
  /// the box unbounded on long sessions.
  static const _maxHistory = 50;

  /// Cached in-flight open. The first caller to `_box()` kicks the open,
  /// every subsequent caller awaits the same future. Without this the
  /// `Future.wait` over 9 loaders in AppState._restoreLibrary fires 9
  /// concurrent Hive.openBox calls for the same box — even if Hive
  /// internally serializes, the diagnostic noise alone made the log
  /// unreadable, and on some platforms it's a real race risk.
  Future<Box>? _openFuture;

  Future<Box> _box() async {
    if (Hive.isBoxOpen(_boxName)) return Hive.box(_boxName);
    return _openFuture ??= _openOnce();
  }

  Future<Box> _openOnce() async {
    Box box;
    try {
      box = await Hive.openBox(_boxName);
    } catch (e, st) {
      // Corruption recovery — if the .hive file is half-written (rare,
      // but possible if the device was killed mid-flush) Hive throws on
      // open. Without recovery the catch blocks in loadLikedIds /
      // loadLikedSongs / etc. silently return empty, which presents to
      // the user as "library got wiped" even though the playback box at
      // the same path opened fine. Delete the corrupted file + start
      // fresh so subsequent writes get a clean baseline.
      // ignore: avoid_print
      print('[library-store] ⚠ openBox("$_boxName") FAILED: $e\n$st\n'
          '[library-store] deleting corrupted box file and retrying…');
      try {
        await Hive.deleteBoxFromDisk(_boxName);
      } catch (_) {}
      box = await Hive.openBox(_boxName);
    }
    // Best-effort file-size probe alongside the entry counts. Release
    // builds aren't debuggable, so `adb shell run-as` is blocked — having
    // the app log its own on-disk byte counts lets us distinguish
    // "writes never reached disk" (size ≈ 0) from "writes succeeded but
    // read returns empty" (size > 0 with entries=0). Path / lock files
    // are sibling to `box.path`.
    int boxBytes = -1;
    int lockBytes = -1;
    try {
      final p = box.path;
      if (p != null) {
        final f = File(p);
        if (await f.exists()) boxBytes = await f.length();
        final l = File('$p.lock'.replaceAll('.hive.lock', '.lock'));
        if (await l.exists()) lockBytes = await l.length();
      }
    } catch (_) {}

    // `print` (not debugPrint) so this surfaces in release logcat too.
    // ignore: avoid_print
    print('[library-store] opened "$_boxName" at ${box.path} '
        '(file=${boxBytes}b lock=${lockBytes}b) — '
        'liked=${(box.get(_kLikedSongs) as List?)?.length ?? 0} '
        'history=${(box.get(_kHistory) as List?)?.length ?? 0} '
        'albums=${(box.get(_kSavedAlbums) as List?)?.length ?? 0} '
        'playlists=${(box.get(_kSavedPlaylists) as List?)?.length ?? 0} '
        'artists=${(box.get(_kSavedArtists) as List?)?.length ?? 0}');
    return box;
  }

  List<FeedItem> _decodeList(Object? raw) {
    // CRITICAL: must return a *growable, modifiable* list because every
    // mutation path (setLiked / pushHistory / setSaved) does
    // `current.removeWhere(...)` + `current.insert(0, …)` on the result.
    // Returning `const []` here threw `Unsupported operation: Cannot
    // remove from an unmodifiable list` on the very first like attempt
    // (when the key didn't exist yet), which aborted the write before
    // any data hit disk — the UI showed the optimistic update fine but
    // nothing was persisted, so "library got wiped on update" was really
    // "library was never on disk to begin with."
    if (raw is! List) return <FeedItem>[];
    return raw
        .whereType<Map>()
        .map((m) => FeedItem.fromJson(m.cast<String, dynamic>()))
        .toList(); // toList() is growable + modifiable
  }

  List<Map<String, dynamic>> _encodeList(List<FeedItem> items) =>
      items.map((s) => s.toJson()).toList();

  // ── Liked songs ────────────────────────────────────────────────────────

  /// Lightweight read for "is X liked?" checks — only deserialises the ids,
  /// not each full FeedItem.
  Future<Set<String>> loadLikedIds() async {
    try {
      final box = await _box();
      final raw = box.get(_kLikedSongs);
      if (raw is! List) return <String>{};
      return raw
          .whereType<Map>()
          .map((m) => (m['id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet();
    } catch (e) {
      debugPrint('[library-store] loadLikedIds failed: $e');
      return <String>{};
    }
  }

  Future<List<FeedItem>> loadLikedSongs() async {
    try {
      final box = await _box();
      return _decodeList(box.get(_kLikedSongs));
    } catch (e) {
      debugPrint('[library-store] loadLikedSongs failed: $e');
      return const [];
    }
  }

  /// Add `song` to the liked list (newest-first), or remove it if it's
  /// already there. Returns the full updated list for the caller to push
  /// into in-memory state without re-reading from disk.
  Future<List<FeedItem>> setLiked({
    required FeedItem song,
    required bool liked,
  }) async {
    final box = await _box();
    final current = _decodeList(box.get(_kLikedSongs));
    current.removeWhere((s) => s.id == song.id);
    if (liked) current.insert(0, song);
    await box.put(_kLikedSongs, _encodeList(current));
    // Force fsync — Hive buffers writes by default; without flush, a
    // crash or fast subsequent `adb install` can drop the write.
    await box.flush();
    debugPrint('[library-store] liked=${liked ? 'on' : 'off'} ${song.id} '
        '(total=${current.length})');
    return current;
  }

  // ── History ────────────────────────────────────────────────────────────

  Future<List<FeedItem>> loadHistory() async {
    try {
      final box = await _box();
      return _decodeList(box.get(_kHistory));
    } catch (e) {
      debugPrint('[library-store] loadHistory failed: $e');
      return const [];
    }
  }

  /// Push `song` onto the history (newest-first, deduped by id, capped at
  /// [_maxHistory]). Returns the full updated list.
  Future<List<FeedItem>> pushHistory(FeedItem song) async {
    final box = await _box();
    final current = _decodeList(box.get(_kHistory));
    current.removeWhere((s) => s.id == song.id);
    current.insert(0, song);
    if (current.length > _maxHistory) {
      current.removeRange(_maxHistory, current.length);
    }
    await box.put(_kHistory, _encodeList(current));
    await box.flush();
    return current;
  }

  Future<void> clearHistory() async {
    final box = await _box();
    await box.put(_kHistory, const []);
    await box.flush();
  }

  // ── Saved collections (albums / playlists / artists) ──────────────────
  // Same shape as liked_songs but separate keys so the UI can show
  // them in their own buckets (and the user can have a Maroon 5 album
  // saved without that artist being followed, etc.).

  String _keyForKind(String kind) {
    switch (kind) {
      case 'album':
        return _kSavedAlbums;
      case 'playlist':
        return _kSavedPlaylists;
      case 'artist':
        return _kSavedArtists;
      default:
        throw ArgumentError('Unsupported saved kind: $kind');
    }
  }

  /// All saved ids for [kind] (`album` / `playlist` / `artist`). Cheap
  /// — only deserializes the ids.
  Future<Set<String>> loadSavedIds(String kind) async {
    try {
      final box = await _box();
      final raw = box.get(_keyForKind(kind));
      if (raw is! List) return <String>{};
      return raw
          .whereType<Map>()
          .map((m) => (m['id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet();
    } catch (e) {
      debugPrint('[library-store] loadSavedIds($kind) failed: $e');
      return <String>{};
    }
  }

  Future<List<FeedItem>> loadSaved(String kind) async {
    try {
      final box = await _box();
      return _decodeList(box.get(_keyForKind(kind)));
    } catch (e) {
      debugPrint('[library-store] loadSaved($kind) failed: $e');
      return const [];
    }
  }

  /// Toggle saved state for [item]. Returns the updated list (newest-first).
  Future<List<FeedItem>> setSaved({
    required FeedItem item,
    required bool saved,
  }) async {
    final key = _keyForKind(item.type);
    final box = await _box();
    final current = _decodeList(box.get(key));
    current.removeWhere((s) => s.id == item.id);
    if (saved) current.insert(0, item);
    await box.put(key, _encodeList(current));
    await box.flush();
    debugPrint('[library-store] saved=${saved ? 'on' : 'off'} '
        '${item.type}:${item.id} (total=${current.length})');
    return current;
  }

  // ── User-created playlists ────────────────────────────────────────────
  // Persisted as a JSON list keyed on `_kUserPlaylists`, newest-first by
  // `updatedAt` (so the most-recently-edited playlist surfaces first).

  List<UserPlaylist> _decodePlaylists(Object? raw) {
    if (raw is! List) return <UserPlaylist>[];
    return raw
        .whereType<Map>()
        .map((m) => UserPlaylist.fromJson(m.cast<String, dynamic>()))
        .toList();
  }

  List<Map<String, dynamic>> _encodePlaylists(List<UserPlaylist> items) =>
      items.map((p) => p.toJson()).toList();

  Future<List<UserPlaylist>> loadUserPlaylists() async {
    try {
      final box = await _box();
      return _decodePlaylists(box.get(_kUserPlaylists));
    } catch (e) {
      debugPrint('[library-store] loadUserPlaylists failed: $e');
      return const [];
    }
  }

  /// Upsert a single playlist (matched on `id`). Bumps it to the front
  /// of the list (most-recently-modified ordering). Returns the full
  /// updated list.
  Future<List<UserPlaylist>> upsertUserPlaylist(UserPlaylist p) async {
    final box = await _box();
    final current = _decodePlaylists(box.get(_kUserPlaylists));
    current.removeWhere((x) => x.id == p.id);
    current.insert(0, p);
    await box.put(_kUserPlaylists, _encodePlaylists(current));
    await box.flush();
    debugPrint('[library-store] upsert user-playlist "${p.name}" '
        '(songs=${p.songs.length}, total=${current.length})');
    return current;
  }

  Future<List<UserPlaylist>> deleteUserPlaylist(String id) async {
    final box = await _box();
    final current = _decodePlaylists(box.get(_kUserPlaylists));
    current.removeWhere((p) => p.id == id);
    await box.put(_kUserPlaylists, _encodePlaylists(current));
    await box.flush();
    debugPrint('[library-store] deleted user-playlist $id '
        '(total=${current.length})');
    return current;
  }
}
