// Single-player audio handler.
//
// One mpv `Player` instance. Handler owns the queue + current index; on
// natural EOF of the active track we just call `Player.open(next, play:
// true)` — small (~100-300 ms) load gap between tracks, but rock-solid.
//
// The two-player musical-chairs architecture this used to be was ripped
// out 2026-05-26 (along with the crossfade setting). The crossfade path
// itself worked, but the gapless variant (crossfade=0) had a long tail
// of race conditions — pre-warm not confirming, idle leaks, swap timing
// mismatch — and the user opted to remove the feature entirely rather
// than keep iterating on it. If you want crossfade back later, the git
// history at 2026-05-26 still has the working two-player implementation.
//
// **Manual skips** load the target on the active player immediately — a
// tap should feel instant.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../api/dto.dart';
import '../api/stream_resolver.dart';
import 'url_refresh.dart';

/// Placeholder scheme — mpv asks us to resolve this in the on_load hook.
const _placeholderScheme = 'sunoh-song://';

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

  // ── Handler-level queue ────────────────────────────────────────────────
  // mpv plays one track at a time; the queue lives here and we drive
  // advance / skip / shuffle from this side.
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

  /// Emits when the on_load resolver enriches the currently-playing song
  /// with metadata that wasn't in the original FeedItem. Distinct from
  /// [currentSongStream] (which only fires on a NEW song id) — same id +
  /// fuller data goes here. AppState listens and re-runs `_applySong`
  /// with the merged payload.
  final StreamController<FeedItem> _enrichedCurrentSongCtl =
      StreamController<FeedItem>.broadcast();

  Stream<FeedItem> get enrichedCurrentSongStream =>
      _enrichedCurrentSongCtl.stream;

  /// Merge enriched fields onto the queue entry for [songId] in place. If
  /// it's the currently-playing index, also broadcast the merged item via
  /// [enrichedCurrentSongStream].
  void _mergeSongMetadata(String songId, FeedItem enriched) {
    final idx = _queue.indexWhere((s) => s.id == songId);
    if (idx < 0) return;
    final old = _queue[idx];
    final merged = FeedItem(
      id: old.id,
      // Keep title/type/source/url from the original — search responses
      // sometimes have a more user-recognisable title than the canonical
      // backend record. Everything else takes the enriched value when
      // present (search has nulls / empties for these).
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
      stationType: old.stationType, // never enriched — radio-specific
      mediaUrls:
          enriched.mediaUrls.isNotEmpty ? enriched.mediaUrls : old.mediaUrls,
    );
    final next = [..._queue]..[idx] = merged;
    _updateQueue(next);
    if (idx == _currentIndex) {
      _enrichedCurrentSongCtl.add(merged);
    }
  }

  // ── Public streams ─────────────────────────────────────────────────────
  // Re-broadcast the player's streams through our own controllers so any
  // future changes to internals don't break consumers. Bound once at
  // construction; no rebinding needed in the single-player world.
  final StreamController<Duration> _positionCtl =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _durationCtl =
      StreamController<Duration>.broadcast();
  final StreamController<bool> _playingCtl =
      StreamController<bool>.broadcast();
  final StreamController<FeedItem?> _currentSongCtl =
      StreamController<FeedItem?>.broadcast();

  Stream<Duration> get positionStream => _positionCtl.stream;
  Stream<Duration> get durationStream => _durationCtl.stream;
  Stream<bool> get playingStream => _playingCtl.stream;
  Stream<FeedItem?> get currentSongStream =>
      _currentSongCtl.stream.distinct((a, b) => a?.id == b?.id);

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

  // ── URL refresh / on_load hook state ──────────────────────────────────
  late final UrlRefreshScheduler _urlRefresh;

  /// One-shot start-position consumed by the next on_load hook. Used for
  /// cross-session restore and the URL-refresh reload.
  Duration? _pendingStartPosition;

  /// One-shot: when set, the next on_load hook calls resolve with
  /// forceRefresh=true so embedded (stale) mediaUrls are bypassed.
  bool _forceRefreshNextResolve = false;

  final Map<String, int> _loadFailRetries = {};
  static const _maxRetries = 2;

  /// Last position emitted by the player's tick stream. Used by the
  /// premature-EOF guard in [_onEndFile]: at the moment mpv fires endFile,
  /// `player.state.position` is often already reset toward 0, which would
  /// make a perfectly natural end-of-file look "premature" and incorrectly
  /// trigger a URL refresh. The last *tick* is closer to duration on a
  /// genuine natural end.
  Duration _lastPosition = Duration.zero;

  /// User-intent flag: did the user *want* to be playing right now?
  /// NOT the same as `_player.state.playing` — at the moment of a load
  /// error mpv reports `playing: false` even if the user just tapped
  /// play. The URL refresh path uses this to know "should I resume after
  /// the reload?".
  bool _userPlaying = false;

  // ── Next-track pre-resolve ─────────────────────────────────────────────
  // When the current track has ≤ 15 s remaining, fire-and-forget a resolve
  // for the upcoming track. The resolver caches the URL by song id with
  // an expiry-aware TTL, so the on_load hook for `_advanceTo` hits a fresh
  // cached URL (no network round-trip) → transitions feel ~instant. If
  // the cached URL is somehow stale by the time it's used (paused-queue
  // scenarios), the resolver's TTL check forces a re-resolve.
  static const _kNextPreResolveLead = Duration(seconds: 15);
  bool _nextPreResolveKicked = false;

  // ── Subscriptions ──────────────────────────────────────────────────────
  final List<StreamSubscription<dynamic>> _subs = [];

  void _wirePlayerStreams() {
    _subs.add(_player.stream.position.listen((p) {
      _lastPosition = p;
      _positionCtl.add(p);
      _maybePreResolveNext(p);
    }));
    _subs.add(_player.stream.duration.listen(_durationCtl.add));
    _subs.add(_player.stream.playbackState.listen((s) {
      _playingCtl.add(s == MpvPlaybackState.playing);
    }));
    // Canonical "natural end-of-file → advance queue" signal per the
    // mpv_audio_kit docs (MpvPlaybackState.completed comment: "Reached
    // natural end-of-file. Advance the queue here."). The separate
    // endFile event is too ambiguous — it fires for stop / error /
    // premature network-drop too, all marked as `eof` reason.
    _subs.add(_player.stream.completed.listen(_onCompleted));
    // Belt-and-suspenders: `eofReached` mirrors mpv's `eof-reached`
    // property directly. With `keep-open=no` we set above, the regular
    // endFile/completed signals fire reliably — but if the package
    // version ever changes behaviour, `eofReached` is the lowest-level
    // signal and still tells us when mpv has run out of file.
    _subs.add(_player.stream.eofReached.listen((reached) {
      // ignore: avoid_print
      print('[audio] eofReached=$reached');
      if (reached) _handleNaturalOrPremature(reason: 'eof-reached');
    }));
    _subs.add(_player.stream.error.listen(_onError));
    _subs.add(_player.stream.log.listen((entry) {
      final prefix = entry.prefix.toLowerCase();
      if (prefix == 'ao' ||
          prefix == 'demux' ||
          prefix == 'ffmpeg' ||
          prefix == 'cplayer' ||
          entry.level == LogLevel.error ||
          entry.level == LogLevel.fatal) {
        debugPrint(
            '[mpv/${entry.prefix}] ${entry.level.name}: ${entry.text}');
      }
    }));
    _subs.add(_player.stream.hook.listen(_onHook));
    // endFile is now ONLY used for premature-EOF detection — network drop
    // mid-stream reports as `eof` (not `error`), and the natural-end
    // branch is handled by [_onCompleted] instead.
    _subs.add(_player.stream.endFile.listen(_onEndFile));
    // URL refresh cancels itself whenever the active track changes.
    _subs.add(currentSongStream.listen((_) => _urlRefresh.cancel()));
  }

  /// Fire-and-forget the next track's resolve as the current track nears
  /// its end. Warms the resolver's URL cache so `_advanceTo`'s on_load
  /// hook (which is on the critical-path the user perceives as gap) hits
  /// a cached URL instead of waiting on `/music/song/:id`. Saves 300–800
  /// ms of perceived gap between tracks.
  void _maybePreResolveNext(Duration pos) {
    if (_nextPreResolveKicked) return;
    if (_currentIndex + 1 >= _queue.length) return;
    final dur = _player.state.duration;
    if (dur <= Duration.zero) return;
    if (dur - pos > _kNextPreResolveLead) return;
    _nextPreResolveKicked = true;
    final next = _queue[_currentIndex + 1];
    debugPrint('[audio] pre-resolving next "${next.title}" '
        '(${(dur - pos).inSeconds}s remaining)');
    unawaited(resolver.resolve(next).catchError((e) {
      // Pre-resolve is best-effort — failure here just means the on_load
      // hook will hit the network when the track auto-advances. Not fatal.
      debugPrint('[audio] pre-resolve failed: $e');
      return ResolvedStream(''); // dummy — we don't use the value
    }));
  }

  Future<void> _applyAudioOutputTuning() async {
    try {
      await _player.setAudioBuffer(const Duration(milliseconds: 500));
      // Gapless OFF — we don't use mpv's internal playlist (the queue
      // lives at the handler level), and `Gapless.yes` tells mpv to wait
      // at EOF for the next playlist entry, which can suppress the
      // `completed` signal we use to detect natural end-of-track.
      await _player.setGapless(Gapless.no);
      // CRITICAL: override `keep-open=yes` (which mpv_audio_kit sets at
      // init in player.dart:613) → `no`. With `keep-open=yes` mpv pauses
      // at EOF and never closes the file, so no `endFile` event fires
      // and `completed` never goes true → our auto-advance signal never
      // arrives and playback just sits stuck at `-0:01`.
      await _player.setRawProperty('keep-open', 'no');
    } catch (e) {
      debugPrint('[audio] tuning failed: $e');
    }
  }

  // ── on_load hook ───────────────────────────────────────────────────────
  Future<void> _onHook(MpvHookEvent event) async {
    if (event.hook != Hook.load) {
      _player.continueHook(event.id);
      return;
    }
    try {
      final raw = await _player.getRawProperty('stream-open-filename') ?? '';
      if (!raw.startsWith(_placeholderScheme)) return;
      final encoded = raw.substring(_placeholderScheme.length);
      final id = Uri.decodeComponent(encoded);
      final song = _queue.firstWhere(
        (s) => s.id == id,
        orElse: () => const FeedItem(id: '', title: '', type: '', image: []),
      );
      if (song.id.isEmpty) {
        debugPrint('[audio] hook: no song in queue for id "$id"');
        return;
      }
      final fresh = _forceRefreshNextResolve;
      _forceRefreshNextResolve = false;
      debugPrint(
          '[audio] hook resolving ${song.id}${fresh ? ' (forceRefresh)' : ''}');
      final resolved = await resolver.resolve(song, forceRefresh: fresh);
      debugPrint('[audio] hook resolved → ${resolved.url}');
      await _player.setRawProperty('stream-open-filename', resolved.url);
      // Backfill the queue item with the richer metadata that came along
      // with the resolve (search responses leave artists / duration /
      // subtitle empty; /music/song/:id has them all).
      if (resolved.enriched != null) {
        _mergeSongMetadata(song.id, resolved.enriched!);
      }

      // One-shot start position for restore / URL-refresh paths.
      final start = _pendingStartPosition;
      if (start != null && start.inMilliseconds > 0) {
        debugPrint('[audio] hook applying start=${start.inSeconds}s');
        await _player.setRawProperty(
          'file-local-options/start',
          start.inSeconds.toString(),
        );
        _pendingStartPosition = null;
      }

      _urlRefresh.schedule(songId: song.id, resolvedUrl: resolved.url);
    } catch (e) {
      debugPrint('[audio] hook failed: $e');
    } finally {
      _player.continueHook(event.id);
    }
  }

  void _onError(MpvPlayerError err) {
    debugPrint('[mpv error] $err');
    if (err is! MpvEndFileError || !err.isLoadingError) return;
    if (_currentIndex < 0 || _currentIndex >= _queue.length) return;

    final song = _queue[_currentIndex];
    final tries = _loadFailRetries[song.id] ?? 0;
    if (tries >= _maxRetries) {
      debugPrint('[audio] giving up on ${song.id} after $tries retries');
      _loadFailRetries.remove(song.id);
      // Auto-skip ONLY when the user intended to play. Don't skip while
      // paused — on app launch we pre-load the queue via
      // prepareQueue(play:false) for restore; if every URL is stale we'd
      // otherwise burn through the whole queue silently before the user
      // even hit play.
      if (_userPlaying && _currentIndex + 1 < _queue.length) {
        unawaited(_advanceTo(_currentIndex + 1, play: true));
      }
      return;
    }
    _loadFailRetries[song.id] = tries + 1;
    debugPrint('[audio] load error for ${song.id} '
        '(try ${tries + 1}/$_maxRetries) — force-refreshing URL');
    unawaited(_refreshCurrentTrack());
  }

  /// Track id we last fired `_onCompleted` / `_onEndFile` for — used to
  /// dedupe (mpv fires both `completed=true` and `endFile reason=eof` at
  /// roughly the same time; we want to react once).
  String? _lastTerminatedSongId;

  /// Canonical end-of-file handler — fires both for natural completion
  /// AND for mid-stream network drops (mpv reports both as eof). We
  /// differentiate by position:
  ///   • near end of duration   → advance to next track
  ///   • far short of duration  → premature drop → URL refresh
  ///
  /// Wired via `_player.stream.completed` (same trigger as endFile-with-
  /// eof but exposed as a boolean stream). `_onEndFile` is kept around
  /// purely for diagnostic logging of non-eof reasons (stop / error /
  /// redirect / quit) and as a safety-net invocation of this same path.
  void _onCompleted(bool completed) {
    // ignore: avoid_print
    print('[audio] completed=$completed (idx=$_currentIndex)');
    if (!completed) return;
    _handleNaturalOrPremature(reason: 'completed-stream');
  }

  /// Network-drop / premature-EOF detection. mpv reports mid-stream
  /// disconnects with `MpvEndFileReason.eof` — most of the time we'll
  /// have already reacted via [_onCompleted], but if `completed` fails
  /// to emit for some reason this is the safety-net.
  void _onEndFile(MpvFileEndedEvent event) {
    // ignore: avoid_print
    print('[audio] endFile reason=${event.reason}');
    if (event.reason != MpvEndFileReason.eof) return;
    _handleNaturalOrPremature(reason: 'endFile-eof');
  }

  void _handleNaturalOrPremature({required String reason}) {
    if (_currentIndex < 0 || _currentIndex >= _queue.length) return;
    final song = _queue[_currentIndex];
    // Dedupe — both the completed stream and endFile event fire for the
    // same natural EOF; we only want one of them to drive the advance.
    if (song.id == _lastTerminatedSongId) {
      // ignore: avoid_print
      print('[audio] $reason: already handled for "${song.id}" — skip');
      return;
    }
    _lastTerminatedSongId = song.id;

    final dur = _player.state.duration;
    final pos = _lastPosition;
    // Premature if we never reached 90 % of duration AND we're ≥ 15 s
    // short. HLS streams (gaana .m3u8) stop ticking position a few
    // seconds before the actual end of the segment list, so a tight 3-s
    // window misfires on natural ends.
    final isPremature = dur > const Duration(seconds: 3) &&
        pos < dur - const Duration(seconds: 15) &&
        pos.inMilliseconds < (dur.inMilliseconds * 0.9).round();

    if (isPremature) {
      // ignore: avoid_print
      print('[audio] $reason: PREMATURE @ ${pos.inSeconds}/${dur.inSeconds}s '
          '— url-refresh');
      unawaited(_urlRefresh.triggerRefresh(reason: 'premature EOF'));
      return;
    }

    if (_currentIndex + 1 < _queue.length) {
      // ignore: avoid_print
      print('[audio] $reason: NATURAL @ ${pos.inSeconds}/${dur.inSeconds}s '
          '— advancing to idx ${_currentIndex + 1}');
      unawaited(_advanceTo(_currentIndex + 1, play: true));
    } else {
      // ignore: avoid_print
      print('[audio] $reason: NATURAL @ end of queue');
    }
  }

  // ── Refresh action (URL refresh scheduler callback) ───────────────────
  // Re-open the current track via a fresh resolve. Position survives via
  // `_pendingStartPosition`; play state via `_userPlaying`.
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

  Future<void> setQueue(List<FeedItem> songs, int startIndex) async {
    if (songs.isEmpty) return;
    debugPrint('[audio] setQueue len=${songs.length} startIndex=$startIndex');
    _updateQueue(songs);
    _currentIndex = startIndex.clamp(0, songs.length - 1);
    _loadFailRetries.clear();
    _originalQueue = null;
    _nextPreResolveKicked = false;
    _lastTerminatedSongId = null;
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
  }) async {
    if (songs.isEmpty) return;
    debugPrint('[audio] prepareQueue len=${songs.length} idx=$startIndex '
        'seek=${seekTo?.inSeconds}s');
    _updateQueue(songs);
    _currentIndex = startIndex.clamp(0, songs.length - 1);
    _loadFailRetries.clear();
    _nextPreResolveKicked = false;
    _lastTerminatedSongId = null;
    _userPlaying = false; // restore lands paused; user taps play to start
    _pendingStartPosition = seekTo;
    await _player.setVolume(100);
    await _player.open(
      Media(_placeholderFor(songs[_currentIndex])),
      play: false,
    );
    _emitCurrentSong();
  }

  /// Cross-cutting "go to index N" used by skipToNext/Previous/jumpTo and
  /// the auto-advance path.
  Future<void> _advanceTo(int newIndex, {required bool play}) async {
    if (newIndex < 0 || newIndex >= _queue.length) return;
    _currentIndex = newIndex;
    _nextPreResolveKicked = false; // fresh window for the new "next"
    _lastTerminatedSongId = null; // new track → fresh completion window
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
    // The "next" slot changed identity — let pre-resolve fire again on
    // the new occupant. Otherwise the old next track's cache would still
    // be the one consumed at advance time.
    _nextPreResolveKicked = false;
  }

  /// Append `song` to the end of the queue. If the queue is empty, starts
  /// a new one-song queue.
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
    final currentSong = _queue[_currentIndex]; // pre-move snapshot
    final newCurrentIndex = next.indexWhere((s) => s.id == currentSong.id);
    if (newCurrentIndex >= 0) _currentIndex = newCurrentIndex;
    _nextPreResolveKicked = false; // "next" may have changed identity
    _emitCurrentSong();
  }

  /// Shuffle / unshuffle the upcoming portion of the queue. The currently
  /// playing track stays put — only what's *after* it gets rearranged.
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
    _nextPreResolveKicked = false;
    _lastTerminatedSongId = null;
    await _player.stop();
    _emitCurrentSong();
  }

  // ── DSP / 10-band graphic equalizer ───────────────────────────────────
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
  }
}
