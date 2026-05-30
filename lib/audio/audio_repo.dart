// AudioRepo — high-level interface UI code uses to drive playback.
//
// Queue management lives in the handler (with lazy URL resolution via the
// mpv on_load hook), so this layer is thin: build the right metadata for
// audio_service announce and forward calls.

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dto.dart';
import '../api/stream_resolver.dart';
import '../data/models.dart';
import '../state/app_state.dart' show LoopMode;
import 'audio_handler.dart';
import 'audio_service_bridge.dart';
import 'library_store.dart';
import 'playback_state_store.dart';
import 'settings_store.dart';

class AudioRepo {
  AudioRepo({
    required this.handler,
    required this.resolver,
    required this.store,
    required this.settings,
    required this.library,
  }) {
    // Always-on track-change listener. Wired in the constructor (NOT in
    // attachBridge) so persistence works even when audio_service init fails
    // — otherwise auto-advance to a new track would never persist the new
    // index, the 5s position-only tick would then overwrite the OLD index's
    // saved position with the NEW track's position, and restore would land
    // on the wrong song at the wrong time.
    handler.currentSongStream.listen((song) {
      if (song == null) return;
      _currentIndex = handler.currentIndex;
      _bridge?.onTrackChanged(_mediaItemFor(song));
      // Skip while restoring — `prepareQueue` emits a currentSong event
      // before mpv has actually loaded the file, so handler.position is
      // 0 even though the SAVED state had a non-zero seek target. Writing
      // back at this moment would clobber the saved position with 0 and
      // the next launch would start at the beginning of the track.
      if (_restoreInProgress) return;
      unawaited(persistAll());
    });
    // Mirror handler.queueListenable reactively so repo.queue is always
    // fresh. Without this, repo's `_queue` field was being copied from
    // `handler.queue` synchronously after each mutation — but mpv's
    // playlist stream is async, so the copy could land BEFORE the new
    // order was reflected, leaving repo's view stale.
    handler.queueListenable.addListener(_onHandlerQueueChanged);
  }

  void _onHandlerQueueChanged() {
    _queue = handler.queueListenable.value;
    _currentIndex = handler.currentIndex;
    final bridge = _bridge;
    if (bridge != null) {
      bridge.announceQueue(
        _queue.map(_mediaItemFor).toList(),
        startIndex: _currentIndex,
      );
    }
    // Persist on every queue mutation (reorder, add, remove) so a kill
    // mid-session doesn't lose the new order. Skipped during restore
    // for the same reason currentSongStream is — `prepareQueue` emits
    // events before mpv has loaded the file.
    if (_restoreInProgress) return;
    unawaited(persistAll());
  }
  final SunohAudioHandler handler;
  final StreamResolver resolver;
  final PlaybackStateStore store;
  final SettingsStore settings;
  final LibraryStore library;

  /// The active queue, mirroring what the handler holds. Cached here so we
  /// can persist it without round-tripping through mpv's internal playlist.
  List<FeedItem> _queue = const [];
  int _currentIndex = 0;
  String? _sourceLabel;
  DetailRef? _sourceRef;
  /// Tracks the play mode the current queue was started with so
  /// `persistAll` can save it alongside queue/index/position. Without
  /// this, cold-restore always defaults `prepareQueue` to
  /// `PlayMode.track` — which works for songs but turns a live radio
  /// queue into a finite-track playback where `play` does nothing
  /// (mpv reached EOF on the prior session and there's no "next").
  PlayMode _playMode = PlayMode.track;
  List<FeedItem> get queue => _queue;
  int get currentIndex => _currentIndex;
  String? get sourceLabel => _sourceLabel;
  /// DetailRef of the queue's origin (album/playlist). Persisted alongside
  /// sourceLabel so the player's "Go to Album/Playlist" menu row survives
  /// a kill/restart. Null when the queue was started outside a detail
  /// screen (search, radio, library shortcuts).
  DetailRef? get sourceRef => _sourceRef;

