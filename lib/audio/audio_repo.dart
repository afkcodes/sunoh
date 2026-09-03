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
import 'sponsorblock_skipper.dart';

class AudioRepo {
  AudioRepo({
    required this.handler,
    required this.resolver,
    required this.store,
    required this.settings,
    required this.library,
    required this.sponsorBlock,
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
      // Look up skip segments for the new track. Fire-and-forget: the
      // skipper degrades to "no segments" on any failure, and playback
      // must never wait on a third-party lookup.
      unawaited(sponsorBlock.onTrackChanged(song));
      // Ask the hi-res catalog about the *next* track now, while this one has
      // a whole song's worth of time to answer in. Without it, pressing next
      // met a cold lookup and waited out its budget before any sound.
      _warmNextLossless();
      // Skip while restoring — `prepareQueue` emits a currentSong event
      // before mpv has actually loaded the file, so handler.position is
      // 0 even though the SAVED state had a non-zero seek target. Writing
      // back at this moment would clobber the saved position with 0 and
      // the next launch would start at the beginning of the track.
      if (_restoreInProgress) return;
      unawaited(persistAll());
    });
    // SponsorBlock: jump past a segment as soon as the play head enters
    // it. Driven off mpv's position stream rather than a timer so it
    // stays accurate through seeks and track changes.
    handler.positionStream.listen((position) {
      final target = sponsorBlock.skipTargetFor(position);
      if (target != null) unawaited(handler.seek(target));
    });

