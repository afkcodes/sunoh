// Single-player audio handler — owns mpv, the queue, and the per-track
// lifecycle bookkeeping.
//
// ## Architecture
//
// One `Player` instance, one handler-level queue (`_queue` + `_currentIndex`).
// Public API surface stays stable so `AudioRepo` consumers don't need to
// adapt (`setQueue` / `play` / `skipToNext` / `setShuffle` / etc.).
//
// EOF handling is single-signal — we listen exclusively to mpv's
// `eof-reached` property (via `_player.stream.eofReached`). The other
// candidates (`endFile` event, `completed` reactive) all fire at roughly
// the same moment and we'd just have to dedupe, so picking the lowest-
// level one keeps the code surface small. Critical mpv option:
// `keep-open=no` — see [_applyAudioOutputTuning] for why.
//
// Per-track flags (last-position, terminated-id dedupe, pre-resolve
// kicked) are bundled into [_TrackLifecycle] so they all reset together
// on every track change. Adding a new "fires once per track" flag is
// then one line in that class, not "remember to update 5 call sites."
//
// **PlayMode** — `track` (default, finite content) vs `live` (internet-
// radio / ICY streams that never EOF naturally). EOF in live mode is
// always treated as a network drop → URL refresh of the same source.
// Live mode also disables pre-resolve, repeat, premature-EOF tolerance
// (none of those make sense for an infinite stream).
//
// **Repeat modes** — `off` / `all` / `one` consulted at natural EOF.
// Manual skips ignore repeat.
//
// **Local-source extension point** — the resolver consults
// [LocalSourceProvider] (tier-0) before going to the network, so the
// downloads feature can plug in offline files without touching the
// handler.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../api/dto.dart';
import '../api/stream_resolver.dart';
import '../state/app_state.dart' show LoopMode;
import 'url_refresh.dart';

/// Placeholder scheme — mpv asks us to resolve this in the on_load hook.
const _placeholderScheme = 'sunoh-song://';

/// What kind of content is on the queue. Branches several places in the
/// handler:
///   - [track]: finite tracks, EOF advances the queue (respecting repeat),
///     pre-resolve fires for the next entry, premature-EOF tolerance applies.
///   - [live]: continuous ICY / internet-radio streams. EOF means the
///     network dropped (these streams never end naturally); we just
///     re-resolve the same source. No pre-resolve, no repeat, no
///     premature-EOF tolerance.
enum PlayMode { track, live }

/// Per-track lifecycle bundle. Anything that needs to fire / dedupe once
/// per track lives here so the reset logic stays in one place. Adding a
/// new field then only needs the corresponding line in [reset].
class _TrackLifecycle {
  /// Last position emitted by the player's tick stream. Used by the
  /// premature-EOF guard — mpv often resets `state.position` to 0 by the
  /// time eofReached fires, but the last tick is close to duration on a
  /// genuine natural end.
  Duration lastPosition = Duration.zero;

  /// Track id we last fired the natural/premature handler for. Even
  /// though we only listen to one EOF signal now, mpv can still re-emit
  /// `eofReached: true` after a seek-past-end + immediate re-seek — the
  /// dedupe key keeps us idempotent.
  String? terminatedSongId;

  /// Set when pre-resolve has fired for the *current* track. Reset on
  /// each track change so each new "next" gets its own fire.
  bool preResolveKicked = false;

  void reset() {
    lastPosition = Duration.zero;
    terminatedSongId = null;
    preResolveKicked = false;
  }
}

class SunohAudioHandler {
  SunohAudioHandler({required this.resolver}) {
    debugPrint('[audio] SunohAudioHandler() constructing Player…');
    _player = _buildPlayer();
    _urlRefresh = UrlRefreshScheduler(refresh: _refreshCurrentTrack);
    debugPrint('[audio] Player constructed ✓');
    _wirePlayerStreams();
    unawaited(_applyAudioOutputTuning());
  }

