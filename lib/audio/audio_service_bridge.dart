// Optional audio_service layer on top of the mpv handler. The bridge does
// NOT own the Player — it references the existing handler. If init hangs
// or throws, in-app playback is untouched.

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import 'audio_handler.dart';

class SunohAudioServiceBridge extends BaseAudioHandler {
  SunohAudioServiceBridge(this._handler) {
    _wire();
  }

  final SunohAudioHandler _handler;
  final List<StreamSubscription<dynamic>> _subs = [];

  void _wire() {
    _subs.add(_handler.playingStream.listen((playing) {
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
      playbackState.add(playbackState.value.copyWith(updatePosition: pos));
    }));
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

  // ── audio_service callbacks → forward to the mpv handler ──────────────

  @override
  Future<void> play() => _handler.play();

  @override
  Future<void> pause() => _handler.pause();

  @override
  Future<void> seek(Duration position) => _handler.seek(position);

  @override
  Future<void> skipToNext() => _handler.skipToNext();

  @override
  Future<void> skipToPrevious() => _handler.skipToPrevious();

  @override
  Future<void> stop() async {
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