    // Feed mpv's real duration back into the OS notification.
    //
    // MediaItem.duration is otherwise only ever what the feed told us at
    // queue time, and Android draws no seekbar at all when it's null.
    // YouTube carousel cards carry no duration, so those tracks played
    // with a bare notification. mpv knows the true length once the file
    // is open, so re-announce the current item with it — which also
    // corrects any source whose metadata duration is wrong.
    handler.durationStream.listen((duration) {
      if (duration <= Duration.zero) return;
      final bridge = _bridge;
      final song = handler.currentSong;
      if (bridge == null || song == null) return;
      // Only re-announce on a real change; mpv re-emits this while
      // buffering and every push redraws the notification.
      if (_announcedDuration[song.id] == duration) return;
      _announcedDuration[song.id] = duration;
      bridge.onTrackChanged(_mediaItemFor(song, duration: duration));
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

  /// Skips non-music segments on YouTube tracks. Consulted from the
  /// position stream; a no-op until the user's setting enables it.
  final SponsorBlockSkipper sponsorBlock;

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

  /// Durations already pushed to the OS, keyed by song id. Guards against
  /// re-announcing on mpv's repeated duration events while buffering.
  final Map<String, Duration> _announcedDuration = <String, Duration>{};

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
  }) async {
    if (songs.isEmpty) return;
    debugPrint('[audio] playQueue len=${songs.length} startIndex=$startIndex');
    _queue = songs;
    _currentIndex = startIndex;
    _sourceLabel = sourceLabel;
    _sourceRef = sourceRef;
    // Kick the segment lookup here as well as from currentSongStream.
    // That stream only emits when mpv's playlist INDEX changes, and
    // starting a fresh single-track queue leaves the index at 0 — so
    // tapping a search result would otherwise never trigger a lookup.
    unawaited(
      sponsorBlock.onTrackChanged(songs[startIndex.clamp(0, songs.length - 1)]),
    );
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

  /// Wait for mpv's playlist to reach [expected] entries.
  ///
  /// Polled rather than awaited on a stream: the queue listenable is a plain
  /// ValueListenable with no completion signal, and the interesting condition
  /// is a length rather than an event. Capped, because a queue that never
  /// arrives must not leave restore suppressed forever — a stale guard would
  /// stop persisting real changes for the rest of the session.
  Future<void> _queueSettled(int expected) async {
    const step = Duration(milliseconds: 50);
    const limit = Duration(seconds: 5);
    var waited = Duration.zero;
    while (waited < limit) {
      if (handler.queueListenable.value.length >= expected) return;
      await Future<void>.delayed(step);
      waited += step;
    }
    debugPrint('[audio] queue did not settle at $expected — releasing guard');
  }

  /// The last saved queue + position, read from disk.
  ///
  /// Split from [prepareSaved] because the two have wildly different costs.
  /// This is a Hive read; that one opens the file in mpv, which resolves a
  /// stream URL over the network. They used to be one method, so the mini
  /// player sat empty until a round trip to a CDN had completed — the saved
  /// track and its position arrived seconds after the app was already on
  /// screen. Callers show this result immediately and prepare in the
  /// background.
  Future<SavedPlaybackState?> loadSaved() async {
    final saved = await store.load();
    if (saved == null) return null;
    _queue = saved.queue;
    _currentIndex = saved.currentIndex;
    _sourceLabel = saved.sourceLabel;
    _sourceRef = saved.sourceRef;
    return saved;
  }

  /// Hand the saved queue to mpv, paused and seeked, ready for a tap on play.
  ///
  /// [_restoreInProgress] covers exactly this: `prepareQueue` emits
  /// track-change and queue events before mpv has loaded the file, and
  /// persisting on those would write position 0 over the saved one.
  Future<void> prepareSaved(SavedPlaybackState saved) async {
    _restoreInProgress = true;
    try {
      unawaited(
        sponsorBlock.onTrackChanged(
          saved.queue[saved.currentIndex.clamp(0, saved.queue.length - 1)],
        ),
      );
      await handler.prepareQueue(
        saved.queue,
        saved.currentIndex,
        seekTo: Duration(seconds: saved.positionSec),
      );
      // prepareQueue returning does not mean mpv has finished building its
      // playlist. It keeps emitting queue events as the entries land, and
      // each one drives _onHandlerQueueChanged -> persistAll with a partial
      // queue and position 0 — which overwrote the very state just restored.
      // Measured on a device: sixteen writes, the queue growing 15 -> 52,
      // every one of them stamping pos=0s over a saved 202s.
      await _queueSettled(saved.queue.length);
      final bridge = _bridge;
      if (bridge != null) {
        bridge.announceQueue(
          saved.queue.map(_mediaItemFor).toList(),
          startIndex: saved.currentIndex,
        );
      }
    } finally {
      _restoreInProgress = false;
    }
  }

  /// How far ahead the hi-res catalog is asked to look.
  ///
  /// Three covers the way people actually skip — a couple of taps to get past
  /// something, not a scroll through the whole queue. Each is one small
  /// request, answered once and then cached for the session, so the cost is
  /// bounded even when someone skips through an album. Going deeper would
  /// mostly buy lookups for tracks nobody reaches.
  static const int _kLosslessWarmAhead = 3;

  /// Start the hi-res lookups for the next few tracks.
  ///
  /// Cheap by construction: the API skips anything it already knows, already
  /// ruled out, or is already fetching, so this settles to nothing while a
  /// queue plays through in order.
  void _warmNextLossless() {
    for (var i = 1; i <= _kLosslessWarmAhead; i++) {
      final at = _currentIndex + i;
      if (at < 0 || at >= _queue.length) return;
      resolver.warmLossless(_queue[at]);
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
  ValueListenable<List<FeedItem>> get queueListenable =>
      handler.queueListenable;

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

  /// [duration] overrides the feed's value — used once mpv reports the
  /// real length, so the notification gets a seekbar even when the source
  /// metadata had none.
  ///
  /// Falls back to a previously corrected duration for the same song.
  /// Without that, any later `announceQueue` (queue reorder, add, or the
  /// mirror sync that fires on every playlist change) would rebuild the
  /// item from feed metadata alone and wipe the seekbar back out — which
  /// is why it appeared for some tracks and not others.
  MediaItem _mediaItemFor(FeedItem song, {Duration? duration}) {
    return MediaItem(
      id: song.id,
      title: song.title,
      artist: (song.artists ?? const <ApiArtistRef>[])
          .map((a) => a.name)
          .where((n) => n.isNotEmpty)
          .take(2)
          .join(', '),
      album: '',
      artUri: song.artworkUri,
      duration:
          duration ??
          _announcedDuration[song.id] ??
          _parseDuration(song.duration),
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