  final StreamResolver resolver;

  // ── Player ─────────────────────────────────────────────────────────────
  late final Player _player;

  Player _buildPlayer() {
    final p = Player(
      configuration: const PlayerConfiguration(
        autoPlay: true,
        initialVolume: 100.0,
        logLevel: LogLevel.info,
      ),
    );
    p.registerHook(Hook.load, timeout: const Duration(seconds: 10));
    return p;
  }

  // ── Queue ──────────────────────────────────────────────────────────────
  List<FeedItem> _queue = const [];
  int _currentIndex = 0;

  /// Original (pre-shuffle) queue. Held only while shuffle is ON so we can
  /// restore the user's intended ordering when they toggle it OFF.
  List<FeedItem>? _originalQueue;

  final ValueNotifier<List<FeedItem>> _queueListenable =
      ValueNotifier<List<FeedItem>>(const []);
  ValueListenable<List<FeedItem>> get queueListenable => _queueListenable;
  List<FeedItem> get queue => _queueListenable.value;

  void _updateQueue(List<FeedItem> next) {
    _queue = next;
    _queueListenable.value = List.unmodifiable(next);
  }

  // ── Mode + repeat ──────────────────────────────────────────────────────
  PlayMode _playMode = PlayMode.track;
  PlayMode get playMode => _playMode;

  LoopMode _repeat = LoopMode.off;
  LoopMode get repeat => _repeat;

  /// Pushed from `AppState.cycleRepeat`. Repeat only affects the natural-
  /// EOF advance path; manual skips ignore it.
  void setRepeat(LoopMode mode) {
    _repeat = mode;
    debugPrint('[audio] repeat=$mode');
  }

  // ── Per-track lifecycle ────────────────────────────────────────────────
  final _TrackLifecycle _lifecycle = _TrackLifecycle();

  // ── Public streams ─────────────────────────────────────────────────────
  // Re-broadcast through our own controllers so consumers (AppState,
  // audio_service bridge) subscribe once and we can later change the
  // underlying source without breaking them.
  final StreamController<Duration> _positionCtl =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _durationCtl =
      StreamController<Duration>.broadcast();
  final StreamController<bool> _playingCtl =
      StreamController<bool>.broadcast();
  final StreamController<FeedItem?> _currentSongCtl =
      StreamController<FeedItem?>.broadcast();
  final StreamController<FeedItem> _enrichedCurrentSongCtl =
      StreamController<FeedItem>.broadcast();
  final StreamController<String?> _icyTitleCtl =
      StreamController<String?>.broadcast();

  Stream<Duration> get positionStream => _positionCtl.stream;
  Stream<Duration> get durationStream => _durationCtl.stream;
  Stream<bool> get playingStream => _playingCtl.stream;
  Stream<FeedItem?> get currentSongStream =>
      _currentSongCtl.stream.distinct((a, b) => a?.id == b?.id);

  /// Emits when the on_load resolver enriches the currently-playing song
  /// with metadata that wasn't in the original FeedItem.
  Stream<FeedItem> get enrichedCurrentSongStream =>
      _enrichedCurrentSongCtl.stream;

  /// ICY-stream "now playing" title, parsed from mpv's metadata events.
  /// Only meaningful in [PlayMode.live]. Emits null when the field clears
  /// or there's no ICY data.
  Stream<String?> get icyTitleStream => _icyTitleCtl.stream.distinct();

  void _emitCurrentSong() {
    if (_currentIndex < 0 || _currentIndex >= _queue.length) {
      _currentSongCtl.add(null);
    } else {
      _currentSongCtl.add(_queue[_currentIndex]);
    }
  }

  // ── Public surface getters ─────────────────────────────────────────────
  bool get isPlaying => _player.state.playing;
  Duration get position => _player.state.position;
  Duration get duration => _player.state.duration;
  int get currentIndex => _currentIndex;
  FeedItem? get currentSong {
    if (_currentIndex < 0 || _currentIndex >= _queue.length) return null;
    return _queue[_currentIndex];
  }

