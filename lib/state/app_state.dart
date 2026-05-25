// Central app state — tweaks, navigation, and the player state machine.
// Ported from the prototype's App() in app.jsx.

import 'dart:async';
import 'package:flutter/material.dart';

import '../api/dto.dart';
import '../audio/audio_handler.dart' show PlayMode;
import '../audio/audio_repo.dart';
import '../audio/eq_presets.dart';
import '../data/catalog.dart';
import '../data/models.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';

enum LoopMode { off, all, one }

class AppState extends ChangeNotifier with WidgetsBindingObserver {
  AppState({this.audioRepo, this.palettize}) {
    current = kTracks[0];
    queue = kTracks.sublist(1, 6);
    liked = {kTracks[0].id: true};
    WidgetsBinding.instance.addObserver(this);
    _bindAudio();
    _restoreSavedPlayback();
    _restoreSavedEq();
    _restoreSavedSettings();
    _restoreLibrary();
  }

  /// Load liked songs + saved collections + history from Hive at startup
  /// so the Library tab renders the user's real state on first frame
  /// instead of an empty shell that pops in once async finishes.
  Future<void> _restoreLibrary() async {
    final repo = audioRepo;
    if (repo == null) return;
    try {
      final results = await Future.wait([
        repo.library.loadLikedIds(),
        repo.library.loadLikedSongs(),
        repo.library.loadHistory(),
        repo.library.loadSaved('album'),
        repo.library.loadSavedIds('album'),
        repo.library.loadSaved('playlist'),
        repo.library.loadSavedIds('playlist'),
        repo.library.loadSaved('artist'),
        repo.library.loadSavedIds('artist'),
      ]);
      _likedIds = results[0] as Set<String>;
      _likedSongs = results[1] as List<FeedItem>;
      _playedHistory = results[2] as List<FeedItem>;
      _savedAlbums = results[3] as List<FeedItem>;
      _savedAlbumIds = results[4] as Set<String>;
      _savedPlaylists = results[5] as List<FeedItem>;
      _savedPlaylistIds = results[6] as Set<String>;
      _savedArtists = results[7] as List<FeedItem>;
      _savedArtistIds = results[8] as Set<String>;
      notifyListeners();
      debugPrint('[library] restored liked=${_likedSongs.length} '
          'history=${_playedHistory.length} '
          'albums=${_savedAlbums.length} '
          'playlists=${_savedPlaylists.length} '
          'artists=${_savedArtists.length}');
    } catch (e) {
      debugPrint('[library] restore failed: $e');
    }
  }

  /// Pulls the live palette accent for an artwork URL. Wired through the
  /// Riverpod provider in app_state_provider.dart so AppState stays Riverpod-
  /// agnostic. Null when no provider is wired (tests).
  final Future<Color?> Function(String url)? palettize;

  /// Cached accent extracted from the current artwork. Updated whenever the
  /// playing track changes; null while a palette is in flight or extraction
  /// failed. Used by `colors` when `tintFromArt` is on.
  Color? _extractedAccent;
  String? _extractedForUrl;

