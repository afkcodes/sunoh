// Cross-session persistence for the active playback state.
//
// Backed by Hive CE — a 'playback' box holds three keys: 'queue' (List of
// FeedItem JSON maps), 'index' (int), 'position' (int seconds). When the
// library/history slices land they get their own boxes ('library',
// 'history', 'settings') with the same idiom.
//
// What's deliberately NOT saved: per-song mediaUrls. Gaana URLs are signed
// and expire; saavn URLs may drift. The StreamResolver re-resolves on play,
// so persisting stale URLs would just cost bytes.

import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../api/dto.dart';

class SavedPlaybackState {
  const SavedPlaybackState({
    required this.queue,
    required this.currentIndex,
    required this.positionSec,
    this.sourceLabel,
  });
  final List<FeedItem> queue;
  final int currentIndex;
  final int positionSec;
  /// Display label of where playback originated (e.g. "PLAYLIST · Top Charts").
  /// Null for restores from older saves that predate this field.
  final String? sourceLabel;
}

class PlaybackStateStore {
  PlaybackStateStore();

  static const _boxName = 'playback';
  static const _kQueue = 'queue';
  static const _kIndex = 'index';
  static const _kPosition = 'position';
  static const _kSourceLabel = 'sourceLabel';

  Future<Box> _box() async {
    if (Hive.isBoxOpen(_boxName)) return Hive.box(_boxName);
    return Hive.openBox(_boxName);
  }

  Future<void> save({
    required List<FeedItem> queue,
    required int currentIndex,
    required int positionSec,
    String? sourceLabel,
  }) async {
    if (queue.isEmpty) {
      await clear();
      return;
    }
    final box = await _box();
    await box.putAll({
      _kQueue: queue.map((s) => s.toJson()).toList(),
      _kIndex: currentIndex,
      _kPosition: positionSec,
      _kSourceLabel: sourceLabel,
    });
    debugPrint('[playback-store] saved queue=${queue.length} '
        'idx=$currentIndex pos=${positionSec}s src=$sourceLabel');
  }

  Future<SavedPlaybackState?> load() async {
    try {
      final box = await _box();
      final queueRaw = box.get(_kQueue);
      if (queueRaw is! List || queueRaw.isEmpty) return null;
      final queue = queueRaw
          .whereType<Map>()
          .map((m) => FeedItem.fromJson(m.cast<String, dynamic>()))
          .toList();
      if (queue.isEmpty) return null;
      final idx = (box.get(_kIndex) as num?)?.toInt() ?? 0;
      final pos = (box.get(_kPosition) as num?)?.toInt() ?? 0;
      final src = box.get(_kSourceLabel) as String?;
      debugPrint('[playback-store] loaded queue=${queue.length} '
          'idx=$idx pos=${pos}s');
      return SavedPlaybackState(
        queue: queue,
        currentIndex: idx.clamp(0, queue.length - 1),
        positionSec: pos,
        sourceLabel: src,
      );
    } catch (e) {
      debugPrint('[playback-store] load failed: $e');
      return null;
    }
  }

  Future<void> clear() async {
    final box = await _box();
    await box.clear();
  }

  /// Lightweight update — used for position ticks. Only writes the position
  /// (no queue serialization). Cheap enough to call every N seconds.
  Future<void> updatePosition(int positionSec) async {
    if (!Hive.isBoxOpen(_boxName)) return;
    final box = Hive.box(_boxName);
    if (box.get(_kQueue) == null) return; // nothing saved → no-op
    await box.put(_kPosition, positionSec);
  }
}