  // ── on_load + URL refresh state ────────────────────────────────────────
  late final UrlRefreshScheduler _urlRefresh;

  /// One-shot start position consumed by the next on_load hook. Used for
  /// restore + URL-refresh re-open.
  Duration? _pendingStartPosition;

  /// One-shot: when true, the next on_load resolve calls the resolver
  /// with `forceRefresh: true` (bypasses cache + inline mediaUrls).
  bool _forceRefreshNextResolve = false;

  final Map<String, int> _loadFailRetries = {};
  static const _maxRetries = 2;

  /// User-intent flag: did the user *want* to be playing right now?
  /// NOT the same as `_player.state.playing` — at the moment of a load
  /// error mpv reports `playing: false` even if the user just tapped
  /// play. The URL refresh path uses this to know "should I resume?".
  bool _userPlaying = false;

  // ── Pre-resolve ────────────────────────────────────────────────────────
  /// How far before EOF to fire the next track's resolver call. Warms the
  /// resolver's URL cache so the on_load hook for `_advanceTo` skips the
  /// network round-trip.
  static const _kNextPreResolveLead = Duration(seconds: 15);

  // ── Subscriptions ──────────────────────────────────────────────────────
  final List<StreamSubscription<dynamic>> _subs = [];

  void _wirePlayerStreams() {
    _subs.add(_player.stream.position.listen(_onPositionTick));
    _subs.add(_player.stream.duration.listen(_durationCtl.add));
    _subs.add(_player.stream.playbackState.listen((s) {
      _playingCtl.add(s == MpvPlaybackState.playing);
    }));
    // Single canonical EOF signal — see file header for the reasoning.
    _subs.add(_player.stream.eofReached.listen(_onEofReached));
    _subs.add(_player.stream.error.listen(_onError));
    _subs.add(_player.stream.log.listen(_onLog));
    _subs.add(_player.stream.hook.listen(_onHook));
    _subs.add(_player.stream.metadata.listen(_onMetadata));
    // URL refresh cancels itself whenever the active track changes.
    _subs.add(currentSongStream.listen((_) => _urlRefresh.cancel()));
  }

  void _onLog(MpvLogEntry entry) {
    final prefix = entry.prefix.toLowerCase();
    if (prefix == 'ao' ||
        prefix == 'demux' ||
        prefix == 'ffmpeg' ||
        prefix == 'cplayer' ||
        entry.level == LogLevel.error ||
        entry.level == LogLevel.fatal) {
      debugPrint('[mpv/${entry.prefix}] ${entry.level.name}: ${entry.text}');
    }
  }

  /// Parse `icy-title` (or `title` for some streams) out of mpv's
  /// metadata map. Only meaningful in [PlayMode.live].
  void _onMetadata(Map<String, String> meta) {
    if (_playMode != PlayMode.live) return;
    // ICY radio servers ship the current song in `icy-title`; some
    // streams use `title` instead. We prefer `icy-title` when both
    // exist (it's more specifically a "now playing" field).
    final title = meta['icy-title'] ?? meta['title'];
    _icyTitleCtl.add(title?.trim().isEmpty == true ? null : title);
  }

  Future<void> _applyAudioOutputTuning() async {
    try {
      await _player.setAudioBuffer(const Duration(milliseconds: 500));
      // Gapless OFF — we don't use mpv's internal playlist (the queue
      // lives here), and `Gapless.yes` tells mpv to wait at EOF for the
      // next playlist entry, suppressing the eof-reached signal we use
      // for auto-advance.
      await _player.setGapless(Gapless.no);
      // CRITICAL: override the package's default `keep-open=yes`
      // (mpv_audio_kit-0.2.1/lib/src/player/player.dart:613). With
      // `keep-open=yes` mpv pauses at the last frame and never closes
      // the file, so `eof-reached` never transitions to true and our
      // auto-advance never fires. Playback would stall at -0:01.
      await _player.setRawProperty('keep-open', 'no');
    } catch (e) {
      debugPrint('[audio] tuning failed: $e');
    }
  }

