// Local state for syncing likes to YouTube Music: the "Sunoh Tracks" playlist
// id and the queue of like/unlike operations not yet delivered.
//
// Its own Hive box rather than keys in `settings`: the queue is rewritten on
// every like, and sharing a box with the settings blob would make each
// heart-tap rewrite-and-flush the user's whole preferences file.
//
// Keys are namespaced `ytsync.*` like every other concern's.

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';

/// One undelivered operation. Only the desired end state matters, so there is
/// no timestamp and no attempt count: retries are bounded per pump run, not
/// per op, so a like made on a plane is never aged out of the queue.
class YtLikeOp {
  const YtLikeOp(this.videoId, this.like);
  final String videoId;
  final bool like;

  Map<String, Object> toMap() => {'v': videoId, 'l': like};

  static YtLikeOp? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final v = raw['v'];
    final l = raw['l'];
    if (v is! String || v.isEmpty || l is! bool) return null;
    return YtLikeOp(v, l);
  }
}

class YtLikeStore {
  YtLikeStore({this.boxName = 'ytsync'});
  final String boxName;

  static const _kPlaylistId = 'ytsync.playlist_id';
  static const _kOps = 'ytsync.ops';

  /// Ceiling on queued ops. A user who is offline for months and likes
  /// hundreds of tracks should not grow a box without bound; the oldest are
  /// dropped, and they stay liked in the app regardless.
  static const int maxOps = 300;

  Future<Box>? _open;
  Future<Box> _box() => _open ??= Hive.openBox(boxName);

  Future<String?> loadPlaylistId() async {
    final v = (await _box()).get(_kPlaylistId);
    return v is String && v.isNotEmpty ? v : null;
  }

  Future<void> savePlaylistId(String? id) async {
    final box = await _box();
    if (id == null) {
      await box.delete(_kPlaylistId);
    } else {
      await box.put(_kPlaylistId, id);
    }
    // Flush for the reason settings_store gives: a fast process kill drops
    // buffered writes, and a lost playlist id means a duplicate lookup.
    await box.flush();
  }

  Future<List<YtLikeOp>> loadOps() async {
    try {
      final raw = (await _box()).get(_kOps);
      if (raw is! List) return [];
      return [for (final r in raw) ?YtLikeOp.fromMap(r)];
    } catch (e) {
      debugPrint('[ytsync] queue unreadable, starting empty: $e');
      return [];
    }
  }

  Future<void> saveOps(List<YtLikeOp> ops) async {
    final box = await _box();
    final kept = ops.length > maxOps ? ops.sublist(ops.length - maxOps) : ops;
    await box.put(_kOps, [for (final o in kept) o.toMap()]);
    await box.flush();
  }
}
