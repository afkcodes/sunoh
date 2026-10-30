// Mirrors in-app likes of YouTube tracks onto the user's YouTube Music
// account: a real like, plus membership of a private "Sunoh Tracks" playlist.
//
// Local-first. The in-app like has already happened by the time [enqueue] is
// called and never waits on anything here. Delivery is a persisted queue
// drained by one worker at a time, so:
//
//   - a like made offline syncs on the next launch / next like / next sign-in;
//   - two quick taps cannot race two requests for the same track;
//   - signed out, nothing is queued and nothing is shown. Syncing is an
//     enhancement, never a failure mode.
//
// Only YouTube-sourced songs come through. Saavn and Gaana tracks have no
// YouTube video id and cannot be rated or added to a playlist; the caller
// filters them out.

import 'package:flutter/foundation.dart';

import '../api/ytmusic_api.dart';
import 'yt_like_store.dart';

const kSunohPlaylistTitle = 'Sunoh Tracks';
const _kPlaylistDescription = 'Tracks liked in Sunoh';

class YtLikeSync {
  YtLikeSync({
    required this.store,
    required this.remote,
    required this.isSignedIn,
    this.onFirstLikeSynced,
    this.retries = 3,
    this.backoff = const Duration(seconds: 2),
  });

  final YtLikeStore store;

  /// Resolved per use: the API client is rebuilt when the locale changes.
  final YtLikeRemote Function() remote;
  final bool Function() isSignedIn;

  /// Fired once per session, after the first like lands on YouTube.
  final VoidCallback? onFirstLikeSynced;

  /// Attempts per op in one drain before the drain gives up and leaves the
  /// rest queued for the next trigger.
  final int retries;
  final Duration backoff;

  List<YtLikeOp>? _ops;
  bool _draining = false;
  bool _announced = false;
  String? _playlistId;
  bool _playlistLoaded = false;

  /// Record the user's decision and deliver it. Callers fire-and-forget: the
  /// returned future completes when the queue has drained or given up.
  Future<void> enqueue(String videoId, {required bool like}) async {
    if (!isSignedIn()) return;
    final ops = await _load();
    // An op still waiting (not the one in flight, which is ops.first while
    // draining) is superseded by a later decision on the same track. An
    // opposite pair cancels outright: like then unlike before delivery is a
    // net no-op, and sending both would only risk disagreeing with YouTube.
    final start = _draining ? 1 : 0;
    final i = ops.indexWhere((o) => o.videoId == videoId, start);
    if (i >= 0) {
      final same = ops[i].like == like;
      if (!same) ops.removeAt(i);
      if (same) return;
    } else {
      ops.add(YtLikeOp(videoId, like));
    }
    await store.saveOps(ops);
    await drain();
  }

  /// Deliver whatever is queued. Safe to call any time; a no-op when signed
  /// out, empty, or already running.
  Future<void> drain() async {
    if (_draining || !isSignedIn()) return;
    _draining = true;
    try {
      final ops = await _load();
      while (ops.isNotEmpty && isSignedIn()) {
        final done = await _deliver(ops.first);
        if (!done) return; // leave it queued; the next trigger retries
        ops.removeAt(0);
        await store.saveOps(ops);
      }
    } finally {
      _draining = false;
    }
  }

  Future<List<YtLikeOp>> _load() async => _ops ??= await store.loadOps();

  /// True when the op is finished (delivered, or hopeless and dropped).
  Future<bool> _deliver(YtLikeOp op) async {
    for (var attempt = 0; attempt < retries; attempt++) {
      try {
        await _apply(op);
        return true;
      } on _Refused {
        debugPrint('[ytsync] ${idPrefix(op.videoId)} refused, dropping');
        return true;
      } catch (e) {
        debugPrint('[ytsync] ${idPrefix(op.videoId)} failed: ${e.runtimeType}');
        if (attempt + 1 < retries) {
          await Future<void>.delayed(backoff * (1 << attempt));
        }
      }
    }
    return false;
  }

  Future<void> _apply(YtLikeOp op) async {
    final api = remote();
    if (!await api.rate(op.videoId, like: op.like)) throw const _Refused();
    if (op.like && !_announced) {
      _announced = true;
      onFirstLikeSynced?.call();
    }
    // The playlist is best-effort next to the like itself: a refusal here must
    // not undo or block the rating that already succeeded.
    try {
      await _syncPlaylist(api, op);
    } on YtPlaylistGone {
      // Deleted on YouTube since we stored its id: forget and redo once.
      await _setPlaylistId(null);
      await _syncPlaylist(api, op);
    }
  }

  Future<void> _syncPlaylist(YtLikeRemote api, YtLikeOp op) async {
    final id = await _ensurePlaylist(api, create: op.like);
    if (id == null) return;
    final entries = await api.entries(id);
    if (entries == null) throw const YtPlaylistGone();
    final setId = entries[op.videoId];
    if (op.like) {
      if (setId == null) await api.addVideo(id, op.videoId);
    } else if (setId != null) {
      await api.removeVideo(id, op.videoId, setId);
    }
  }

  /// Stored id, else an existing "Sunoh Tracks" (so a reinstall does not make
  /// a second one), else a new one. Unliking never creates: there would be
  /// nothing to remove from it.
  Future<String?> _ensurePlaylist(
    YtLikeRemote api, {
    required bool create,
  }) async {
    if (!_playlistLoaded) {
      _playlistId = await store.loadPlaylistId();
      _playlistLoaded = true;
    }
    if (_playlistId != null) return _playlistId;
    var id = await api.findPlaylist(kSunohPlaylistTitle);
    if (id == null && create) {
      id = await api.createPlaylist(kSunohPlaylistTitle, _kPlaylistDescription);
      debugPrint('[ytsync] created $kSunohPlaylistTitle');
    }
    if (id != null) await _setPlaylistId(id);
    return id;
  }

  Future<void> _setPlaylistId(String? id) async {
    _playlistId = id;
    _playlistLoaded = true;
    await store.savePlaylistId(id);
  }
}

class _Refused implements Exception {
  const _Refused();
}
