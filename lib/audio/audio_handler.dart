// Two-player audio handler — real overlapping crossfade.
//
// Two mpv `Player` instances ("musical chairs"): one is the "active" player
// the user hears, the other is "idle" until a transition. The queue lives at
// the handler level, NOT in mpv's playlist — both players play one track at
// a time and we manually decide what each plays next.
//
// **Crossfade (N>0)**:
//   1. Active's track approaches `duration - N`.
//   2. Load next track onto idle at volume 0, start it playing.
//   3. Ramp active 100→0 + idle 0→100 over N seconds using EQUAL-POWER curves
//      (`cos`/`sin`) so the perceived loudness stays constant across the
//      crossover — linear ramps sound like the audio dips at the midpoint.
//   4. When ramp completes: pause old active, swap roles, advance index.
//
// **Gapless (N=0)**:
//   Detect natural EOF on active, load next on active immediately. Small load
//   gap (~50-100 ms) is acceptable for the personal-app context. This isn't
//   mpv's sample-accurate gapless — sacrificed in exchange for a unified
//   architecture between the gapless + crossfade paths.
//
// **Public API**:
//   Surface is unchanged from the previous single-player handler so AudioRepo
//   doesn't need any modifications. `positionStream` / `playingStream` /
//   `currentSongStream` are switched stream controllers that re-bind to the
//   active player on every role swap.
//
// **Manual skips bypass crossfade** — `skipToNext` / `skipToPrevious` /
// `jumpTo` cancel any in-flight ramp and load the target on active
// immediately. A tap should feel instant.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../api/dto.dart';
import '../api/stream_resolver.dart';
import 'url_refresh.dart';

/// Placeholder scheme — mpv asks us to resolve this in the on_load hook.
const _placeholderScheme = 'sunoh-song://';

class SunohAudioHandler {
  SunohAudioHandler({required this.resolver}) {
    debugPrint('[audio] SunohAudioHandler() constructing 2× Player…');
    _a = _buildPlayer('A');
    _b = _buildPlayer('B');
    _urlRefresh = UrlRefreshScheduler(refresh: _refreshCurrentTrack);
    debugPrint('[audio] Players constructed ✓');
    _wireSharedStreams();
    _bindActivePlayerStreams();
    unawaited(_applyAudioOutputTuning());
  }

  final StreamResolver resolver;

  // ── Two Player instances ───────────────────────────────────────────────
  late final Player _a;
  late final Player _b;
  bool _activeIsA = true;
  Player get _active => _activeIsA ? _a : _b;
  Player get _idle => _activeIsA ? _b : _a;

  Player _buildPlayer(String label) {
    final p = Player(
      configuration: const PlayerConfiguration(
        autoPlay: true,
        initialVolume: 100.0,
        logLevel: LogLevel.info,
      ),
    );
    p.registerHook(Hook.load, timeout: const Duration(seconds: 10));
    debugPrint('[audio] Player $label constructed');
    return p;
  }

  // ── Handler-level queue ────────────────────────────────────────────────
  // The queue lives here, not in mpv's playlist. Both players play single
  // tracks; the handler decides what each plays next. This is required for
  // the musical-chairs crossfade where two tracks overlap.
  List<FeedItem> _queue = const [];
  int _currentIndex = 0;

  final ValueNotifier<List<FeedItem>> _queueListenable =
      ValueNotifier<List<FeedItem>>(const []);
  ValueListenable<List<FeedItem>> get queueListenable => _queueListenable;
  List<FeedItem> get queue => _queueListenable.value;

  void _updateQueue(List<FeedItem> next) {
    _queue = next;
    _queueListenable.value = List.unmodifiable(next);
  }

  // ── Switched public streams ────────────────────────────────────────────
  // Consumers (AppState, audio_service bridge) subscribe to these once. The
  // handler re-binds the underlying source streams to whichever player is
  // currently active.
  final StreamController<Duration> _positionCtl =
      StreamController<Duration>.broadcast();
  final StreamController<bool> _playingCtl =
      StreamController<bool>.broadcast();
  final StreamController<FeedItem?> _currentSongCtl =
      StreamController<FeedItem?>.broadcast();