  // ── Position tick ──────────────────────────────────────────────────────
  void _onPositionTick(Duration pos) {
    _lifecycle.lastPosition = pos;
    _positionCtl.add(pos);
    if (_playMode == PlayMode.track) _maybePreResolveNext(pos);
  }

  /// Warm the resolver's URL cache for the upcoming track. Cheap +
  /// best-effort — failure here just means the on_load hook for
  /// `_advanceTo` will hit the network when the time comes.
  void _maybePreResolveNext(Duration pos) {
    if (_lifecycle.preResolveKicked) return;
    if (_currentIndex + 1 >= _queue.length) return;
    final dur = _player.state.duration;
    if (dur <= Duration.zero) return;
    if (dur - pos > _kNextPreResolveLead) return;
    _lifecycle.preResolveKicked = true;
    final next = _queue[_currentIndex + 1];
    debugPrint('[audio] pre-resolving next "${next.title}" '
        '(${(dur - pos).inSeconds}s remaining)');
    unawaited(resolver.resolve(next).catchError((e) {
      debugPrint('[audio] pre-resolve failed: $e');
      return ResolvedStream('');
    }));
  }

  // ── EOF handling ───────────────────────────────────────────────────────
  void _onEofReached(bool reached) {
    // ignore: avoid_print
    print('[audio] eofReached=$reached (mode=$_playMode idx=$_currentIndex)');
    if (!reached) return;
    if (_currentIndex < 0 || _currentIndex >= _queue.length) return;
    final song = _queue[_currentIndex];
    if (song.id == _lifecycle.terminatedSongId) {
      // ignore: avoid_print
      print('[audio] eofReached: already handled for "${song.id}"');
      return;
    }
    _lifecycle.terminatedSongId = song.id;

    if (_playMode == PlayMode.live) {
      // Live streams (ICY / internet radio) never end naturally — EOF
      // means the connection dropped. Refresh the same source rather
      // than advancing.
      // ignore: avoid_print
      print('[audio] eofReached live-stream — reconnecting');
      unawaited(_urlRefresh.triggerRefresh(reason: 'live stream EOF'));
      return;
    }

    final dur = _player.state.duration;
    final pos = _lifecycle.lastPosition;
    // Premature if we never reached 90 % of duration AND we're ≥ 15 s
    // short. HLS streams stop ticking position a few seconds before the
    // actual end of the segment list, so a tight 3 s window misfires.
    final isPremature = dur > const Duration(seconds: 3) &&
        pos < dur - const Duration(seconds: 15) &&
        pos.inMilliseconds < (dur.inMilliseconds * 0.9).round();

    if (isPremature) {
      // ignore: avoid_print
      print('[audio] eofReached PREMATURE @ ${pos.inSeconds}/${dur.inSeconds}s '
          '— url-refresh');
      unawaited(_urlRefresh.triggerRefresh(reason: 'premature EOF'));
      return;
    }

    // ignore: avoid_print
    print('[audio] eofReached NATURAL @ ${pos.inSeconds}/${dur.inSeconds}s '
        '— advancing via repeat=$_repeat');
    unawaited(_advanceForNaturalEof());
  }

