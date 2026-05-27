// Optional audio_service layer on top of the mpv handler. The bridge does
// NOT own the Player — it references the existing handler. If init hangs
// or throws, in-app playback is untouched.

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import '../cast/cast_service.dart';
import 'audio_handler.dart';

class SunohAudioServiceBridge extends BaseAudioHandler {
  SunohAudioServiceBridge(this._handler) {
    _wire();
  }

  final SunohAudioHandler _handler;
  final List<StreamSubscription<dynamic>> _subs = [];

  /// When true, the bridge's `playingStream` + `positionStream`
  /// listeners ignore mpv updates — the cast layer is pushing
  /// playback state explicitly via [setCastingPlaybackState]. Set
  /// via [setCastingActive].
  bool _castOverride = false;

  void _wire() {
    _subs.add(_handler.playingStream.listen((playing) {
      if (_castOverride) return; // cast layer owns the notification state
      // Controls have to reflect the current state: when playing, expose
      // *pause* (not play). If the controls list doesn't change with state,
      // Android may decide the foreground service isn't really an active
      // media session and kill it when the app is backgrounded.
      playbackState.add(playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {MediaAction.seek},
        processingState: AudioProcessingState.ready,
        playing: playing,
        updatePosition: _handler.position,
      ));
    }));
    _subs.add(_handler.positionStream.listen((pos) {
      if (_castOverride) return;
      playbackState.add(playbackState.value.copyWith(updatePosition: pos));
    }));
  }

  /// Flip the bridge into / out of cast-override mode. While `true`,
  /// updates from mpv are ignored and the bridge only changes its
  /// playbackState when [setCastingPlaybackState] is called. The
  /// initial cast state push happens here on the transition into
  /// override so the notification reflects the cast session
  /// immediately instead of waiting for the first position tick.
  void setCastingActive({
    required bool active,
    required bool playing,
    required Duration position,
  }) {
    _castOverride = active;
    if (active) {
      playbackState.add(playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {MediaAction.seek},
        processingState: AudioProcessingState.ready,
        playing: playing,
        updatePosition: position,
      ));
    } else {
      // Falling back to mpv. Re-emit the current mpv state so the
      // notification snaps back without waiting for the next tick.
      playbackState.add(playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (_handler.isPlaying) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {MediaAction.seek},
        processingState: AudioProcessingState.ready,
        playing: _handler.isPlaying,
        updatePosition: _handler.position,
      ));
    }
  }

  /// Push a live cast-derived snapshot to the OS notification. AppState
  /// calls this on every Cast `playerPositionStream` event (or every
  /// `mediaStatusStream` event for the playing flag).
  void setCastingPlaybackState({
    required bool playing,
    required Duration position,
  }) {
    if (!_castOverride) return;
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {MediaAction.seek},
      processingState: AudioProcessingState.ready,
      playing: playing,
      updatePosition: position,
    ));
  }

  /// Tell the OS about the full queue + which one is active. Called by
  /// AudioRepo after each playQueue.
  void announceQueue(List<MediaItem> items, {required int startIndex}) {
    debugPrint('[audio-svc] announceQueue len=${items.length} idx=$startIndex');
    queue.add(items);
    if (startIndex >= 0 && startIndex < items.length) {
      mediaItem.add(items[startIndex]);
    }
  }

  /// Push a new active MediaItem when mpv advances to the next track. The
  /// queue stream stays as-is; only the current pointer changes.
  void onTrackChanged(MediaItem item) {
    debugPrint('[audio-svc] onTrackChanged → ${item.title}');
    mediaItem.add(item);
  }

  // ── audio_service callbacks → forward to the right backend ────────────
  //
  // When the OS notification or a hardware media key fires these, we
  // need to route to whichever backend currently owns playback. mpv is
  // the default; Cast takes over while a session is live (mpv stays
  // loaded but muted, so calling _handler.pause/play during a cast
  // session would just no-op the silent mpv side and the receiver
  // would keep playing).

  @override
  Future<void> play() async {
    if (_castOverride) {
      await CastService.instance.play();
    } else {
      await _handler.play();
    }
  }

  @override
  Future<void> pause() async {
    if (_castOverride) {
      await CastService.instance.pause();
    } else {
      await _handler.pause();
    }
  }

  @override
  Future<void> seek(Duration position) async {
    if (_castOverride) {
      await CastService.instance.seek(position);
    } else {
      await _handler.seek(position);
    }
  }

  @override
  Future<void> skipToNext() => _handler.skipToNext();

  @override
  Future<void> skipToPrevious() => _handler.skipToPrevious();

  @override
  Future<void> stop() async {
    // Stop from the lockscreen = "I'm done." If casting, disconnect
    // first (which stops the receiver), then run the mpv-side stop so
    // queue + position are flushed.
    if (_castOverride) {
      await CastService.instance.disconnect();
    }
    await _handler.stop();
    await super.stop();
  }

  /// Android fires this when the user swipes the app from the recents list.
  /// We pause instead of stopping so the queue + saved position stay intact
  /// in memory + on disk. The OS handles winding down the foreground service
  /// after we pause (with `androidStopForegroundOnPause: true` in main.dart).
  @override
  Future<void> onTaskRemoved() async {
    debugPrint('[audio-svc] onTaskRemoved — pausing');
    await pause();
  }
}