  Stream<Duration> get positionStream => _positionCtl.stream;
  Stream<bool> get playingStream => _playingCtl.stream;
  Stream<FeedItem?> get currentSongStream =>
      _currentSongCtl.stream.distinct((a, b) => a?.id == b?.id);

  StreamSubscription? _activePosSub;
  StreamSubscription? _activePlayingSub;

  void _bindActivePlayerStreams() {
    _activePosSub?.cancel();
    _activePlayingSub?.cancel();
    _activePosSub = _active.stream.position.listen(_positionCtl.add);
    _activePlayingSub = _active.stream.playbackState.listen((s) {
      _playingCtl.add(s == MpvPlaybackState.playing);
    });
  }

  void _emitCurrentSong() {
    if (_currentIndex < 0 || _currentIndex >= _queue.length) {
      _currentSongCtl.add(null);
    } else {
      _currentSongCtl.add(_queue[_currentIndex]);
    }
  }

  // ── Public surface getters ─────────────────────────────────────────────
  bool get isPlaying => _active.state.playing;
  Duration get position => _active.state.position;
  Duration get duration => _active.state.duration;
  int get currentIndex => _currentIndex;
  FeedItem? get currentSong {
    if (_currentIndex < 0 || _currentIndex >= _queue.length) return null;
    return _queue[_currentIndex];
  }

  // ── URL refresh / on_load hook state ──────────────────────────────────
  late final UrlRefreshScheduler _urlRefresh;

  /// One-shot start-position consumed by the next on_load hook on `_active`.
  /// Used for cross-session restore and the URL-refresh swap.
  Duration? _pendingStartPosition;

  /// One-shot: when set, the next on_load hook calls resolve with
  /// forceRefresh=true so embedded (stale) mediaUrls are bypassed.
  bool _forceRefreshNextResolve = false;

  final Map<String, int> _loadFailRetries = {};
  static const _maxRetries = 2;

  // ── Crossfade state ───────────────────────────────────────────────────
  int _crossfadeSec = 0;
  bool _userInitiatedSkip = false;

  /// How long before the ramp window opens we pre-warm the idle player.
  /// Without a buffer, the idle player is still loading / demuxing / filling
  /// its audio buffer when the ramp starts — so for the first ~500 ms the
  /// idle outputs silence (volume already ramped up but no audio yet), and
  /// the user perceives "next track starts late". Pre-warming at vol 0
  /// before the ramp gives mpv time to fill the pipeline so audio actually
  /// starts the moment the ramp does.
  static const _kPrewarmBuffer = Duration(milliseconds: 700);

  /// True while a crossfade ramp is in progress. Suppresses re-triggering
  /// the kick on the same track and prevents natural-EOF auto-advance from
  /// fighting the swap.
  bool _crossfadeInProgress = false;
  Timer? _crossfadeTimer;
  DateTime? _crossfadeStartedAt;

  /// Set as soon as we *pre-warm* idle, BEFORE the ramp window opens.
  /// Cleared on every track change.
  bool _crossfadeKickedForCurrent = false;
  bool _idlePrewarmed = false;
  Timer? _rampStartTimer;

  void setCrossfade(int seconds) {
    _crossfadeSec = seconds.clamp(0, 12);
    debugPrint('[crossfade] set to ${_crossfadeSec}s');
    if (_crossfadeSec == 0 && _crossfadeInProgress) {
      _cancelCrossfade(snapToActive: true);
    }
  }

  // ── Subscriptions ──────────────────────────────────────────────────────
  final List<StreamSubscription<dynamic>> _subs = [];

  void _wireSharedStreams() {
    // Both players: error + log + on_load hook + endFile.
    for (final pair in [(_a, 'A'), (_b, 'B')]) {
      final p = pair.$1;
      final label = pair.$2;
      _subs.add(p.stream.error.listen((e) => _onError(p, label, e)));
      _subs.add(p.stream.log.listen((entry) {
        final prefix = entry.prefix.toLowerCase();
        if (prefix == 'ao' ||
            prefix == 'demux' ||
            prefix == 'ffmpeg' ||
            prefix == 'cplayer' ||
            entry.level == LogLevel.error ||
            entry.level == LogLevel.fatal) {
          debugPrint(
              '[mpv $label/${entry.prefix}] ${entry.level.name}: ${entry.text}');
        }
      }));
      _subs.add(p.stream.hook.listen((event) => _onHook(p, label, event)));
      _subs.add(p.stream.endFile.listen((event) => _onEndFile(p, label, event)));
    }

    // Position tick on whichever player is active → drives the crossfade
    // pre-warm trigger AND consumers (via the switched _positionCtl, bound
    // in _bindActivePlayerStreams).
    _subs.add(positionStream.listen(_onActivePosition));
    // URL refresh cancels itself whenever the active track changes.
    _subs.add(currentSongStream.listen((_) => _urlRefresh.cancel()));
  }

