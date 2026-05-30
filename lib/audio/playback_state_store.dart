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

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../api/dto.dart';
import '../audio/audio_handler.dart' show PlayMode;
import '../data/models.dart';

class SavedPlaybackState {
  const SavedPlaybackState({
    required this.queue,
    required this.currentIndex,
    required this.positionSec,
    this.sourceLabel,
    this.sourceRef,
    this.playMode = PlayMode.track,
  });
  final List<FeedItem> queue;
  final int currentIndex;
  final int positionSec;
  /// Display label of where playback originated (e.g. "PLAYLIST · Top Charts").
  /// Null for restores from older saves that predate this field.
  final String? sourceLabel;
  /// DetailRef of the album/playlist this queue was started from. Lets the
  /// player's track-menu sheet surface a "Go to Album/Playlist" row after
  /// restore. Null for restores from older saves OR for queues started
  /// outside a detail screen (search, radio).
  final DetailRef? sourceRef;
  /// Track-mode vs live-stream — restored verbatim so a radio queue
  /// re-opens with PlayMode.live (single-entry, no auto-advance,
  /// EOF-→-refresh semantics). Default `track` for backwards-compat
  /// with saves that predate this field.
  final PlayMode playMode;
}

class PlaybackStateStore {
  PlaybackStateStore();

  static const _boxName = 'playback';
  static const _kQueue = 'queue';
  static const _kIndex = 'index';
  static const _kPosition = 'position';
  static const _kSourceLabel = 'sourceLabel';
  // Three keys so the DetailRef can be reconstructed on restore. Kept as
  // discrete keys (not a nested map) for backwards-compat with saves that
  // predate sourceRef — missing keys just yield null.
  static const _kSourceRefKind = 'sourceRefKind';
  static const _kSourceRefId = 'sourceRefId';
  static const _kSourceRefProvider = 'sourceRefProvider';
  // PlayMode persisted as enum name ('track' / 'live'). Stored separately
  // so we don't have to bump a schema version when a new mode is added.
  static const _kPlayMode = 'playMode';

  Future<Box> _box() async {
    if (Hive.isBoxOpen(_boxName)) return Hive.box(_boxName);
    Box box;
    try {
      box = await Hive.openBox(_boxName);
    } catch (e, st) {
      // ignore: avoid_print
      print('[playback-store] ⚠ openBox("$_boxName") FAILED: $e\n$st\n'
          '[playback-store] deleting corrupted box file and retrying…');
      try {
        await Hive.deleteBoxFromDisk(_boxName);
      } catch (_) {}
      box = await Hive.openBox(_boxName);
    }
    // Best-effort on-disk size probe (release builds aren't debuggable,
    // so `adb shell run-as` is blocked — log it from inside the app).
    int boxBytes = -1;
    try {
      final p = box.path;
      if (p != null) {
        final f = File(p);
        if (await f.exists()) boxBytes = await f.length();
      }
    } catch (_) {}
    final queue = box.get(_kQueue);
    // `print` (not debugPrint) so survives release. Pairs with the
    // library-store cold-start log: same dir, same Hive.openBox pattern.
    // ignore: avoid_print
    print('[playback-store] opened "$_boxName" at ${box.path} '
        '(file=${boxBytes}b) — '
        'queue=${(queue is List) ? queue.length : 0} '
        'idx=${box.get(_kIndex) ?? '-'} '
        'pos=${box.get(_kPosition) ?? '-'}s');
    return box;
  }

  Future<void> save({
    required List<FeedItem> queue,
    required int currentIndex,
    required int positionSec,
    String? sourceLabel,
    DetailRef? sourceRef,
    PlayMode playMode = PlayMode.track,
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
      _kSourceRefKind: sourceRef?.kind,
      _kSourceRefId: sourceRef?.id,
      _kSourceRefProvider: sourceRef?.source,
      _kPlayMode: playMode.name,
    });
    // Force fsync — same reason as library_store / settings_store: without
    // flush, Hive buffers in memory and a process-kill mid-write drops
    // the update. (Earlier comment here claimed position survived because
    // we write every 5 s — wrong. `updatePosition` also wasn't flushing,
    // so cold-kill restore landed on the last full save's position. Both
    // call sites now flush.)
    await box.flush();
    debugPrint('[playback-store] saved queue=${queue.length} '
        'idx=$currentIndex pos=${positionSec}s src=$sourceLabel '
        'ref=${sourceRef == null ? '-' : '${sourceRef.kind}:${sourceRef.id}'}');
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
      final refKind = box.get(_kSourceRefKind) as String?;
      final refId = box.get(_kSourceRefId) as String?;
      final refProvider = box.get(_kSourceRefProvider) as String?;
      final ref = (refKind != null && refId != null && refId.isNotEmpty)
          ? DetailRef(refKind, refId, source: refProvider)
          : null;
      // playMode: parse the persisted enum name back; default to track
      // for saves that predate this field. A second-line guard infers
      // 'live' from a single radio-station queue entry — covers saves
      // that were written between v1.7.0 (PlayMode.live shipped) and
      // this fix (where it wasn't yet persisted).
      final modeRaw = box.get(_kPlayMode) as String?;
      PlayMode playMode = PlayMode.values.firstWhere(
        (m) => m.name == modeRaw,
        orElse: () =>
            (queue.length == 1 && queue.first.type == 'radio_station')
                ? PlayMode.live
                : PlayMode.track,
      );
      debugPrint('[playback-store] loaded queue=${queue.length} '
          'idx=$idx pos=${pos}s mode=$playMode '
          'ref=${ref == null ? '-' : '${ref.kind}:${ref.id}'}');
      return SavedPlaybackState(
        queue: queue,
        currentIndex: idx.clamp(0, queue.length - 1),
        positionSec: pos,
        sourceLabel: src,
        sourceRef: ref,
        playMode: playMode,
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
  ///
  /// `flush()` is required — without it Hive only writes to its in-memory
  /// buffer and the OS may not flush the underlying file before a hard
  /// kill (force-close from recents). The result: cold-launch restore
  /// would land on the last position written by `save()` (which only
  /// fires on track / queue / source changes), not the most recent tick.
  /// On flash storage even 12 flushes / minute is well within the
  /// device's wear budget.
  Future<void> updatePosition(int positionSec) async {
    if (!Hive.isBoxOpen(_boxName)) return;
    final box = Hive.box(_boxName);
    if (box.get(_kQueue) == null) return; // nothing saved → no-op
    await box.put(_kPosition, positionSec);
    await box.flush();
  }
}