  /// Decide what "next" means after a natural EOF, factoring in repeat
  /// mode. Manual skips bypass this — they always go to the literal next
  /// queue entry regardless of repeat.
  Future<void> _advanceForNaturalEof() async {
    if (_repeat == LoopMode.one) {
      // Repeat-one: re-seek the current track to zero. We re-open instead
      // of seeking because some HLS streams don't seek cleanly to 0
      // after EOF — open() is the reliable reset.
      final song = _queue[_currentIndex];
      debugPrint('[audio] repeat-one — restarting "${song.title}"');
      _userPlaying = true;
      _lifecycle.reset();
      await _player.open(Media(_placeholderFor(song)), play: true);
      return;
    }
    if (_currentIndex + 1 < _queue.length) {
      await _advanceTo(_currentIndex + 1, play: true);
      return;
    }
    // End of queue.
    if (_repeat == LoopMode.all && _queue.isNotEmpty) {
      debugPrint('[audio] repeat-all — wrapping to idx 0');
      await _advanceTo(0, play: true);
      return;
    }
    debugPrint('[audio] end of queue');
  }

  // ── Error / retry ──────────────────────────────────────────────────────
  void _onError(MpvPlayerError err) {
    debugPrint('[mpv error] $err');
    if (err is! MpvEndFileError || !err.isLoadingError) return;
    if (_currentIndex < 0 || _currentIndex >= _queue.length) return;

    final song = _queue[_currentIndex];
    final tries = _loadFailRetries[song.id] ?? 0;
    if (tries >= _maxRetries) {
      debugPrint('[audio] giving up on ${song.id} after $tries retries');
      _loadFailRetries.remove(song.id);
      // Auto-skip ONLY when the user intended to play. Don't burn through
      // the queue on a paused restore where every URL might be stale.
      if (_userPlaying &&
          _playMode == PlayMode.track &&
          _currentIndex + 1 < _queue.length) {
        unawaited(_advanceTo(_currentIndex + 1, play: true));
      }
      return;
    }
    _loadFailRetries[song.id] = tries + 1;
    debugPrint('[audio] load error for ${song.id} '
        '(try ${tries + 1}/$_maxRetries) — force-refresh');
    unawaited(_refreshCurrentTrack());
  }

  // ── on_load hook — decomposed into three small steps ──────────────────
  Future<void> _onHook(MpvHookEvent event) async {
    if (event.hook != Hook.load) {
      _player.continueHook(event.id);
      return;
    }
    try {
      final song = await _identifyLoadingSong();
      if (song == null) return;
      final resolved = await _resolveForHook(song);
      if (resolved == null) return;
      await _applyResolvedUrl(resolved.url);
      _mergeEnrichmentIfAny(song.id, resolved.enriched);
      await _applyPendingStartPosition();
      _urlRefresh.schedule(songId: song.id, resolvedUrl: resolved.url);
    } catch (e, st) {
      debugPrint('[audio] hook failed: $e\n$st');
    } finally {
      _player.continueHook(event.id);
    }
  }

  /// Read mpv's `stream-open-filename` and decode the placeholder back
  /// into a FeedItem from the queue.
  Future<FeedItem?> _identifyLoadingSong() async {
    final raw = await _player.getRawProperty('stream-open-filename') ?? '';
    if (!raw.startsWith(_placeholderScheme)) return null;
    final encoded = raw.substring(_placeholderScheme.length);
    final id = Uri.decodeComponent(encoded);
    final song = _queue.firstWhere(
      (s) => s.id == id,
      orElse: () => const FeedItem(id: '', title: '', type: '', image: []),
    );
    if (song.id.isEmpty) {
      debugPrint('[audio] hook: no song in queue for id "$id"');
      return null;
    }
    return song;
  }

  Future<ResolvedStream?> _resolveForHook(FeedItem song) async {
    final fresh = _forceRefreshNextResolve;
    _forceRefreshNextResolve = false;
    debugPrint('[audio] hook resolving ${song.id}'
        '${fresh ? ' (forceRefresh)' : ''}');
    try {
      final resolved = await resolver.resolve(song, forceRefresh: fresh);
      debugPrint('[audio] hook resolved → ${resolved.url}');
      return resolved;
    } catch (e) {
      debugPrint('[audio] hook resolve failed: $e');
      return null;
    }
  }