  /// One-shot mpv configuration applied to BOTH players after construction.
  Future<void> _applyAudioOutputTuning() async {
    for (final p in [_a, _b]) {
      try {
        await p.setAudioBuffer(const Duration(milliseconds: 500));
        // We manage the playlist ourselves so per-player prefetch is moot.
        // Keep gapless on for any back-to-back same-format playback edge
        // cases mpv may surface (e.g., HLS variant continuity).
        await p.setGapless(Gapless.yes);
      } catch (e) {
        debugPrint('[audio] tuning failed: $e');
      }
    }
  }

  // ── on_load hook ───────────────────────────────────────────────────────

  /// Identifies whose hook fired by player reference. Identical body to the
  /// old single-player handler, with the resolver-side `forceRefresh` flag.
  /// Only the ACTIVE player's hook resolution schedules a URL refresh — the
  /// idle player is short-lived and short-track (only used during ramps).
  Future<void> _onHook(Player p, String label, MpvHookEvent event) async {
    if (event.hook != Hook.load) {
      p.continueHook(event.id);
      return;
    }
    try {
      final raw = await p.getRawProperty('stream-open-filename') ?? '';
      if (!raw.startsWith(_placeholderScheme)) return;
      final encoded = raw.substring(_placeholderScheme.length);
      final id = Uri.decodeComponent(encoded);
      final song = _queue.firstWhere(
        (s) => s.id == id,
        orElse: () => const FeedItem(id: '', title: '', type: '', image: []),
      );
      if (song.id.isEmpty) {
        debugPrint('[audio/$label] hook: no song in queue for id "$id"');
        return;
      }
      final fresh = _forceRefreshNextResolve;
      _forceRefreshNextResolve = false;
      debugPrint(
          '[audio/$label] hook resolving ${song.id}${fresh ? ' (forceRefresh)' : ''}');
      final url = await resolver.resolve(song, forceRefresh: fresh);
      debugPrint('[audio/$label] hook resolved → $url');
      await p.setRawProperty('stream-open-filename', url);

      // One-shot start-position applies only when this hook fires on the
      // active player (idle's loads always start at 0).
      if (identical(p, _active)) {
        final start = _pendingStartPosition;
        if (start != null && start.inMilliseconds > 0) {
          debugPrint('[audio/$label] hook applying start=${start.inSeconds}s');
          await p.setRawProperty(
            'file-local-options/start',
            start.inSeconds.toString(),
          );
          _pendingStartPosition = null;
        }
      }

      // Pre-emptive URL refresh — only schedule for the active player,
      // since idle's role is purely the next-track holder during a ramp.
      if (identical(p, _active)) {
        _urlRefresh.schedule(songId: song.id, resolvedUrl: url);
      }
    } catch (e) {
      debugPrint('[audio/$label] hook failed: $e');
    } finally {
      p.continueHook(event.id);
    }
  }

  void _onError(Player p, String label, MpvPlayerError err) {
    debugPrint('[mpv $label error] $err');
    if (err is! MpvEndFileError || !err.isLoadingError) return;

    // Only act on errors from the active player. Idle errors are best-effort.
    if (!identical(p, _active)) return;

    if (!p.state.playing) {
      debugPrint('[audio] load error while paused — not retrying/skipping');
      return;
    }
    if (_currentIndex < 0 || _currentIndex >= _queue.length) return;
    final song = _queue[_currentIndex];
    final tries = _loadFailRetries[song.id] ?? 0;
    if (tries >= _maxRetries) {
      debugPrint(
          '[audio] giving up on ${song.id} after $tries retries — skipping');
      _loadFailRetries.remove(song.id);
      // Skip to next track on active.
      if (_currentIndex + 1 < _queue.length) {
        _userInitiatedSkip = true; // suppress crossfade for forced skip
        unawaited(_advanceTo(_currentIndex + 1, play: true));
      }
      return;
    }
    _loadFailRetries[song.id] = tries + 1;
    debugPrint(
        '[audio] load error for ${song.id} (try ${tries + 1}/$_maxRetries) — re-opening');
    unawaited(p.open(Media(_placeholderFor(song)), play: true));
  }

