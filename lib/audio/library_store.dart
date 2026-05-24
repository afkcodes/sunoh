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

  /// Max items kept in the played-history list. Older entries get evicted
  /// LRU-style. 50 is enough for "Recently Played" sections without growing
  /// the box unbounded on long sessions.
  static const _maxHistory = 50;

  Future<Box> _box() async {
    if (Hive.isBoxOpen(_boxName)) return Hive.box(_boxName);
    return Hive.openBox(_boxName);
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
    return current;
  }

  Future<void> clearHistory() async {
    final box = await _box();
    await box.put(_kHistory, const []);
  }
}
