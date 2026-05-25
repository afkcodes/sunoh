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
  }) async {
    if (songs.isEmpty) return;
    debugPrint(
        '[audio] playQueue len=${songs.length} startIndex=$startIndex');
    _queue = songs;
    _currentIndex = startIndex;
    _sourceLabel = sourceLabel;
    _sourceRef = sourceRef;
    await handler.setQueue(songs, startIndex);

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
      await handler.prepareQueue(
        saved.queue,
        saved.currentIndex,
        seekTo: Duration(seconds: saved.positionSec),
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

  Future<void> removeFromQueue(int i) async {
    await handler.removeAt(i);
    _queue = handler.queue;
    _currentIndex = handler.currentIndex;
    // Update audio_service's queue stream so the lockscreen reflects the
    // change too. queue (the BehaviorSubject from BaseAudioHandler) just
    // takes a fresh List<MediaItem>.
    _bridge?.announceQueue(_queue.map(_mediaItemFor).toList(),
        startIndex: _currentIndex);
    unawaited(persistAll());
  }

  /// Insert `song` right after the currently-playing track. Used by the
  /// track-row context menu's "Play next" action. If nothing's playing,
  /// starts a fresh single-song queue.
  Future<void> playNext(FeedItem song, {String? sourceLabel}) async {
    if (_queue.isEmpty) {
      _sourceLabel = sourceLabel;
    }
    await handler.playNext(song);
    _queue = handler.queue;
    _currentIndex = handler.currentIndex;
    _bridge?.announceQueue(_queue.map(_mediaItemFor).toList(),
        startIndex: _currentIndex);
    unawaited(persistAll());
  }

  /// Append `song` to the end of the queue.
  Future<void> addToQueue(FeedItem song, {String? sourceLabel}) async {
    if (_queue.isEmpty) {
      _sourceLabel = sourceLabel;
    }
    await handler.addToQueue(song);
    _queue = handler.queue;
    _currentIndex = handler.currentIndex;
    _bridge?.announceQueue(_queue.map(_mediaItemFor).toList(),
        startIndex: _currentIndex);
    unawaited(persistAll());
  }

  Future<void> moveInQueue(int from, int to) async {
    await handler.moveItem(from, to);
    _queue = handler.queue;
    _currentIndex = handler.currentIndex;
    _bridge?.announceQueue(_queue.map(_mediaItemFor).toList(),
        startIndex: _currentIndex);
    unawaited(persistAll());
  }

  /// Toggle shuffle on the handler. Shuffles the upcoming tail of the
  /// queue (in place, preserving the now-playing track) when enabled;
  /// restores the original ordering when disabled. After the handler
  /// rearranges its queue we mirror it locally, push the bridge an
  /// updated MediaItem list (so the OS notification's queue reflects
  /// the new order), and persist so a kill/restart restores the
  /// post-shuffle state — otherwise the saved queue would be the
  /// original and the user would lose their shuffled play order.
  void setShuffle(bool enabled) {
    handler.setShuffle(enabled);
    _queue = handler.queue;
    _currentIndex = handler.currentIndex;
    _bridge?.announceQueue(_queue.map(_mediaItemFor).toList(),
        startIndex: _currentIndex);
    unawaited(persistAll());
  }

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