  void _onEndFile(Player p, String label, MpvFileEndedEvent event) {
    if (event.reason != MpvEndFileReason.eof) return;
    // We only act on EOF from the active player.
    if (!identical(p, _active)) return;

    final pos = p.state.position;
    final dur = p.state.duration;

    // Premature EOF (mpv reports network drops as eof) → URL refresh.
    if (dur > const Duration(seconds: 3) &&
        pos < dur - const Duration(seconds: 3)) {
      debugPrint(
          '[url-refresh] premature EOF at ${pos.inSeconds}/${dur.inSeconds}s');
      unawaited(_urlRefresh.triggerRefresh(reason: 'premature EOF'));
      return;
    }

    // Natural end-of-track. If a crossfade is in progress, the swap will
    // handle index advancement — don't double-advance.
    if (_crossfadeInProgress) return;

    // Gapless-path advance (no crossfade, or crossfade didn't trigger).
    if (_currentIndex + 1 < _queue.length) {
      debugPrint('[audio/$label] natural EOF — advancing');
      unawaited(_advanceTo(_currentIndex + 1, play: true));
    } else {
      debugPrint('[audio/$label] EOF at end of queue');
    }
  }

  // ── Active-position-driven crossfade trigger ──────────────────────────

  void _onActivePosition(Duration pos) {
    if (_crossfadeSec <= 0) return;
    if (_crossfadeInProgress) return;
    if (_userInitiatedSkip) return;
    if (_currentIndex + 1 >= _queue.length) return;

    final dur = _active.state.duration;
    if (dur <= Duration.zero) return;
    // Tracks shorter than 2× crossfade duration aren't worth crossfading —
    // we'd be ramping more than we're playing at full volume.
    if (dur.inSeconds < _crossfadeSec * 2) return;

    final remainingMs = dur.inMilliseconds - pos.inMilliseconds;
    final windowMs = _crossfadeSec * 1000;
    final prewarmTriggerMs = windowMs + _kPrewarmBuffer.inMilliseconds;

    // Phase 1: pre-warm idle so its audio pipeline is full and emitting
    // (silently at vol 0) by the time the ramp starts. Without this the
    // first ~500 ms of the ramp window is silent on the idle side because
    // mpv's still loading + buffering.
    if (!_idlePrewarmed && remainingMs <= prewarmTriggerMs) {
      _idlePrewarmed = true;
      unawaited(_prewarmIdle());
      return;
    }
    // Phase 2: ramp begins exactly at `duration - N` regardless of when
    // pre-warm completed. Pre-warm was a head start, not a substitute.
    if (!_crossfadeKickedForCurrent && remainingMs <= windowMs) {
      _crossfadeKickedForCurrent = true;
      unawaited(_kickRamp());
    }
  }

  /// Open the next track on the idle player at volume 0 — gives mpv time
  /// to load, demux, and start emitting audio before the ramp begins.
  Future<void> _prewarmIdle() async {
    final nextIndex = _currentIndex + 1;
    if (nextIndex >= _queue.length) return;
    final nextSong = _queue[nextIndex];
    debugPrint(
        '[crossfade] pre-warming idle (+${_kPrewarmBuffer.inMilliseconds}ms) → '
        '${nextSong.title}');
    try {
      await _idle.setVolume(0);
      await _idle.open(Media(_placeholderFor(nextSong)), play: true);
    } catch (e) {
      debugPrint('[crossfade] pre-warm failed: $e');
      _idlePrewarmed = false;
    }
  }