  /// Set for the duration of `restore()`. Suppresses the track-change
  /// listener's `persistAll` call so we don't write position=0 over the
  /// saved seek target before mpv has loaded the file.
  bool _restoreInProgress = false;

  SunohAudioServiceBridge? _bridge;

  /// Exposed so AppState's cast wiring can push cast-derived playback
  /// state directly into the OS notification (otherwise the bridge
  /// keeps mirroring mpv's muted-paused state while casting). Null
  /// when audio_service init failed.
  SunohAudioServiceBridge? get bridge => _bridge;

  void attachBridge(SunohAudioServiceBridge bridge) {
    debugPrint('[audio] bridge attached — OS integration live');
    _bridge = bridge;

    // The restore path may have already run before audio_service finished
    // initializing — in which case our earlier announceQueue() was a no-op
    // (the bridge was null). Push the current state now so the lockscreen
    // notification shows the actual song instead of the default app name.
    if (_queue.isNotEmpty) {
      debugPrint('[audio] pushing existing queue to freshly-attached bridge');
      bridge.announceQueue(
        _queue.map(_mediaItemFor).toList(),
        startIndex: _currentIndex,
      );
    } else if (handler.queue.isNotEmpty) {
      // Engine has a queue but repo didn't snapshot it yet (defensive path).
      _queue = handler.queue;
      _currentIndex = handler.currentIndex;
      bridge.announceQueue(
        _queue.map(_mediaItemFor).toList(),
        startIndex: _currentIndex,
      );
    }
  }

  /// Play a queue starting at [startIndex]. Single-track playback is just a
  /// list of one. The handler resolves URLs JIT via the on_load hook.
  Future<void> playQueue(
    List<FeedItem> songs,
    int startIndex, {
    String? sourceLabel,
    DetailRef? sourceRef,
    PlayMode mode = PlayMode.track,
  }) async {
    if (songs.isEmpty) return;
    debugPrint(
        '[audio] playQueue len=${songs.length} startIndex=$startIndex mode=$mode');
    _queue = songs;
    _currentIndex = startIndex;
    _sourceLabel = sourceLabel;
    _sourceRef = sourceRef;
    _playMode = mode;
    await handler.setQueue(songs, startIndex, mode: mode);

    // Best-effort OS metadata push: full queue + the starting item.
    final bridge = _bridge;
    if (bridge != null) {
      bridge.announceQueue(
        songs.map(_mediaItemFor).toList(),
        startIndex: startIndex,
      );
    }
    // Snapshot the new queue so future restores see it. Position will be
    // updated separately via persistCurrentPosition() / persistAll().
    unawaited(persistAll());
  }

  /// Convenience for the common "play this single song" path.
  Future<void> playSong(FeedItem song) => playQueue([song], 0);

  // ── Persistence ───────────────────────────────────────────────────────

  /// Restore the last saved queue + position into mpv WITHOUT auto-playing.
  /// Returns the loaded state (null if nothing was saved) so callers can
  /// reflect it in the UI (mini player, expanded player).
  Future<SavedPlaybackState?> restore() async {
    _restoreInProgress = true;
    try {
      final saved = await store.load();
      if (saved == null) return null;
      _queue = saved.queue;
      _currentIndex = saved.currentIndex;
      _sourceLabel = saved.sourceLabel;
      _sourceRef = saved.sourceRef;
      _playMode = saved.playMode;
      await handler.prepareQueue(
        saved.queue,
        saved.currentIndex,
        seekTo: Duration(seconds: saved.positionSec),
        mode: saved.playMode,
      );
      final bridge = _bridge;
      if (bridge != null) {
        bridge.announceQueue(
          saved.queue.map(_mediaItemFor).toList(),
          startIndex: saved.currentIndex,
        );
      }
      return saved;
    } finally {
      _restoreInProgress = false;
    }
  }