  /// Pull last-saved appearance + playback settings from Hive. Runs at
  /// startup so the user's accent, density, tint-from-art, and stream
  /// quality survive kill/reopen.
  Future<void> _restoreSavedSettings() async {
    final repo = audioRepo;
    if (repo == null) return;
    try {
      final app = await repo.settings.loadAppearance();
      if (app != null) {
        if (app.accentValue != null) {
          accent = Color(app.accentValue!);
        }
        if (app.density != null) {
          density = Density.values.firstWhere(
            (d) => d.name == app.density,
            orElse: () => Density.regular,
          );
        }
        if (app.tintFromArt != null) tintFromArt = app.tintFromArt!;
        if (app.tintIntensity != null) {
          tintIntensity = app.tintIntensity!.clamp(0.0, 1.0);
        }
      }
      final play = await repo.settings.loadPlayback();
      if (play != null) {
        if (play.streamQuality != null) {
          streamQuality = play.streamQuality!;
          repo.resolver.setQualityFromString(streamQuality);
        }
        if (play.repeatMode != null) {
          repeat = LoopMode.values.firstWhere(
            (m) => m.name == play.repeatMode,
            orElse: () => LoopMode.off,
          );
          repo.setRepeat(repeat);
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[settings] restore failed: $e');
    }
  }

  /// Pull the last-saved EQ state from Hive and apply it to mpv. Runs on
  /// AppState construction so playback starts with the user's preset
  /// without them having to re-apply on each launch.
  Future<void> _restoreSavedEq() async {
    final repo = audioRepo;
    if (repo == null) return;
    try {
      final saved = await repo.settings.loadEq();
      if (saved == null) return;
      eqBands = List<double>.from(saved.bands);
      currentEqPresetId = saved.presetId;
      await repo.handler.setEqBands(eqBands);
      notifyListeners();
    } catch (e) {
      debugPrint('[audio] eq restore failed: $e');
    }
  }

  /// Pull the last-played queue/track/position from disk and surface it in
  /// the UI (mini player, expanded player). mpv is also pre-loaded so when
  /// the user hits play, it resumes from where they left off.
  Future<void> _restoreSavedPlayback() async {
    final repo = audioRepo;
    if (repo == null) return;
    try {
      final saved = await repo.restore();
      if (saved == null) return;
      final song = saved.queue[saved.currentIndex];
      apiSourceLabel = saved.sourceLabel;
      apiSourceRef = saved.sourceRef;
      _applySong(song);
      position = saved.positionSec;
      // Engine is loaded but paused — UI shows "ready to play".
      isPlaying = false;
      notifyListeners();
      debugPrint('[audio] restored "${song.title}" @ ${saved.positionSec}s');
    } catch (e) {
      debugPrint('[audio] restore failed: $e');
    }
  }

  /// Real audio engine. Null only when audio is intentionally disabled
  /// (tests, headless contexts).
  final AudioRepo? audioRepo;
  final List<StreamSubscription<dynamic>> _audioSubs = [];

  /// When playback is driven by the real audio engine (i.e. a tapped
  /// FeedItem song), this holds the FeedItem so the player UI can display
  /// rich metadata. Otherwise null and `current` (dummy Track) is the source.
  FeedItem? currentApiSong;

  // Note: persisted played-history lives in `_playedHistory` (loaded from
  // LibraryStore at startup, pushed on every track change). Use
  // [playedHistory] for read access.

  /// Where the active API queue came from — e.g. 'PLAYLIST · Top Charts',
  /// 'ALBUM · Dhurandhar', 'TOP SONGS · Tanishk Bagchi'. Shown in the
  /// expanded player header. Null when we're on the dummy path or after
  /// a restore where we never knew (legacy save).
  String? apiSourceLabel;

  /// DetailRef of the playlist/album/artist the current queue was started
  /// from. Lets the expanded player's track-menu sheet surface a "Go to
  /// album/playlist" navigation row. Not persisted — re-derived next time
  /// the user starts a queue. Null on dummy-path / restore.
  DetailRef? apiSourceRef;

  // ── Settings (persisted via SettingsStore) ────────────────────────────
  Color accent = kAccentOptions[0];
  Density density = Density.regular;
  bool tintFromArt = false;

  /// How strongly the extracted artwork color overrides the user's accent
  /// when `tintFromArt` is on. 0.0 = always user accent, 1.0 = pure
  /// artwork. Default 0.7 — keeps user identity readable while letting the
  /// art tint the UI.
  double tintIntensity = 0.7;

  /// Stream quality preference. 'auto' picks the highest playable; 'high'
  /// forces 320/high; 'data' caps at 96kbps / low for cell-data savings.
  String streamQuality = 'auto';

  // ── Navigation ────────────────────────────────────────────────────────
  // Route navigation is owned by go_router now; AppState only keeps the
  // home top-tab selection (Music | Radio | Podcasts).
  String topTab = 'Music';

  // ── Player ────────────────────────────────────────────────────────────
  late Track current;
  late List<Track> queue;
  List<Track> history = [];

  // The playback clock lives in its own notifier so the 1 Hz tick rebuilds
  // only the scrubber / time / lyrics widgets — not the whole screen tree.
  final ValueNotifier<int> positionTick = ValueNotifier<int>(48);
  int get position => positionTick.value;
  set position(int v) => positionTick.value = v;

  bool isPlaying = false;
  // Legacy dummy-path liked map (kept so the dummy `playTrack` path keeps
  // working). For real API songs, `_likedIds` / `_likedSongs` below is the
  // source of truth.
  late Map<String, bool> liked;
  bool shuffle = false;
  LoopMode repeat = LoopMode.off;

  // ── Library (persisted) ───────────────────────────────────────────────
  // Loaded on construction from Hive; written through whenever the user
  // toggles a heart or a new track auto-plays.
  Set<String> _likedIds = const <String>{};
  List<FeedItem> _likedSongs = const <FeedItem>[];
  List<FeedItem> _playedHistory = const <FeedItem>[];

  // Saved collections — same newest-first ordering as liked_songs,
  // independent buckets so the Library tab can show them side-by-side.
  Set<String> _savedAlbumIds = const <String>{};
  List<FeedItem> _savedAlbums = const <FeedItem>[];
  Set<String> _savedPlaylistIds = const <String>{};
  List<FeedItem> _savedPlaylists = const <FeedItem>[];
  Set<String> _savedArtistIds = const <String>{};
  List<FeedItem> _savedArtists = const <FeedItem>[];

  List<FeedItem> get savedAlbums => _savedAlbums;
  List<FeedItem> get savedPlaylists => _savedPlaylists;
  List<FeedItem> get savedArtists => _savedArtists;

  bool isSavedAlbumId(String id) => _savedAlbumIds.contains(id);
  bool isSavedPlaylistId(String id) => _savedPlaylistIds.contains(id);
  bool isSavedArtistId(String id) => _savedArtistIds.contains(id);

  /// Is this item type+id saved in the matching bucket? Convenience for
  /// the detail-hero heart that doesn't care which kind it is.
  bool isSaved(FeedItem item) {
    switch (item.type) {
      case 'album':
        return _savedAlbumIds.contains(item.id);
      case 'playlist':
        return _savedPlaylistIds.contains(item.id);
      case 'artist':
        return _savedArtistIds.contains(item.id);
      default:
        return false;
    }
  }

  /// Toggle a saved album / playlist / artist. Persists + optimistic.
  Future<void> toggleSaved(FeedItem item) async {
    final repo = audioRepo;
    if (repo == null) return;
    final kind = item.type;
    if (kind != 'album' && kind != 'playlist' && kind != 'artist') return;
    final wasSaved = isSaved(item);
    final shouldSave = !wasSaved;
    // Optimistic — UI heart fills instantly.
    if (kind == 'album') {
      _savedAlbumIds = {..._savedAlbumIds};
      if (shouldSave) {
        _savedAlbumIds.add(item.id);
        _savedAlbums = [item, ..._savedAlbums.where((s) => s.id != item.id)];
      } else {
        _savedAlbumIds.remove(item.id);
        _savedAlbums = _savedAlbums.where((s) => s.id != item.id).toList();
      }
    } else if (kind == 'playlist') {
      _savedPlaylistIds = {..._savedPlaylistIds};
      if (shouldSave) {
        _savedPlaylistIds.add(item.id);
        _savedPlaylists = [item, ..._savedPlaylists.where((s) => s.id != item.id)];
      } else {
        _savedPlaylistIds.remove(item.id);
        _savedPlaylists = _savedPlaylists.where((s) => s.id != item.id).toList();
      }
    } else {
      _savedArtistIds = {..._savedArtistIds};
      if (shouldSave) {
        _savedArtistIds.add(item.id);
        _savedArtists = [item, ..._savedArtists.where((s) => s.id != item.id)];
      } else {
        _savedArtistIds.remove(item.id);
        _savedArtists = _savedArtists.where((s) => s.id != item.id).toList();
      }
    }
    flashToast(shouldSave
        ? 'Added ${_kindLabel(kind)} to Library'
        : 'Removed ${_kindLabel(kind)} from Library');
    notifyListeners();
    try {
      final next =
          await repo.library.setSaved(item: item, saved: shouldSave);
      switch (kind) {
        case 'album':
          _savedAlbums = next;
          _savedAlbumIds = next.map((s) => s.id).toSet();
        case 'playlist':
          _savedPlaylists = next;
          _savedPlaylistIds = next.map((s) => s.id).toSet();
        case 'artist':
          _savedArtists = next;
          _savedArtistIds = next.map((s) => s.id).toSet();
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[library] toggleSaved failed for ${item.type}:${item.id}: $e');
    }
  }

  static String _kindLabel(String kind) {
    switch (kind) {
      case 'album':
        return 'album';
      case 'playlist':
        return 'playlist';
      case 'artist':
        return 'artist';
      default:
        return 'item';
    }
  }

  /// Full liked list — newest-first.
  List<FeedItem> get likedSongs => _likedSongs;

  /// Last-played API songs — newest-first, capped at LibraryStore's max.
  List<FeedItem> get playedHistory => _playedHistory;

  /// O(1) liked check by song id. Use for heart icons in lists.
  bool isLikedId(String id) => _likedIds.contains(id);

  /// True when the currently-playing API song is liked. Drives the heart
  /// in the expanded + mini players.
  bool get isLikedCurrentApi {
    final id = currentApiSong?.id;
    if (id == null) return likedCurrent; // dummy-path fallback
    return _likedIds.contains(id);
  }

  /// Like / unlike an API song. Updates the in-memory cache, persists,
  /// and notifies listeners. Idempotent (calling twice with the same
  /// state is a no-op write).
  Future<void> toggleLikedSong(FeedItem song) async {
    final repo = audioRepo;
    if (repo == null) return;
    final wasLiked = _likedIds.contains(song.id);
    final shouldLike = !wasLiked;
    // Optimistic UI: update cache first so the heart fills instantly.
    _likedIds = {..._likedIds};
    if (shouldLike) {
      _likedIds.add(song.id);
      _likedSongs = [song, ..._likedSongs.where((s) => s.id != song.id)];
    } else {
      _likedIds.remove(song.id);
      _likedSongs = _likedSongs.where((s) => s.id != song.id).toList();
    }
    flashToast(shouldLike ? 'Added to Liked' : 'Removed from Liked');
    notifyListeners();
    // Persist + reconcile with disk truth (in case of concurrent writes).
    try {
      final next = await repo.library.setLiked(song: song, liked: shouldLike);
      _likedSongs = next;
      _likedIds = next.map((s) => s.id).toSet();
      notifyListeners();
    } catch (e) {
      debugPrint('[library] toggleLiked failed for ${song.id}: $e');
    }
  }

  /// Clear the played-history list. Used by the Library tab's clear action.
  Future<void> clearPlayedHistory() async {
    final repo = audioRepo;
    if (repo == null) return;
    _playedHistory = const [];
    notifyListeners();
    try {
      await repo.library.clearHistory();
    } catch (e) {
      debugPrint('[library] clearHistory failed: $e');
    }
  }

  // ── 10-band graphic EQ ────────────────────────────────────────────────
  // ISO frequencies matching RN's audio_x: 31, 63, 125, 250, 500, 1k, 2k,
  // 4k, 8k, 16k Hz. Gains in dB, clamped to -12..+12. Preset id (when one
  // is active) is tracked separately so the UI can highlight it and clear
  // on manual edit.
  static const eqFrequencies = ['31', '63', '125', '250', '500', '1k', '2k', '4k', '8k', '16k'];
  List<double> eqBands = List<double>.filled(10, 0);
  String? currentEqPresetId = 'flat';

  // ── Toast ─────────────────────────────────────────────────────────────
  String toast = '';
  Timer? _toastTimer;

  Timer? _tick;

  // ── Derived ───────────────────────────────────────────────────────────

  /// Resolved accent — when tint-from-art is on, lerps the user accent
  /// toward the artwork's extracted color by `tintIntensity`. Falls back
  /// to the deterministic hash placeholder while palette is in flight.
  Color get resolvedAccent {
    if (!tintFromArt) return accent;
    final extracted = _extractedAccent ?? artAccent(current.id);
    return Color.lerp(accent, extracted, tintIntensity.clamp(0.0, 1.0))!;
  }

  bool get likedCurrent => liked[current.id] ?? false;

  SunohColors get colors {
    final tint = tintFromArt ? resolvedAccent : null;
    return SunohColors.resolve(accent: resolvedAccent, tintAccent: tint);
  }

  // ── Playback timer ────────────────────────────────────────────────────
  // The simulated clock only runs for dummy tracks (radio stations, podcasts
  // — the catalog-backed paths). Real audio (FeedItem songs played through
  // audioRepo) drives positionTick from the engine's position stream below.
  void _ensureTimer() {
    _tick?.cancel();
    if (!isPlaying || currentApiSong != null) return;
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (position + 1 >= current.duration) {
        next();
      } else {
        // Only bumps positionTick — does NOT notify the whole tree.
        position += 1;
      }
    });
  }

  // ── Real audio plumbing ───────────────────────────────────────────────
  void _bindAudio() {
    final repo = audioRepo;
    if (repo == null) return;
    final handler = repo.handler;

    // Position → positionTick (the scrubber + lyrics already watch this).
    // Also persists position to disk roughly every 5 seconds so a crash
    // doesn't lose more than that.
    int lastPersistedSec = 0;
    _audioSubs.add(handler.positionStream.listen((pos) {
      if (currentApiSong == null) return; // dummy clock still owns the tick
      final secs = pos.inSeconds;
      if (secs != position) position = secs;
      if ((secs - lastPersistedSec).abs() >= 5) {
        lastPersistedSec = secs;
        audioRepo?.persistCurrentPosition();
      }
    }));
    // mpv's reported duration → _engineDurationSec. Fires shortly after
    // each track opens. Resets to 0 on track change via _applySong.
    _audioSubs.add(handler.durationStream.listen((dur) {
      if (currentApiSong == null) return;
      final secs = dur.inSeconds;
      if (secs > 0 && secs != _engineDurationSec) {
        _engineDurationSec = secs;
        notifyListeners();
      }
    }));
    // Playing flag → isPlaying.
    _audioSubs.add(handler.playingStream.listen((playing) {
      if (currentApiSong == null) return;
      if (playing != isPlaying) {
        isPlaying = playing;
        notifyListeners();
      }
    }));
    // Track change → currentApiSong + Track stub. Fires when mpv advances
    // (next button, queue auto-advance, headset/notification skip).
    // Mid-song metadata enrichment — fires after the on_load hook has
    // hit /music/song/:id and merged the richer payload (artists,
    // duration, subtitle) into the queue entry. Saavn search responses
    // arrive sparse; this stream is how the player UI gets the real
    // artist names + scrubber max after the user taps a search result.
    _audioSubs.add(handler.enrichedCurrentSongStream.listen((enriched) {
      if (currentApiSong?.id != enriched.id) return;
      _applySong(enriched);
      notifyListeners();
    }));
    _audioSubs.add(handler.currentSongStream.listen((song) {
      if (song == null) return;
      if (currentApiSong?.id == song.id) return; // already in sync
      // Push the previous song onto the persisted history before swapping
      // (NOT the new one — history is "songs you finished listening to").
      // The push fires fire-and-forget; on success it'll notifyListeners
      // again with the updated list. We don't await — UI doesn't wait on
      // Hive for the track-change animation.
      final prev = currentApiSong;
      if (prev != null) {
        unawaited(_pushPlayedHistory(prev));
      }
      _applySong(song);
      notifyListeners();
    }));
  }

  Future<void> _pushPlayedHistory(FeedItem song) async {
    final repo = audioRepo;
    if (repo == null) return;
    // Optimistic update so the Library tab sees the entry immediately.
    _playedHistory = [
      song,
      ..._playedHistory.where((s) => s.id != song.id),
    ];
    if (_playedHistory.length > 50) {
      _playedHistory = _playedHistory.sublist(0, 50);
    }
    try {
      final next = await repo.library.pushHistory(song);
      _playedHistory = next;
      notifyListeners();
    } catch (e) {
      debugPrint('[library] pushHistory failed: $e');
    }
  }

  // ── Background position restore ───────────────────────────────────────
  // On Android, when the app goes background for a long time the OS can
  // restart the audio_service / mpv process. Mpv state comes back at
  // position 0 even though the same track is loaded. Save where we were
  // on pause and seek back if the engine has reset.
  String? _savedTrackId;
  int _savedPositionSec = 0;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (audioRepo == null || currentApiSong == null) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // In-memory snapshot for same-session OS resets.
      _savedTrackId = currentApiSong!.id;
      _savedPositionSec = position;
      // Persist to disk so a kill+relaunch comes back to the same spot.
      audioRepo!.persistAll();
      debugPrint(
          '[audio] lifecycle paused — saved $_savedTrackId@${_savedPositionSec}s');
    } else if (state == AppLifecycleState.resumed) {
      _maybeRestorePosition();
    }
  }

  void _maybeRestorePosition() {
    final saved = _savedTrackId;
    if (saved == null || _savedPositionSec <= 1) return;
    // Wait a beat — mpv may still be settling after the OS handed control back.
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      if (currentApiSong?.id != saved) return; // user switched tracks
      final enginePos = audioRepo?.handler.position.inSeconds ?? 0;
      if (enginePos < 2 && _savedPositionSec > 2) {
        debugPrint(
            '[audio] lifecycle resumed — engine at ${enginePos}s, restoring to ${_savedPositionSec}s');
        audioRepo?.seek(Duration(seconds: _savedPositionSec));
      }
      _savedTrackId = null;
      _savedPositionSec = 0;
    });
  }

  /// Mirror a FeedItem into the legacy Track stub the player UI reads from.
  void _applySong(FeedItem song) {
    currentApiSong = song;
    // Artist fallback chain: artists[].name → subtitle → empty (let UI
    // hide). The old "Unknown artist" literal was the wrong default for
    // search responses where saavn returns subtitle:null + artists:[] —
    // the player would scream "Unknown artist" for every search-tapped
    // song even when there's no real data unknown about it.
    final fromArtists = (song.artists ?? const <ApiArtistRef>[])
        .map((a) => a.name.trim())
        .where((n) => n.isNotEmpty)
        .take(2)
        .join(', ');
    final fromSubtitle = (song.subtitle ?? '').trim();
    final artistLabel = fromArtists.isNotEmpty
        ? fromArtists
        : (fromSubtitle.isNotEmpty ? fromSubtitle : '');
    // Duration: search responses don't include it, so the int.tryParse
    // falls through to 180 here. The real duration is bound from mpv's
    // duration stream in _bindAudio and surfaced via [currentDurationSec]
    // — the player UI prefers that over `current.duration`.
    final durSec = int.tryParse(song.duration ?? '') ?? 180;
    current = Track(
      id: song.id,
      title: song.title,
      artist: artistLabel,
      album: '',
      duration: durSec,
      plays: song.playCount ?? '',
    );
    // mpv will report fresh duration as the next file loads; clear the
    // stale value so the player doesn't briefly show the previous track's
    // duration for the new one.
    _engineDurationSec = 0;
    position = 0;
    _refreshExtractedAccent(song.artwork);
  }

  // Live duration reported by mpv after it opens the current file. 0 when
  // not yet known (e.g. immediately after a track change, or for dummy
  // playback paths that don't go through mpv). Use [currentDurationSec]
  // for the merged "best known" value.
  int _engineDurationSec = 0;

  /// Authoritative duration in seconds for the currently-playing track.
  /// Prefers mpv's reported value (accurate, available after the file
  /// opens) and falls back to the FeedItem's parsed duration (or the 180
  /// default) for the brief window before mpv has loaded the file or for
  /// dummy-path playback.
  int get currentDurationSec =>
      _engineDurationSec > 0 ? _engineDurationSec : current.duration;

  /// Kick off palette extraction for the given URL. When it lands, the
  /// cached `_extractedAccent` updates and we notify so any palette-aware
  /// UI rebuilds. Cheap to call repeatedly — palette_provider caches per
  /// URL for 30 minutes.
  ///
  /// On track change we **clear `_extractedAccent` immediately** so the UI
  /// doesn't keep painting with the previous track's palette during the
  /// short async window before the new palette lands. Two-phase update:
  ///   1. Clear → notify (UI snaps to the user's accent fallback).
  ///   2. Palette resolves → set + notify (UI transitions to the new tint).
  Future<void> _refreshExtractedAccent(String? url) async {
    final p = palettize;
    final previousAccent = _extractedAccent;
    final previousUrl = _extractedForUrl;
    // No-op when the URL hasn't actually changed (e.g. repeat-one).
    if (url == previousUrl && previousAccent != null) return;

    // Phase 1: forget the old palette right now.
    _extractedForUrl = url;
    _extractedAccent = null;
    if (previousAccent != null && tintFromArt) notifyListeners();

    if (p == null || url == null || url.isEmpty) {
      debugPrint('[palette] skip — '
          'palettize=${p == null ? 'null' : 'set'} url="${url ?? ''}"');
      return;
    }

    try {
      final color = await p(url);
      // Bail if a newer track took over while we were waiting.
      if (_extractedForUrl != url) {
        debugPrint('[palette] discard stale result for $url');
        return;
      }
      _extractedAccent = color;
      debugPrint('[palette] resolved ${color ?? 'null'} for $url '
          '(tintFromArt=$tintFromArt)');
      if (tintFromArt) notifyListeners();
    } catch (e) {
      debugPrint('[palette] extraction failed for $url: $e');
    }
  }

  /// Play a single song. Equivalent to [playApiQueue] with a one-element list.
  Future<void> playApiSong(FeedItem song, {String? sourceLabel}) =>
      playApiQueue([song], 0, sourceLabel: sourceLabel);

  /// Insert `song` right after the currently-playing track. Surfaces a
  /// toast on success so the user gets confirmation (the queue mutation
  /// itself is invisible — there's no inline indicator on the album/
  /// playlist row for "this song is now queued next").
  Future<void> playApiSongNext(FeedItem song) async {
    final repo = audioRepo;
    if (repo == null) {
      flashToast('Audio engine unavailable');
      return;
    }
    await repo.playNext(song);
    flashToast('Up next: ${song.title}');
  }

  /// Append `song` to the end of the queue. Same UX shape as [playApiSongNext]
  /// — just a different insertion point.
  Future<void> addApiSongToQueue(FeedItem song) async {
    final repo = audioRepo;
    if (repo == null) {
      flashToast('Audio engine unavailable');
      return;
    }
    await repo.addToQueue(song);
    flashToast('Added to queue: ${song.title}');
  }

  /// Play a queue of songs starting at [startIndex]. Optimistically updates
  /// the UI to the starting song, then hands the rest to the engine.
  ///
  /// [sourceLabel] is what the player header displays as "PLAYING FROM"
  /// (e.g. 'PLAYLIST · Top Charts'). Null defaults to 'Library'.
  Future<void> playApiQueue(
    List<FeedItem> songs,
    int startIndex, {
    String? sourceLabel,
    DetailRef? sourceRef,
    PlayMode mode = PlayMode.track,
  }) async {
    if (songs.isEmpty) return;
    final startSong = songs[startIndex.clamp(0, songs.length - 1)];
    debugPrint('[audio] playApiQueue len=${songs.length} idx=$startIndex '
        '→ "${startSong.title}"');
    apiSourceLabel = sourceLabel;
    apiSourceRef = sourceRef;
    _applySong(startSong);
    isPlaying = true;
    _tick?.cancel();
    notifyListeners();

    final repo = audioRepo;
    if (repo == null) {
      flashToast('Audio engine unavailable');
      isPlaying = false;
      notifyListeners();
      return;
    }
    try {
      await repo.playQueue(songs, startIndex,
          sourceLabel: sourceLabel, sourceRef: sourceRef, mode: mode);
    } catch (e) {
      flashToast('Could not play: $e');
      isPlaying = false;
      notifyListeners();
    }
  }

  // ── Settings setters (each fires + persists via SettingsStore) ────────
  void setAccent(Color v) {
    accent = v;
    _persistAppearance();
    notifyListeners();
  }

  void setDensity(Density v) {
    density = v;
    _persistAppearance();
    notifyListeners();
  }

  void setTintFromArt(bool v) {
    tintFromArt = v;
    _persistAppearance();
    // Make sure the live artwork color is ready when the toggle flips on.
    if (v && _extractedAccent == null) {
      _refreshExtractedAccent(currentApiSong?.artwork);
    }
    notifyListeners();
  }

  void setTintIntensity(double v) {
    tintIntensity = v.clamp(0.0, 1.0);
    _persistAppearance();
    notifyListeners();
  }

  void setStreamQuality(String v) {
    streamQuality = v;
    audioRepo?.resolver.setQualityFromString(v);
    _persistPlayback();
    notifyListeners();
  }

  void _persistAppearance() {
    audioRepo?.settings.saveAppearance(
      accent: accent,
      density: density,
      tintFromArt: tintFromArt,
      tintIntensity: tintIntensity,
    );
  }

  void _persistPlayback() {
    audioRepo?.settings.savePlayback(
      streamQuality: streamQuality,
      repeatMode: repeat.name,
    );
  }

  // ── EQ setters ────────────────────────────────────────────────────────
  void setEqBand(int index, double db) {
    if (index < 0 || index >= eqBands.length) return;
    eqBands = [...eqBands]..[index] = db.clamp(-12.0, 12.0);
    currentEqPresetId = null; // manual tweak → presets deselect
    audioRepo?.handler.setEqBands(eqBands);
    _persistEq();
    notifyListeners();
  }

  void applyEqPreset(EqPreset preset) {
    eqBands = preset.gains.map((g) => g.toDouble()).toList();
    currentEqPresetId = preset.id;
    audioRepo?.handler.setEqBands(eqBands);
    _persistEq();
    notifyListeners();
  }

  void resetEq() {
    eqBands = List<double>.filled(10, 0);
    currentEqPresetId = 'flat';
    audioRepo?.handler.setEqBands(eqBands);
    _persistEq();
    notifyListeners();
  }

  void _persistEq() {
    final repo = audioRepo;
    if (repo == null) return;
    // Fire and forget — Hive writes are fast enough that we don't gate
    // anything on completion. Errors are logged inside the store.
    repo.settings.saveEq(bands: eqBands, presetId: currentEqPresetId);
  }

  bool get eqActive => eqBands.any((g) => g.abs() > 0.001);

  // ── Toast ─────────────────────────────────────────────────────────────
  void flashToast(String m) {
    toast = m;
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(milliseconds: 2700), () {
      toast = '';
      notifyListeners();
    });
    notifyListeners();
  }

  // ── Player actions ────────────────────────────────────────────────────
  void playTrack(Track track, [List<Track>? contextTracks]) {
    if (current.id != track.id) {
      history = [current, ...history].take(24).toList();
    }
    current = track;
    position = 0;
    isPlaying = true;
    if (contextTracks != null) {
      final idx = contextTracks.indexWhere((x) => x.id == track.id);
      if (idx >= 0) queue = contextTracks.sublist(idx + 1);
    }
    _ensureTimer();
    notifyListeners();
  }

  void playAll(List<Track> tracks) {
    if (tracks.isEmpty) return;
    playTrack(tracks.first, tracks);
  }

  void playPause() {
    isPlaying = !isPlaying;
    if (currentApiSong != null && audioRepo != null) {
      if (isPlaying) {
        audioRepo!.play();
      } else {
        audioRepo!.pause();
      }
    } else {
      _ensureTimer();
    }
    notifyListeners();
  }

  void next() {
    // Real engine queue: forward to mpv. The currentSongStream listener
    // updates UI when mpv advances.
    if (currentApiSong != null && audioRepo != null) {
      audioRepo!.next();
      return;
    }
    if (queue.isEmpty) {
      isPlaying = false;
      position = 0;
      _ensureTimer();
      notifyListeners();
      return;
    }
    final n = queue.first;
    history = [current, ...history].take(24).toList();
    current = n;
    queue = queue.sublist(1);
    position = 0;
    _ensureTimer();
    notifyListeners();
  }

  void prev() {
    if (currentApiSong != null && audioRepo != null) {
      // Match the legacy behavior: if we're a few seconds in, restart the
      // current track instead of jumping back.
      if (position > 4) {
        audioRepo!.seek(Duration.zero);
        position = 0;
        notifyListeners();
        return;
      }
      audioRepo!.previous();
      return;
    }
    if (position > 4) {
      position = 0;
      notifyListeners();
      return;
    }
    if (history.isEmpty) {
      position = 0;
      notifyListeners();
      return;
    }
    final last = history.first;
    queue = [current, ...queue];
    current = last;
    history = history.sublist(1);
    position = 0;
    notifyListeners();
  }

  void seek(int v) {
    position = v.clamp(0, current.duration);
    if (currentApiSong != null && audioRepo != null) {
      audioRepo!.seek(Duration(seconds: position));
    }
    notifyListeners();
  }

  void toggleLike() {
    final was = liked[current.id] ?? false;
    liked = {...liked, current.id: !was};
    flashToast(was ? 'Removed from Liked' : 'Added to Liked');
  }

  void addToQueue(Track track) {
    queue = [...queue, track];
    flashToast('Queued ‘${track.title}’');
  }

  void toggleShuffle() {
    shuffle = !shuffle;
    // Push to the handler so the queue actually gets rearranged. Without
    // this the icon flipped but track-N+1 was still the same boring track
    // it always was — the user reasonably called it broken.
    audioRepo?.setShuffle(shuffle);
    notifyListeners();
  }

  void cycleRepeat() {
    repeat = switch (repeat) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
    // Push to the handler so natural-EOF advance honours the new mode.
    // Manual skip taps ignore repeat — they always go to the literal
    // next queue entry.
    audioRepo?.setRepeat(repeat);
    _persistPlayback();
    notifyListeners();
  }

  void jumpQueue(int i) {
    final newCur = queue[i];
    final before = queue.sublist(0, i);
    final after = queue.sublist(i + 1);
    history = [current, ...before.reversed, ...history].take(24).toList();
    queue = after;
    current = newCur;
    position = 0;
    isPlaying = true;
    _ensureTimer();
    notifyListeners();
  }

  void removeFromQueue(int i) {
    queue = [
      for (var k = 0; k < queue.length; k++)
        if (k != i) queue[k]
    ];
    notifyListeners();
  }

  void reorderQueue(int oldIndex, int newIndex) {
    final list = [...queue];
    if (newIndex > oldIndex) newIndex -= 1;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    queue = list;
    notifyListeners();
  }

  // ── API-queue ops (used by queue sheet when in API playback mode) ─────

  /// Songs in the engine queue AFTER the currently-playing one — what the
  /// queue sheet renders as "Next up". Each index here maps to engine index
  /// `currentIndex + 1 + i`.
  List<FeedItem> get apiUpNext {
    final repo = audioRepo;
    if (repo == null) return const [];
    final q = repo.queue;
    final idx = repo.currentIndex;
    if (q.isEmpty || idx + 1 >= q.length) return const [];
    return q.sublist(idx + 1);
  }

  Future<void> apiJumpToUpNext(int upNextIndex) async {
    final repo = audioRepo;
    if (repo == null) return;
    final target = repo.currentIndex + 1 + upNextIndex;
    await repo.jumpToIndex(target);
  }

  Future<void> apiRemoveFromUpNext(int upNextIndex) async {
    final repo = audioRepo;
    if (repo == null) return;
    final target = repo.currentIndex + 1 + upNextIndex;
    await repo.removeFromQueue(target);
    notifyListeners();
  }

  Future<void> apiReorderUpNext(int oldIndex, int newIndex) async {
    final repo = audioRepo;
    if (repo == null) return;
    // ReorderableList's convention: newIndex is the slot where the item is
    // dropped, computed BEFORE removing oldIndex. Adjust for that quirk.
    var adjusted = newIndex;
    if (newIndex > oldIndex) adjusted -= 1;
    final base = repo.currentIndex + 1;
    await repo.moveInQueue(base + oldIndex, base + adjusted);
    notifyListeners();
  }

  Future<void> apiClearUpNext() async {
    final repo = audioRepo;
    if (repo == null) return;
    // We remove from the tail forward so the current track keeps playing.
    final base = repo.currentIndex + 1;
    while (repo.queue.length > base) {
      await repo.removeFromQueue(repo.queue.length - 1);
    }
    notifyListeners();
  }

  // Tune a radio station — synthesizes a "live" track and starts playback.
  void playStation(String id) {
    final s = stationOf(id);
    playTrack(Track(
      id: id,
      title: s?.live ?? 'Live',
      artist: s?.name ?? 'Radio',
      duration: 6000,
      plays: 'live',
      album: id,
    ));
  }

  void setTopTab(String t) {
    topTab = t;
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    _toastTimer?.cancel();
    for (final s in _audioSubs) {
      s.cancel();
    }
    positionTick.dispose();
    super.dispose();
  }
}