  /// Start the volume ramp. Equal-power curves keep the perceived loudness
  /// constant across the crossover.
  Future<void> _kickRamp() async {
    if (!_idlePrewarmed) {
      // Edge case: position jumped past the pre-warm trigger straight into
      // the ramp window (seek, time jitter). Pre-warm now and accept the
      // first ~500 ms of silent overlap.
      await _prewarmIdle();
    }
    debugPrint('[crossfade] ramp start (${_crossfadeSec}s, equal-power)');
    _crossfadeInProgress = true;
    _crossfadeStartedAt = DateTime.now();
    const tick = Duration(milliseconds: 50);
    _crossfadeTimer = Timer.periodic(tick, (t) {
      final start = _crossfadeStartedAt;
      if (start == null) {
        t.cancel();
        return;
      }
      final elapsedMs = DateTime.now().difference(start).inMilliseconds;
      final fadeDurMs = _crossfadeSec * 1000;
      if (elapsedMs >= fadeDurMs) {
        t.cancel();
        unawaited(_completeCrossfade());
        return;
      }
      // cos goes 1 → 0, sin goes 0 → 1, cos²+sin²=1 ⇒ constant loudness.
      final progress = elapsedMs / fadeDurMs;
      final activeVol = math.cos(progress * math.pi / 2) * 100.0;
      final idleVol = math.sin(progress * math.pi / 2) * 100.0;
      _active.setVolume(activeVol);
      _idle.setVolume(idleVol);
    });
  }

  /// Ramp complete — swap roles. Old active becomes idle (paused). New
  /// active was already playing the next track at vol 100.
  ///
  /// Order matters: re-bind public streams to the new active FIRST so the
  /// `playingStream` stays continuously emitting `true` across the swap.
  /// If we paused old active first, the `playingStream` (still bound to
  /// old) would emit a brief `false`, which Android's foreground service
  /// can interpret as "playback ended" and tear down the service.
  Future<void> _completeCrossfade() async {
    debugPrint('[crossfade] complete — swapping roles');
    final oldActive = _active;
    // 1. Flip role pointer + ensure new active is at full volume.
    _activeIsA = !_activeIsA;
    await _active.setVolume(100);
    _currentIndex++;
    _crossfadeInProgress = false;
    _crossfadeKickedForCurrent = false;
    _idlePrewarmed = false;
    _crossfadeTimer = null;
    _crossfadeStartedAt = null;
    // 2. Re-bind public streams to the (now) active — playingStream stays
    //    `true` continuously because new active was already playing.
    _bindActivePlayerStreams();
    _emitCurrentSong();
    // 3. Now quiesce the previously-active player (now idle). Its
    //    playingStream may emit `false` but no one's listening to it.
    await oldActive.setVolume(0);
    await oldActive.pause();
  }

  /// Cancel any in-flight crossfade. `snapToActive=true` means restore the
  /// (current) active to full volume + leave the index alone — used when
  /// crossfade gets disabled mid-ramp. `snapToActive=false` means complete
  /// the swap instantly — used for manual skips during a ramp.
  void _cancelCrossfade({required bool snapToActive}) {
    _crossfadeTimer?.cancel();
    _crossfadeTimer = null;
    _rampStartTimer?.cancel();
    _rampStartTimer = null;
    _crossfadeStartedAt = null;
    _crossfadeInProgress = false;
    _crossfadeKickedForCurrent = false;
    _idlePrewarmed = false;
    if (snapToActive) {
      _active.setVolume(100);
      _idle.stop();
    }
  }

  // ── Refresh action (URL refresh scheduler callback) ───────────────────
  // Reload the active player's current track via a fresh open so the on_load
  // hook fires with forceRefresh=true. Position survives via the one-shot
  // _pendingStartPosition. Defers if paused — same rationale as before
  // (avoid resuming playback as a side-effect).
  Future<void> _refreshCurrentTrack() async {
    if (_currentIndex < 0 || _currentIndex >= _queue.length) return;
    if (!_active.state.playing) {
      debugPrint('[url-refresh] paused — deferring');
      return;
    }
    final song = _queue[_currentIndex];
    final pos = _active.state.position;
    debugPrint('[url-refresh] swap ${song.id} @ ${pos.inSeconds}s');
    _pendingStartPosition = pos;
    _forceRefreshNextResolve = true;
    try {
      await _active.open(Media(_placeholderFor(song)), play: true);
    } catch (e) {
      debugPrint('[url-refresh] swap failed: $e');
      _pendingStartPosition = null;
      _forceRefreshNextResolve = false;
    }
  }