  Future<void> _applyResolvedUrl(String url) =>
      _player.setRawProperty('stream-open-filename', url);

  void _mergeEnrichmentIfAny(String songId, FeedItem? enriched) {
    if (enriched == null) return;
    _mergeSongMetadata(songId, enriched);
  }

  Future<void> _applyPendingStartPosition() async {
    final start = _pendingStartPosition;
    if (start == null || start.inMilliseconds <= 0) return;
    debugPrint('[audio] hook applying start=${start.inSeconds}s');
    await _player.setRawProperty(
      'file-local-options/start',
      start.inSeconds.toString(),
    );
    _pendingStartPosition = null;
  }

  /// Merge enriched fields onto the queue entry for [songId]. Title /
  /// type / source / station are NEVER overwritten — search responses
  /// sometimes have a more user-recognisable title than the canonical
  /// backend record, and station-type is radio-only metadata.
  void _mergeSongMetadata(String songId, FeedItem enriched) {
    final idx = _queue.indexWhere((s) => s.id == songId);
    if (idx < 0) return;
    final old = _queue[idx];
    final merged = FeedItem(
      id: old.id,
      title: old.title,
      type: old.type,
      source: old.source,
      url: enriched.url ?? old.url,
      image: enriched.image.length > old.image.length
          ? enriched.image
          : old.image,
      subtitle: (enriched.subtitle?.trim().isNotEmpty ?? false)
          ? enriched.subtitle
          : old.subtitle,
      language: (enriched.language?.trim().isNotEmpty ?? false)
          ? enriched.language
          : old.language,
      duration: (enriched.duration?.trim().isNotEmpty ?? false)
          ? enriched.duration
          : old.duration,
      songCount: enriched.songCount ?? old.songCount,
      playCount: enriched.playCount ?? old.playCount,
      releaseDate: enriched.releaseDate ?? old.releaseDate,
      artists: (enriched.artists ?? const []).isNotEmpty
          ? enriched.artists
          : old.artists,
      token: (enriched.token?.isNotEmpty ?? false) ? enriched.token : old.token,
      stationType: old.stationType,
      mediaUrls:
          enriched.mediaUrls.isNotEmpty ? enriched.mediaUrls : old.mediaUrls,
    );
    final next = [..._queue]..[idx] = merged;
    _updateQueue(next);
    if (idx == _currentIndex) {
      _enrichedCurrentSongCtl.add(merged);
    }
  }

  // ── URL refresh action (scheduler callback) ───────────────────────────
  Future<void> _refreshCurrentTrack() async {
    if (_currentIndex < 0 || _currentIndex >= _queue.length) return;
    final song = _queue[_currentIndex];
    final pos = _player.state.position;
    final shouldPlay = _userPlaying;
    debugPrint('[url-refresh] reload ${song.id} @ ${pos.inSeconds}s '
        'userPlaying=$shouldPlay');
    _pendingStartPosition = pos;
    _forceRefreshNextResolve = true;
    try {
      await _player.open(Media(_placeholderFor(song)), play: shouldPlay);
    } catch (e) {
      debugPrint('[url-refresh] reload failed: $e');
      _pendingStartPosition = null;
      _forceRefreshNextResolve = false;
    }
  }

  // ── Public surface — driven by AudioRepo ──────────────────────────────

  String _placeholderFor(FeedItem song) =>
      '$_placeholderScheme${Uri.encodeComponent(song.id)}';