  /// Snapshot queue + index + current position. Heavy-ish (serializes the
  /// whole queue) — call on lifecycle pause / track change, not per tick.
  Future<void> persistAll() async {
    if (_queue.isEmpty) return;
    await store.save(
      queue: _queue,
      currentIndex: _currentIndex,
      positionSec: handler.position.inSeconds,
      sourceLabel: _sourceLabel,
      sourceRef: _sourceRef,
      playMode: _playMode,
    );
  }

  /// Lightweight position-only write — cheap to call every few seconds.
  Future<void> persistCurrentPosition() async {
    await store.updatePosition(handler.position.inSeconds);
  }

  Future<void> play() => handler.play();
  Future<void> pause() => handler.pause();
  Future<void> seek(Duration pos) => handler.seek(pos);
  Future<void> stop() => handler.stop();
  Future<void> next() => handler.skipToNext();
  Future<void> previous() => handler.skipToPrevious();

  /// Live queue listenable — UI watches this to render the queue sheet.
  ValueListenable<List<FeedItem>> get queueListenable => handler.queueListenable;

  /// Queue mutations (drag to reorder, × to remove, tap to jump).
  Future<void> jumpToIndex(int i) async {
    _currentIndex = i;
    await handler.jumpTo(i);
    unawaited(persistAll());
  }

  // ── Queue mutations ────────────────────────────────────────────────────
  // These all delegate to the handler (which drives mpv's internal
  // playlist) and then return. The mirror update + bridge announce +
  // persist all happen reactively in `_onHandlerQueueChanged` when
  // mpv emits the new playlist — single code path, no duplication.

  Future<void> removeFromQueue(int i) => handler.removeAt(i);

  /// Insert `song` right after the currently-playing track. If nothing's
  /// playing, starts a fresh single-song queue.
  Future<void> playNext(FeedItem song, {String? sourceLabel}) async {
    if (_queue.isEmpty) _sourceLabel = sourceLabel;
    await handler.playNext(song);
  }

  /// Append `song` to the end of the queue.
  Future<void> addToQueue(FeedItem song, {String? sourceLabel}) async {
    if (_queue.isEmpty) _sourceLabel = sourceLabel;
    await handler.addToQueue(song);
  }

  Future<void> moveInQueue(int from, int to) => handler.moveItem(from, to);

  /// Toggle shuffle. mpv's native `playlist-shuffle` / `playlist-unshuffle`
  /// preserves the currently-playing track's playback through the
  /// reorder.
  Future<void> setShuffle(bool enabled) => handler.setShuffle(enabled);

  /// Pass-through for the repeat mode. The handler consults this in its
  /// natural-EOF advance path. Manual skip taps ignore it.
  void setRepeat(LoopMode mode) => handler.setRepeat(mode);

  Future<void> clearQueue() async {
    await handler.clearQueue();
    _queue = const [];
    _currentIndex = 0;
    // Audio_service has no clearQueue directly; pushing an empty list does it.
    final bridge = _bridge;
    if (bridge != null) {
      bridge.announceQueue(const [], startIndex: 0);
    }
    unawaited(store.clear());
  }

  static MediaItem _mediaItemFor(FeedItem song) {
    return MediaItem(
      id: song.id,
      title: song.title,
      artist: (song.artists ?? const <ApiArtistRef>[])
          .map((a) => a.name)
          .where((n) => n.isNotEmpty)
          .take(2)
          .join(', '),
      album: '',
      artUri: (song.artwork ?? '').isEmpty ? null : Uri.tryParse(song.artwork!),
      duration: _parseDuration(song.duration),
      extras: {'source': song.source ?? ''},
    );
  }

  static Duration? _parseDuration(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final secs = int.tryParse(raw);
    if (secs == null) return null;
    return Duration(seconds: secs);
  }
}

final audioRepoProvider = Provider<AudioRepo>((ref) {
  throw StateError(
    'audioRepoProvider was read before main() installed the override.',
  );
});