  // ── Public surface — driven by AudioRepo ──────────────────────────────

  String _placeholderFor(FeedItem song) =>
      '$_placeholderScheme${Uri.encodeComponent(song.id)}';

  Future<void> setQueue(List<FeedItem> songs, int startIndex) async {
    if (songs.isEmpty) return;
    debugPrint('[audio] setQueue len=${songs.length} startIndex=$startIndex');
    _updateQueue(songs);
    _currentIndex = startIndex.clamp(0, songs.length - 1);
    _loadFailRetries.clear();
    _cancelCrossfade(snapToActive: true);
    await _active.setVolume(100);
    await _idle.stop();
    await _active.open(Media(_placeholderFor(songs[_currentIndex])), play: true);
    _emitCurrentSong();
  }

  Future<void> prepareQueue(
    List<FeedItem> songs,
    int startIndex, {
    Duration? seekTo,
  }) async {
    if (songs.isEmpty) return;
    debugPrint('[audio] prepareQueue len=${songs.length} idx=$startIndex '
        'seek=${seekTo?.inSeconds}s');
    _updateQueue(songs);
    _currentIndex = startIndex.clamp(0, songs.length - 1);
    _loadFailRetries.clear();
    _cancelCrossfade(snapToActive: true);
    _pendingStartPosition = seekTo;
    await _active.setVolume(100);
    await _idle.stop();
    await _active.open(Media(_placeholderFor(songs[_currentIndex])),
        play: false);
    _emitCurrentSong();
  }

  /// Cross-cutting "go to index N" used by skipToNext/Previous/jumpTo and
  /// the auto-advance path. Cancels any crossfade — the caller decides
  /// whether to bypass-via-snap or simply load.
  Future<void> _advanceTo(int newIndex, {required bool play}) async {
    if (newIndex < 0 || newIndex >= _queue.length) return;
    _crossfadeKickedForCurrent = false;
    _idlePrewarmed = false;
    _currentIndex = newIndex;
    await _idle.stop();
    await _active.setVolume(100);
    await _active.open(Media(_placeholderFor(_queue[newIndex])), play: play);
    _emitCurrentSong();
  }

  Future<void> play() async {
    // Resume both — if we paused during a ramp, idle is also paused.
    if (_crossfadeInProgress) await _idle.play();
    await _active.play();
  }

  Future<void> pause() async {
    await _active.pause();
    if (_crossfadeInProgress) await _idle.pause();
  }

  Future<void> seek(Duration position) => _active.seek(position);

  Future<void> stop() async {
    _cancelCrossfade(snapToActive: true);
    await _active.stop();
    await _idle.stop();
  }

  Future<void> skipToNext() async {
    _userInitiatedSkip = true;
    if (_crossfadeInProgress) {
      // Snap the in-flight ramp to completion: new active = previous idle,
      // index already advances by 1 via the same swap mechanism.
      _cancelCrossfade(snapToActive: false);
      final newActive = _idle;
      await _active.setVolume(0);
      await _active.pause();
      _activeIsA = !_activeIsA;
      await newActive.setVolume(100);
      _currentIndex++;
      _bindActivePlayerStreams();
      _emitCurrentSong();
      _userInitiatedSkip = false;
      return;
    }
    if (_currentIndex + 1 >= _queue.length) {
      await stop();
      _userInitiatedSkip = false;
      return;
    }
    await _advanceTo(_currentIndex + 1, play: true);
    _userInitiatedSkip = false;
  }

  Future<void> skipToPrevious() async {
    _userInitiatedSkip = true;
    _cancelCrossfade(snapToActive: true);
    if (_currentIndex <= 0) {
      await _active.seek(Duration.zero);
      _userInitiatedSkip = false;
      return;
    }
    await _advanceTo(_currentIndex - 1, play: true);
    _userInitiatedSkip = false;
  }

  Future<void> jumpTo(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _userInitiatedSkip = true;
    _cancelCrossfade(snapToActive: true);
    await _advanceTo(index, play: true);
    _userInitiatedSkip = false;
  }