  /// Replace the queue and start playing. [mode] defaults to
  /// [PlayMode.track]; pass [PlayMode.live] for internet-radio / ICY
  /// streams (changes EOF semantics + disables pre-resolve / repeat).
  Future<void> setQueue(
    List<FeedItem> songs,
    int startIndex, {
    PlayMode mode = PlayMode.track,
  }) async {
    if (songs.isEmpty) return;
    debugPrint('[audio] setQueue len=${songs.length} startIndex=$startIndex '
        'mode=$mode');
    _playMode = mode;
    _updateQueue(songs);
    _currentIndex = startIndex.clamp(0, songs.length - 1);
    _loadFailRetries.clear();
    _originalQueue = null;
    _lifecycle.reset();
    _icyTitleCtl.add(null);
    _userPlaying = true;
    await _player.setVolume(100);
    await _player.open(
      Media(_placeholderFor(songs[_currentIndex])),
      play: true,
    );
    _emitCurrentSong();
  }

  Future<void> prepareQueue(
    List<FeedItem> songs,
    int startIndex, {
    Duration? seekTo,
    PlayMode mode = PlayMode.track,
  }) async {
    if (songs.isEmpty) return;
    debugPrint('[audio] prepareQueue len=${songs.length} idx=$startIndex '
        'seek=${seekTo?.inSeconds}s mode=$mode');
    _playMode = mode;
    _updateQueue(songs);
    _currentIndex = startIndex.clamp(0, songs.length - 1);
    _loadFailRetries.clear();
    _lifecycle.reset();
    _icyTitleCtl.add(null);
    _userPlaying = false; // restore lands paused; user taps play to start
    _pendingStartPosition = seekTo;
    await _player.setVolume(100);
    await _player.open(
      Media(_placeholderFor(songs[_currentIndex])),
      play: false,
    );
    _emitCurrentSong();
  }

  /// Cross-cutting "go to index N" used by skipToNext/Previous/jumpTo
  /// and the natural-EOF advance path.
  Future<void> _advanceTo(int newIndex, {required bool play}) async {
    if (newIndex < 0 || newIndex >= _queue.length) return;
    _currentIndex = newIndex;
    _lifecycle.reset();
    _icyTitleCtl.add(null);
    if (play) _userPlaying = true;
    await _player.setVolume(100);
    await _player.open(
      Media(_placeholderFor(_queue[newIndex])),
      play: play,
    );
    _emitCurrentSong();
  }

  Future<void> play() async {
    _userPlaying = true;
    await _player.play();
    // Reset retry counter so a previously-exhausted track gets fresh
    // attempts on a deliberate user-initiated play.
    _loadFailRetries.clear();
  }

  Future<void> pause() async {
    _userPlaying = false;
    await _player.pause();
  }

  Future<void> seek(Duration position) => _player.seek(position);

  Future<void> stop() async {
    _userPlaying = false;
    await _player.stop();
  }

  Future<void> skipToNext() async {
    if (_currentIndex + 1 >= _queue.length) {
      // At end of queue: respect repeat-all by wrapping; otherwise stop.
      if (_repeat == LoopMode.all && _queue.isNotEmpty) {
        await _advanceTo(0, play: true);
        return;
      }
      await stop();
      return;
    }
    await _advanceTo(_currentIndex + 1, play: true);
  }

  Future<void> skipToPrevious() async {
    if (_currentIndex <= 0) {
      await _player.seek(Duration.zero);
      return;
    }
    await _advanceTo(_currentIndex - 1, play: true);
  }

  Future<void> jumpTo(int index) async {
    if (index < 0 || index >= _queue.length) return;
    await _advanceTo(index, play: true);
  }

  /// Insert `song` at `currentIndex + 1`. The "play next" context-menu
  /// action. If the queue is empty, falls back to starting a new one-
  /// song queue.
  Future<void> playNext(FeedItem song) async {
    if (_queue.isEmpty || _currentIndex < 0) {
      await setQueue([song], 0);
      return;
    }
    final next = [..._queue]..insert(_currentIndex + 1, song);
    _updateQueue(next);
    // The "next" slot changed identity — let pre-resolve fire again.
    _lifecycle.preResolveKicked = false;
  }

