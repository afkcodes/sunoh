// Optional audio_service layer on top of the mpv handler. The bridge does
// NOT own the Player — it references the existing handler. If init hangs
// or throws, in-app playback is untouched.

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import '../cast/cast_service.dart';
import 'audio_handler.dart';
import 'auto_browse.dart';

class SunohAudioServiceBridge extends BaseAudioHandler {
  SunohAudioServiceBridge(this._handler, {AutoBrowseTree? browse})
    : _browse = browse {
    _wire();
  }

  final SunohAudioHandler _handler;

  /// Serves the Android Auto browse tree. Null in contexts where the
  /// library layer wasn't available at init — browsing then returns empty
  /// rather than throwing, and phone playback is unaffected.
  final AutoBrowseTree? _browse;
  final List<StreamSubscription<dynamic>> _subs = [];

  /// When true, the bridge's `playingStream` + `positionStream`
  /// listeners ignore mpv updates — the cast layer is pushing
  /// playback state explicitly via [setCastingPlaybackState]. Set
  /// via [setCastingActive].
  bool _castOverride = false;

  /// Every playback-state push goes through here.
  ///
  /// Controls have to reflect the current state: when playing, expose *pause*
  /// (not play). If the controls list doesn't change with state, Android may
  /// decide the foreground service isn't really an active media session and
  /// kill it when the app is backgrounded.
  ///
  /// `systemActions` is what Android Auto reads to decide which affordances
  /// the head unit may offer. Without playFromMediaId / playFromSearch the car
  /// can draw the browse tree but tapping a row does nothing, and voice
  /// requests are refused before they reach us.
  void _emitState({required bool playing, required Duration position}) {
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.playFromMediaId,
          MediaAction.playFromSearch,
          MediaAction.skipToNext,
          MediaAction.skipToPrevious,
        },
        processingState: AudioProcessingState.ready,
        playing: playing,
        updatePosition: position,
      ),
    );
  }

  void _wire() {
    _subs.add(
      _handler.playingStream.listen((playing) {
        if (_castOverride) return; // cast layer owns the notification state
        _emitState(playing: playing, position: _handler.position);
      }),
    );
    _subs.add(
      _handler.positionStream.listen((pos) {
        if (_castOverride) return;
        playbackState.add(playbackState.value.copyWith(updatePosition: pos));
      }),
    );
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
      _emitState(playing: playing, position: position);
    } else {
      // Falling back to mpv. Re-emit the current mpv state so the
      // notification snaps back without waiting for the next tick.
      _emitState(playing: _handler.isPlaying, position: _handler.position);
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
    _emitState(playing: playing, position: position);
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

  // ── Android Auto: browsing + voice ───────────────────────────────────
  //
  // Android Auto never sees our Flutter UI. It connects to the exported
  // MediaBrowserService and draws its own screens from the MediaItems these
  // callbacks return. All the routing lives in AutoBrowseTree; the bridge
  // just forwards and guards against a null tree.

  @override
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) async {
    final browse = _browse;
    if (browse == null) return const [];
    try {
      final items = await browse.getChildren(parentMediaId);
      debugPrint('[auto] getChildren($parentMediaId) → ${items.length}');
      return items;
    } catch (e, st) {
      // A throw here surfaces in the car as a hard "can't load" state and can
      // wedge the browse stack. An empty list is recoverable — the user backs
      // out and tries again.
      debugPrint('[auto] getChildren($parentMediaId) FAILED: $e\n$st');
      return const [];
    }
  }

  @override
  Future<MediaItem?> getMediaItem(String mediaId) async {
    try {
      return await _browse?.getMediaItem(mediaId);
    } catch (e) {
      debugPrint('[auto] getMediaItem($mediaId) failed: $e');
      return null;
    }
  }

  @override
  Future<void> playFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) async {
    debugPrint('[auto] playFromMediaId($mediaId)');
    try {
      await _browse?.playFromMediaId(mediaId);
    } catch (e, st) {
      debugPrint('[auto] playFromMediaId($mediaId) FAILED: $e\n$st');
    }
  }

  @override
  Future<void> playFromSearch(
    String query, [
    Map<String, dynamic>? extras,
  ]) async {
    debugPrint('[auto] playFromSearch("$query")');
    try {
      await _browse?.playFromSearch(query);
    } catch (e, st) {
      debugPrint('[auto] playFromSearch("$query") FAILED: $e\n$st');
    }
  }

  @override
  Future<List<MediaItem>> search(
    String query, [
    Map<String, dynamic>? extras,
  ]) async {
    try {
      return await _browse?.search(query) ?? const [];
    } catch (e) {
      debugPrint('[auto] search("$query") failed: $e');
      return const [];
    }
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