  Future<void> removeAt(int index) async {
    if (index < 0 || index >= _queue.length) return;
    final wasCurrent = index == _currentIndex;
    final next = [..._queue]..removeAt(index);
    _updateQueue(next);
    if (index < _currentIndex) {
      _currentIndex--;
    } else if (wasCurrent) {
      // Removing the currently-playing entry — stay at the same logical
      // index (which now points to what was the next track). If we just
      // removed the last entry, stop.
      if (next.isEmpty) {
        await stop();
        _emitCurrentSong();
        return;
      }
      if (_currentIndex >= next.length) _currentIndex = next.length - 1;
      _cancelCrossfade(snapToActive: true);
      await _idle.stop();
      await _active.setVolume(100);
      await _active
          .open(Media(_placeholderFor(next[_currentIndex])), play: true);
    }
    _emitCurrentSong();
  }

  Future<void> moveItem(int oldIndex, int newIndex) async {
    if (oldIndex < 0 ||
        newIndex < 0 ||
        oldIndex >= _queue.length ||
        newIndex >= _queue.length ||
        oldIndex == newIndex) {
      return;
    }
    final next = [..._queue];
    final item = next.removeAt(oldIndex);
    next.insert(newIndex, item);
    _updateQueue(next);
    // Keep _currentIndex pointing at the same FeedItem.
    final currentSong = _queue[_currentIndex]; // pre-move snapshot
    final newCurrentIndex = next.indexWhere((s) => s.id == currentSong.id);
    if (newCurrentIndex >= 0) _currentIndex = newCurrentIndex;
    _emitCurrentSong();
  }

  Future<void> clearQueue() async {
    _updateQueue(const []);
    _currentIndex = 0;
    _loadFailRetries.clear();
    _cancelCrossfade(snapToActive: true);
    await _active.stop();
    await _idle.stop();
    _emitCurrentSong();
  }

  // ── DSP / 10-band graphic equalizer (applied to BOTH players) ─────────
  // The crossfade overlap means both players output audio simultaneously
  // for N seconds. If we only EQ'd one, the overlap would have the new
  // track dry and the old track filtered — audible color shift mid-fade.
  static const eqFrequencies = [
    31, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000,
  ];

  Future<void> setEqBands(List<double> gains) async {
    assert(gains.length == eqFrequencies.length,
        'expected ${eqFrequencies.length} bands, got ${gains.length}');
    final anyNonZero = gains.any((g) => g.abs() > 0.001);

    // mpv only knows a handful of native af filters (format, lavfi, pan,
    // rubberband, scaletempo). FFmpeg filters like bass/equalizer/treble
    // MUST be prefixed with `lavfi-` or mpv silences the entire output —
    // see the package's BassSettings.toFilterString for the canonical
    // serializer.
    final filters = <String>[];
    if (anyNonZero) {
      for (var i = 0; i < eqFrequencies.length; i++) {
        final g = gains[i].toStringAsFixed(3);
        final f = eqFrequencies[i];
        if (i == 0) {
          filters.add('lavfi-bass=f=$f:width_type=q:width=1.2:g=$g');
        } else if (i == eqFrequencies.length - 1) {
          filters.add('lavfi-treble=f=$f:width_type=q:width=1.2:g=$g');
        } else {
          filters.add('lavfi-equalizer=f=$f:width_type=q:width=1.2:g=$g');
        }
      }
    }
    // Apply to BOTH players — keeps the crossfade overlap consistent.
    await Future.wait([
      for (final p in [_a, _b])
        p.updateAudioEffects((e) => e.copyWith(
              custom: filters,
              superequalizer: const SuperequalizerSettings(enabled: false),
            )),
    ]);
  }

  // ── Cleanup ────────────────────────────────────────────────────────────

  Future<void> dispose() async {
    _urlRefresh.dispose();
    _crossfadeTimer?.cancel();
    _activePosSub?.cancel();
    _activePlayingSub?.cancel();
    for (final s in _subs) {
      await s.cancel();
    }
    await Future.wait([_a.dispose(), _b.dispose()]);
    await _positionCtl.close();
    await _playingCtl.close();
    await _currentSongCtl.close();
  }
}
