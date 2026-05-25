// Single-player audio handler driving mpv's INTERNAL playlist.
//
// ## Architecture
//
// We hand the whole queue to mpv via `Player.openAll(...)` and let mpv
// auto-advance through it natively. The package documents this as the
// supported pattern (see `example/lib/services/audio_handler.dart` in
// the mpv_audio_kit package — its handler is a thin wrapper around
// mpv's playlist API). Our `AudioRepo` consumers see the same public
// surface as before; mpv just does more of the work internally.
//
// **Why this layout** (was handler-side queue + manual advance):
//   - mpv's playlist auto-advance fires `MPV_EVENT_END_FILE`+`start-file`
//     for the next entry natively; no manual EOF→advance code needed.
//   - `setPrefetchPlaylist(true)` opens the next track's demuxer before
//     the current finishes → gapless transitions for free.
//   - Repeat (`setLoop(Loop.{off,file,playlist})`) and shuffle
//     (`setShuffle(bool)`) are native mpv operations, not handler
//     bookkeeping.
//   - The `eof-reached` property + `keep-open=yes` package default work
//     the way they were designed to (paused-at-end for single-file
//     playback); we don't fight them anymore.
//
// **What stays the same**:
//   - The `on_load` hook for JIT URL resolution. Each playlist entry
//     uses our `sunoh-song://` placeholder URI; on_load resolves it.
//   - `UrlRefreshScheduler` + the resolver cache. Per-track signed-URL
//     expiry handling is unchanged. Mid-track refresh now uses
//     `player.replace(currentIndex, media)` which the docs document as
//     prefetch-driven (gapless) when index == current.
//   - `StreamResolver.localSource` (downloads extension seam) and
//     `PlayMode.track` vs `.live` (internet-radio mode).
//
// **PlayMode.live** semantics:
//   - Single-entry "playlist": just `open(media)` (no `openAll`).
//   - mpv has no next track to advance to. `endFile` with `reason=eof`
//     means the live source dropped → URL refresh, same source.
//   - Repeat / prefetch are irrelevant in live mode.
//   - `metadata` events carry the ICY `icy-title` for the now-playing
//     stream, surfaced via `icyTitleStream`.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../api/dto.dart';
import '../api/stream_resolver.dart';
import '../state/app_state.dart' show LoopMode;
import 'url_refresh.dart';

/// Placeholder scheme — mpv asks us to resolve this in the on_load hook.
const _placeholderScheme = 'sunoh-song://';