  /// Append `song` to the end of the queue. If the queue is empty,
  /// starts a new one-song queue.
  Future<void> addToQueue(FeedItem song) async {
    if (_queue.isEmpty || _currentIndex < 0) {
      await setQueue([song], 0);
      return;
    }
    final next = [..._queue, song];
    _updateQueue(next);
  }

  Future<void> removeAt(int index) async {
    if (index < 0 || index >= _queue.length) return;
    final wasCurrent = index == _currentIndex;
    final next = [..._queue]..removeAt(index);
    _updateQueue(next);
    if (index < _currentIndex) {
      _currentIndex--;
    } else if (wasCurrent) {
      if (next.isEmpty) {
        await stop();
        _emitCurrentSong();
        return;
      }
      if (_currentIndex >= next.length) _currentIndex = next.length - 1;
      _lifecycle.reset();
      await _player.setVolume(100);
      await _player.open(
        Media(_placeholderFor(next[_currentIndex])),
        play: true,
      );
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
    final currentSong = _queue[_currentIndex];
    final newCurrentIndex = next.indexWhere((s) => s.id == currentSong.id);
    if (newCurrentIndex >= 0) _currentIndex = newCurrentIndex;
    _lifecycle.preResolveKicked = false; // "next" may have changed
  }

  /// Shuffle / unshuffle the upcoming portion of the queue. The
  /// currently playing track stays put — only what's *after* gets
  /// rearranged.
  void setShuffle(bool enabled) {
    if (enabled) {
      if (_originalQueue != null) return;
      if (_queue.length <= _currentIndex + 1) return;
      _originalQueue = List<FeedItem>.from(_queue);
      final head = _queue.sublist(0, _currentIndex + 1);
      final tail = _queue.sublist(_currentIndex + 1)..shuffle();
      _updateQueue([...head, ...tail]);
      debugPrint('[shuffle] on — shuffled ${tail.length} upcoming tracks');
      return;
    }
    final orig = _originalQueue;
    if (orig == null) return;
    final currentId = _queue[_currentIndex].id;
    final restoredIdx = orig.indexWhere((s) => s.id == currentId);
    _originalQueue = null;
    if (restoredIdx < 0) {
      debugPrint('[shuffle] off — current song missing from original; '
          'leaving queue as-is');
      return;
    }
    _currentIndex = restoredIdx;
    _updateQueue(List<FeedItem>.from(orig));
    debugPrint('[shuffle] off — restored original order '
        '(idx anchored to current song at $restoredIdx)');
  }

  Future<void> clearQueue() async {
    _updateQueue(const []);
    _currentIndex = 0;
    _loadFailRetries.clear();
    _originalQueue = null;
    _lifecycle.reset();
    _icyTitleCtl.add(null);
    await _player.stop();
    _emitCurrentSong();
  }

  // ── 10-band graphic EQ ────────────────────────────────────────────────
  static const eqFrequencies = [
    31, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000,
  ];

  Future<void> setEqBands(List<double> gains) async {
    assert(gains.length == eqFrequencies.length,
        'expected ${eqFrequencies.length} bands, got ${gains.length}');
    final anyNonZero = gains.any((g) => g.abs() > 0.001);

    // FFmpeg filters (bass / equalizer / treble) MUST be prefixed with
    // `lavfi-` — see the package's BassSettings.toFilterString. Without
    // the prefix mpv silences the entire output.
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
    await _player.updateAudioEffects((e) => e.copyWith(
          custom: filters,
          superequalizer: const SuperequalizerSettings(enabled: false),
        ));
  }

  // ── Cleanup ────────────────────────────────────────────────────────────
  Future<void> dispose() async {
    _urlRefresh.dispose();
    for (final s in _subs) {
      await s.cancel();
    }
    await _player.dispose();
    await _positionCtl.close();
    await _durationCtl.close();
    await _playingCtl.close();
    await _currentSongCtl.close();
    await _enrichedCurrentSongCtl.close();
    await _icyTitleCtl.close();
  }
}
