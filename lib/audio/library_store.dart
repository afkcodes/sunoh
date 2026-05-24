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

import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../api/dto.dart';

class LibraryStore {
  LibraryStore();

  static const _boxName = 'library';
  static const _kLikedSongs = 'liked_songs';
  static const _kHistory = 'history';
  static const _kSavedAlbums = 'saved_albums';
  static const _kSavedPlaylists = 'saved_playlists';
  static const _kSavedArtists = 'saved_artists';

  /// Max items kept in the played-history list. Older entries get evicted
  /// LRU-style. 50 is enough for "Recently Played" sections without growing
  /// the box unbounded on long sessions.
  static const _maxHistory = 50;

  Future<Box> _box() async {
    if (Hive.isBoxOpen(_boxName)) return Hive.box(_boxName);
    final box = await Hive.openBox(_boxName);
    // Diagnostic — surfaces the box path + lengths in logcat each cold
    // start. If a user reports "library wiped after install", check that
    // these numbers stay non-zero across runs. If they reset to 0 after
    // an install, the install path wiped the data directory (signing-
    // cert change, `adb uninstall`, or a manual Settings → Clear data).
    debugPrint(
        '[library-store] opened "$_boxName" at ${box.path} — '
        'liked=${(box.get(_kLikedSongs) as List?)?.length ?? 0} '
        'history=${(box.get(_kHistory) as List?)?.length ?? 0} '
        'albums=${(box.get(_kSavedAlbums) as List?)?.length ?? 0} '
        'playlists=${(box.get(_kSavedPlaylists) as List?)?.length ?? 0} '
        'artists=${(box.get(_kSavedArtists) as List?)?.length ?? 0}');
    return box;
  }

  List<FeedItem> _decodeList(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => FeedItem.fromJson(m.cast<String, dynamic>()))
        .toList();
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
}