/// Track-content type. Branches several places in the handler:
///   - [track]: finite content, mpv's internal playlist drives advance,
///     pre-resolve fires for the next entry, repeat modes apply.
///   - [live]: continuous ICY / internet-radio stream. Single-entry mode
///     (no `openAll`); EOF means the source dropped → URL refresh; no
///     pre-resolve, no repeat.
enum PlayMode { track, live }

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

  // ── Queue mirror ───────────────────────────────────────────────────────
  // mpv's playlist is the source of truth for *order + current index*.
  // We mirror it as a `List<FeedItem>` so the UI / persistence can
  // consume the queue as typed entities. The mirror is updated reactively
  // from `stream.playlist`; never written directly.
  //
  // `_byId` is the FeedItem cache keyed by song id — when the playlist
  // stream emits a new list of Media URIs we look up each FeedItem here.
  // Populated by every queue-mutating method that takes a FeedItem.
  final Map<String, FeedItem> _byId = {};
  int _currentIndex = 0;

  final ValueNotifier<List<FeedItem>> _queueListenable =
      ValueNotifier<List<FeedItem>>(const []);
  ValueListenable<List<FeedItem>> get queueListenable => _queueListenable;
  List<FeedItem> get queue => _queueListenable.value;

  /// Decode a `sunoh-song://<id>` placeholder back to a song id.
  String? _idFromUri(String uri) {
    if (!uri.startsWith(_placeholderScheme)) return null;
    return Uri.decodeComponent(uri.substring(_placeholderScheme.length));
  }

  /// Convert a FeedItem to a `Media` carrying our placeholder URI. The
  /// real URL gets resolved in the on_load hook when mpv tries to open it.
  Media _toMedia(FeedItem song) {
    _byId[song.id] = song;
    return Media('$_placeholderScheme${Uri.encodeComponent(song.id)}');
  }

  /// Rebuild the queue mirror + current-index pointer from mpv's playlist.
  /// Wired to `stream.playlist`; ALSO called manually after any mutation
  /// where we want to read the updated state synchronously.
  void _syncFromPlaylist(Playlist pl) {
    final items = pl.items;
    final list = <FeedItem>[];
    for (final m in items) {
      final id = _idFromUri(m.uri);
      if (id == null) continue;
      final item = _byId[id];
      if (item != null) list.add(item);
    }
    _queueListenable.value = List.unmodifiable(list);
    final newIdx = pl.index;
    final indexChanged = newIdx != _currentIndex;
    _currentIndex = newIdx;
    if (indexChanged) {
      _icyTitleCtl.add(null); // new track → reset ICY title
      _emitCurrentSong();
    }
  }

  /// Emits when the on_load resolver enriches the currently-playing song
  /// with metadata that wasn't in the original FeedItem.
  final StreamController<FeedItem> _enrichedCurrentSongCtl =
      StreamController<FeedItem>.broadcast();

  Stream<FeedItem> get enrichedCurrentSongStream =>
      _enrichedCurrentSongCtl.stream;

  /// Merge enriched fields onto the queue entry for [songId]. Title /
  /// type / source / stationType are never overwritten — search responses
  /// sometimes have a more user-recognisable title than the canonical
  /// backend record.
  void _mergeSongMetadata(String songId, FeedItem enriched) {
    final old = _byId[songId];
    if (old == null) return;
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
    _byId[songId] = merged;
    // Re-emit the mirror so listeners see the enriched data.
    _syncFromPlaylist(_player.state.playlist);
    if (_byId[songId] != null &&
        _player.state.playlist.index >= 0 &&
        _player.state.playlist.index < _player.state.playlist.items.length) {
      final currentUri =
          _player.state.playlist.items[_player.state.playlist.index].uri;
      if (_idFromUri(currentUri) == songId) {
        _enrichedCurrentSongCtl.add(merged);
      }
    }
  }

  // ── Mode + repeat ──────────────────────────────────────────────────────
  PlayMode _playMode = PlayMode.track;
  PlayMode get playMode => _playMode;

  /// Pushed from `AppState.cycleRepeat`. Maps directly to mpv's `Loop`
  /// enum: off ↔ off, one ↔ file, all ↔ playlist.
  Future<void> setRepeat(LoopMode mode) async {
    final loop = switch (mode) {
      LoopMode.off => Loop.off,
      LoopMode.one => Loop.file,
      LoopMode.all => Loop.playlist,
    };
    debugPrint('[audio] repeat $mode → $loop');
    try {
      await _player.setLoop(loop);
    } catch (e) {
      debugPrint('[audio] setLoop failed: $e');
    }
  }

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
  final StreamController<String?> _icyTitleCtl =
      StreamController<String?>.broadcast();

  Stream<Duration> get positionStream => _positionCtl.stream;
  Stream<Duration> get durationStream => _durationCtl.stream;
  Stream<bool> get playingStream => _playingCtl.stream;
  Stream<FeedItem?> get currentSongStream =>
      _currentSongCtl.stream.distinct((a, b) => a?.id == b?.id);
  Stream<String?> get icyTitleStream => _icyTitleCtl.stream.distinct();

  void _emitCurrentSong() {
    if (_currentIndex < 0 || _currentIndex >= queue.length) {
      _currentSongCtl.add(null);
    } else {
      _currentSongCtl.add(queue[_currentIndex]);
    }
  }

  // ── Public surface getters ─────────────────────────────────────────────
  bool get isPlaying => _player.state.playing;
  Duration get position => _player.state.position;
  Duration get duration => _player.state.duration;
  int get currentIndex => _currentIndex;
  FeedItem? get currentSong {
    if (_currentIndex < 0 || _currentIndex >= queue.length) return null;
    return queue[_currentIndex];
  }

  // ── on_load + URL refresh state ────────────────────────────────────────
  late final UrlRefreshScheduler _urlRefresh;

  /// One-shot start position consumed by the next on_load hook (restore +
  /// URL-refresh paths).
  Duration? _pendingStartPosition;

  /// One-shot: when true, the next on_load resolve calls the resolver
  /// with `forceRefresh: true` (bypasses cache + inline mediaUrls).
  bool _forceRefreshNextResolve = false;

  /// User-intent flag for the URL-refresh resume decision. NOT the same
  /// as `_player.state.playing` — at the moment of a load error mpv
  /// reports `playing: false` even if the user just tapped play.
  bool _userPlaying = false;

  // ── Subscriptions ──────────────────────────────────────────────────────
  final List<StreamSubscription<dynamic>> _subs = [];

  void _wirePlayerStreams() {
    _subs.add(_player.stream.position.listen(_positionCtl.add));
    _subs.add(_player.stream.duration.listen(_durationCtl.add));
    _subs.add(_player.stream.playing.listen(_playingCtl.add));
    _subs.add(_player.stream.playlist.listen(_syncFromPlaylist));
    _subs.add(_player.stream.endFile.listen(_onEndFile));
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

  void _onMetadata(Map<String, String> meta) {
    if (_playMode != PlayMode.live) return;
    final title = meta['icy-title'] ?? meta['title'];
    _icyTitleCtl.add(title?.trim().isEmpty == true ? null : title);
  }

  /// One-shot mpv configuration applied after construction. Per the
  /// package's example app pattern: gapless on + prefetch on so the
  /// next playlist entry's demuxer is open before the current finishes.
  Future<void> _applyAudioOutputTuning() async {
    try {
      await _player.setAudioBuffer(const Duration(milliseconds: 500));
      // Gapless decoding across track boundaries.
      await _player.setGapless(Gapless.yes);
      // Pre-open the next playlist entry's demuxer while the current is
      // still playing → seamless auto-advance, no opening-thread stall
      // at the boundary.
      await _player.setPrefetchPlaylist(true);
      // ignore: avoid_print
      print('[audio] tuning applied: gapless=yes prefetch-playlist=yes '
          'audio-buffer=500ms');
    } catch (e) {
      // ignore: avoid_print
      print('[audio] tuning failed: $e');
    }
  }

  // ── EOF / error handling ──────────────────────────────────────────────
  //
  // With mpv's internal playlist driving auto-advance, the natural EOF
  // path is invisible to us — mpv just emits `start-file` for the next
  // entry. We only react to *abnormal* endings here:
  //   - `endFile reason=eof` mid-stream (position significantly short
  //     of duration) → network drop → URL refresh.
  //   - `endFile reason=eof` in PlayMode.live → stream dropped → refresh.
  //   - Hard load errors → retry up to 2× per song id.

  void _onEndFile(MpvFileEndedEvent event) {
    debugPrint('[audio] endFile reason=${event.reason}');
    if (event.reason != MpvEndFileReason.eof) return;

    if (_playMode == PlayMode.live) {
      // Live streams never end naturally — EOF means the connection
      // dropped. Refresh the same source.
      // ignore: avoid_print
      print('[audio] live stream EOF — reconnecting');
      unawaited(_urlRefresh.triggerRefresh(reason: 'live stream EOF'));
      return;
    }

    // Track mode: was this a natural end (mpv will auto-advance) or a
    // premature network drop? Compare position vs duration.
    final pos = _player.state.position;
    final dur = _player.state.duration;
    final isPremature = dur > const Duration(seconds: 3) &&
        pos < dur - const Duration(seconds: 15) &&
        pos.inMilliseconds < (dur.inMilliseconds * 0.9).round();

    if (isPremature) {
      // ignore: avoid_print
      print('[audio] PREMATURE EOF @ ${pos.inSeconds}/${dur.inSeconds}s '
          '— url-refresh');
      unawaited(_urlRefresh.triggerRefresh(reason: 'premature EOF'));
    } else {
      // Natural end — mpv's playlist auto-advance will handle it. The
      // playlist stream listener will emit the new currentSong.
      debugPrint(
          '[audio] natural EOF @ ${pos.inSeconds}/${dur.inSeconds}s (mpv auto-advances)');
    }
  }

  // Per-song-id retry counter for hard load errors.
  final Map<String, int> _loadFailRetries = {};
  static const _maxRetries = 2;

  void _onError(MpvPlayerError err) {
    debugPrint('[mpv error] $err');
    if (err is! MpvEndFileError || !err.isLoadingError) return;
    final song = currentSong;
    if (song == null) return;

    final tries = _loadFailRetries[song.id] ?? 0;
    if (tries >= _maxRetries) {
      debugPrint('[audio] giving up on ${song.id} after $tries retries');
      _loadFailRetries.remove(song.id);
      // In track mode mpv will auto-advance through the playlist on
      // playback failure (its own retry policy). In live mode there's
      // no next, so we just surface the failure.
      return;
    }
    _loadFailRetries[song.id] = tries + 1;
    debugPrint('[audio] load error for ${song.id} '
        '(try ${tries + 1}/$_maxRetries) — force-refresh');
    unawaited(_refreshCurrentTrack());
  }

  // ── on_load hook (decomposed) ─────────────────────────────────────────

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

  Future<FeedItem?> _identifyLoadingSong() async {
    final raw = await _player.getRawProperty('stream-open-filename') ?? '';
    final id = _idFromUri(raw);
    if (id == null) return null;
    final song = _byId[id];
    if (song == null) {
      debugPrint('[audio] hook: no song cached for id "$id"');
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

  // ── URL refresh action (scheduler callback) ───────────────────────────
  //
  // Per the package docs, `Player.replace(index, media)` swaps a playlist
  // entry. When `index == currentPos` the swap rides mpv's prefetch path
  // → gapless transition. Position survives via `_pendingStartPosition`.
  Future<void> _refreshCurrentTrack() async {
    final song = currentSong;
    if (song == null) return;
    final pos = _player.state.position;
    debugPrint('[url-refresh] reload ${song.id} @ ${pos.inSeconds}s');
    _pendingStartPosition = pos;
    _forceRefreshNextResolve = true;
    try {
      if (_playMode == PlayMode.live) {
        // Single-entry mode — re-open the same source. Honour user
        // intent (don't surprise-resume after a refresh if the user had
        // paused mid-stream).
        await _player.open(_toMedia(song), play: _userPlaying);
      } else {
        // Track mode: per docs, `replace(currentIndex, …)` inherits
        // mpv's prefetch-driven transition — the swap is gapless and
        // playing state is preserved automatically.
        await _player.replace(_currentIndex, _toMedia(song));
      }
    } catch (e) {
      debugPrint('[url-refresh] reload failed: $e');
      _pendingStartPosition = null;
      _forceRefreshNextResolve = false;
    }
  }

  // ── Public surface — driven by AudioRepo ──────────────────────────────

  Future<void> setQueue(
    List<FeedItem> songs,
    int startIndex, {
    PlayMode mode = PlayMode.track,
  }) async {
    if (songs.isEmpty) return;
    debugPrint('[audio] setQueue len=${songs.length} startIndex=$startIndex '
        'mode=$mode');
    _playMode = mode;
    // Cache the FeedItems before mpv asks us to resolve them.
    for (final s in songs) {
      _byId[s.id] = s;
    }
    _loadFailRetries.clear();
    _icyTitleCtl.add(null);
    _userPlaying = true;
    final medias = songs.map(_toMedia).toList();
    if (mode == PlayMode.live) {
      // Single entry — no playlist auto-advance is meaningful for a live
      // stream. Just open the one source.
      await _player.open(medias[startIndex.clamp(0, medias.length - 1)],
          play: true);
    } else {
      await _player.openAll(medias,
          index: startIndex.clamp(0, medias.length - 1), play: true);
    }
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
    for (final s in songs) {
      _byId[s.id] = s;
    }
    _loadFailRetries.clear();
    _icyTitleCtl.add(null);
    _userPlaying = false;
    _pendingStartPosition = seekTo;
    final medias = songs.map(_toMedia).toList();
    if (mode == PlayMode.live) {
      await _player.open(medias[startIndex.clamp(0, medias.length - 1)],
          play: false);
    } else {
      await _player.openAll(medias,
          index: startIndex.clamp(0, medias.length - 1), play: false);
    }
  }

  Future<void> play() async {
    _userPlaying = true;
    _loadFailRetries.clear();
    await _player.play();
  }

  Future<void> pause() async {
    _userPlaying = false;
    await _player.pause();
  }

  Future<void> seek(Duration position) => _player.seek(position);

  Future<void> stop() async {
    _userPlaying = false;
    await _player.pause();
    await _player.seek(Duration.zero);
  }

  Future<void> skipToNext() => _player.next();

  Future<void> skipToPrevious() => _player.previous();

  Future<void> jumpTo(int index) => _player.jump(index);

  /// Insert `song` immediately after the currently-playing entry.
  Future<void> playNext(FeedItem song) async {
    _byId[song.id] = song;
    if (queue.isEmpty || _currentIndex < 0) {
      await setQueue([song], 0);
      return;
    }
    // mpv only exposes append + move, so: add to end, then move to
    // currentIndex+1.
    final media = _toMedia(song);
    await _player.add(media);
    final endIdx = _player.state.playlist.items.length - 1;
    final targetIdx = _currentIndex + 1;
    if (endIdx != targetIdx) {
      await _player.move(endIdx, targetIdx);
    }
  }

  Future<void> addToQueue(FeedItem song) async {
    _byId[song.id] = song;
    if (queue.isEmpty || _currentIndex < 0) {
      await setQueue([song], 0);
      return;
    }
    await _player.add(_toMedia(song));
  }

  Future<void> removeAt(int index) async {
    if (index < 0 || index >= queue.length) return;
    await _player.remove(index);
  }

  Future<void> moveItem(int oldIndex, int newIndex) async {
    if (oldIndex < 0 ||
        newIndex < 0 ||
        oldIndex >= queue.length ||
        newIndex >= queue.length ||
        oldIndex == newIndex) {
      return;
    }
    await _player.move(oldIndex, newIndex);
  }

  /// Shuffle / unshuffle. mpv's `playlist-shuffle` shuffles the entries
  /// while keeping the currently-playing track's playback intact;
  /// `playlist-unshuffle` undoes the last shuffle.
  Future<void> setShuffle(bool enabled) async {
    try {
      await _player.setShuffle(enabled);
      debugPrint('[shuffle] $enabled');
    } catch (e) {
      debugPrint('[shuffle] setShuffle failed: $e');
    }
  }

  Future<void> clearQueue() async {
    _loadFailRetries.clear();
    _icyTitleCtl.add(null);
    await _player.clearPlaylist();
    // Pre-clear our mirrors — the playlist stream will sync them too but
    // we want subsequent reads in the same microtask to see empty.
    _byId.clear();
    _queueListenable.value = const [];
    _currentIndex = 0;
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
