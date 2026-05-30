// Central app state — tweaks, navigation, and the player state machine.
// Ported from the prototype's App() in app.jsx.

import 'dart:async';
import 'dart:math' show Random;

import 'package:flutter/material.dart';

import '../api/dto.dart';
import '../audio/audio_handler.dart' show PlayMode;
import 'package:flutter_chrome_cast/enums.dart';

import '../api/sunoh_api.dart';
import '../audio/audio_repo.dart';
import '../audio/eq_presets.dart';
import '../audio/settings_store.dart';
import '../cast/cast_service.dart';
import '../data/catalog.dart';
import '../data/models.dart';
import '../data/user_playlist.dart';
import '../services/analytics_service.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';

enum LoopMode { off, all, one }

/// Single-import-at-a-time state machine for Spotify playlist imports.
/// AppState mutates this through `importSpotifyPlaylist` /
/// `dismissSpotifyImport`; the persistent banner watches it across all
/// screens.
enum SpotifyImportStatus { idle, fetching, completed, failed }

class SpotifyImportState {
  const SpotifyImportState({
    required this.status,
    this.sourceUrl,
    this.sourceName,
    this.newPlaylistId,
    this.totalTracks,
    this.matchedTracks,
    this.errorMessage,
    this.startedAt,
  });
  const SpotifyImportState.idle()
      : status = SpotifyImportStatus.idle,
        sourceUrl = null,
        sourceName = null,
        newPlaylistId = null,
        totalTracks = null,
        matchedTracks = null,
        errorMessage = null,
        startedAt = null;
  final SpotifyImportStatus status;
  /// The original URL the user pasted — kept so the failure banner can
  /// offer a "retry" without re-asking.
  final String? sourceUrl;
  /// Playlist name from the Spotify API once it lands. Used for the
  /// completion banner ("Imported X — N songs").
  final String? sourceName;
  /// UserPlaylist id created on successful import. Tapping the
  /// completion banner navigates here.
  final String? newPlaylistId;
  final int? totalTracks;
  final int? matchedTracks;
  final String? errorMessage;
  /// Used by the banner to render an elapsed-time hint while running.
  final DateTime? startedAt;
}

class AppState extends ChangeNotifier with WidgetsBindingObserver {
  AppState({this.audioRepo, this.api, this.palettize}) {
    current = kTracks[0];
    queue = kTracks.sublist(1, 6);
    liked = {kTracks[0].id: true};
    WidgetsBinding.instance.addObserver(this);
    _bindAudio();
    _wireCast();
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
        repo.library.loadUserPlaylists(),
        repo.library.loadSubscribedPodcasts(),
        repo.library.loadSubscribedPodcastIds(),
        repo.library.loadEpisodeProgress(),
        repo.library.loadLikedStations(),
        repo.library.loadLikedStationIds(),
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
      _userPlaylists = results[9] as List<UserPlaylist>;
      _subscribedPodcasts = results[10] as List<FeedItem>;
      _subscribedPodcastIds = results[11] as Set<String>;
      _episodeProgress = results[12] as Map<String, int>;
      _likedStations = results[13] as List<FeedItem>;
      _likedStationIds = results[14] as Set<String>;
      notifyListeners();
      debugPrint('[library] restored liked=${_likedSongs.length} '
          'history=${_playedHistory.length} '
          'albums=${_savedAlbums.length} '
          'playlists=${_savedPlaylists.length} '
          'artists=${_savedArtists.length} '
          'userPlaylists=${_userPlaylists.length} '
          'podcasts=${_subscribedPodcasts.length} '
          'episodeProgress=${_episodeProgress.length} '
          'stations=${_likedStations.length}');
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
        if (play.languages != null) {
          selectedLanguages = play.languages!.toSet();
        }
        if (play.endlessAutoplay != null) {
          endlessAutoplay = play.endlessAutoplay!;
        }
      }
      final recents = await repo.settings.loadSearchRecents();
      if (recents.isNotEmpty) _searchRecents = recents;
      // Privacy — load the analytics opt-out before notifying. A null
      // value (fresh installs) keeps the default `analyticsEnabled =
      // true`. Apply to the service before any event fires so a user
      // who'd opted out previously doesn't see a single event slip
      // through on startup.
      final analytics = await repo.settings.loadAnalyticsEnabled();
      if (analytics != null) analyticsEnabled = analytics;
      await AnalyticsService.instance.setEnabled(analyticsEnabled);
      notifyListeners();
      // Push restored settings as user properties so every subsequent
      // analytics event is grouped by them in Firebase.
      AnalyticsService.instance.setUserProperties(
        languages: selectedLanguagesCsv,
        density: density.name,
        tintFromArt: tintFromArt,
        streamQuality: streamQuality,
        endlessAutoplay: endlessAutoplay,
      );
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
      // Restore the live flag too — without this, a radio-station
      // queue would re-mount with the track-mode player UI (scrubber,
      // skip buttons) and tapping play after restore would silently
      // no-op because the prior session reached EOF on the live entry.
      _isLive = saved.playMode == PlayMode.live;
      // Engine is loaded but paused — UI shows "ready to play".
      isPlaying = false;
      // Guard against mpv's positionStream clobbering the restored value
      // back to 0. `prepareQueue` opens the file paused; mpv has the
      // `file-local-options/start=Ns` property set in the load hook, but
      // that only takes effect WHEN PLAYBACK STARTS. Until then mpv
      // reports position 0, and the positionStream listener would
      // overwrite our saved value. Holding a non-zero guard makes the
      // listener ignore 0-reports until mpv emits a real non-zero value
      // (which happens the instant the user hits play and mpv seeks).
      _restoredPositionGuard = saved.positionSec;
      notifyListeners();
      debugPrint('[audio] restored "${song.title}" @ ${saved.positionSec}s');
    } catch (e) {
      debugPrint('[audio] restore failed: $e');
    }
  }

  /// Non-zero while the most recent restore is still holding its saved
  /// position against mpv's "paused at 0" reports. Cleared the moment
  /// mpv emits a non-zero position (i.e. playback began and seek
  /// landed), or the user explicitly seeks / starts a new song.
  int _restoredPositionGuard = 0;

  /// Real audio engine. Null only when audio is intentionally disabled
  /// (tests, headless contexts).
  final AudioRepo? audioRepo;

  /// Backend API for endless-autoplay's radio prime. Optional so tests
  /// can construct an AppState without the network layer.
  final SunohApi? api;

  final List<StreamSubscription<dynamic>> _audioSubs = [];

  /// When playback is driven by the real audio engine (i.e. a tapped
  /// FeedItem song), this holds the FeedItem so the player UI can display
  /// rich metadata. Otherwise null and `current` (dummy Track) is the source.
  FeedItem? currentApiSong;

  // ── Sleep timer ────────────────────────────────────────────────────────
  // Two modes: timed (a Duration ticks down) OR end-of-track (pauses when
  // the next currentSongStream event fires). Both pause via `_fadeAndPause`
  // — a short volume ramp then handler.pause(), with the volume restored
  // afterwards so the next play isn't silent.
  Duration? sleepRemaining;
  bool sleepAtTrackEnd = false;
  Timer? _sleepTickTimer;
  // Captured at arm-time so a manual skip doesn't trigger the timer on the
  // wrong track.
  String? _sleepCapturedSongId;

  bool get sleepArmed => sleepRemaining != null || sleepAtTrackEnd;

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

  /// When true, the moment the active track is the last in the queue the
  /// player fires a radio_station prime seeded by it and appends the
  /// returned songs. Off by default; persisted in settings.
  bool endlessAutoplay = false;

  /// User-facing opt-out for Firebase Analytics. On by default; flipping
  /// to false calls `AnalyticsService.setEnabled(false)` which both
  /// halts collection via Firebase's own switch AND resets the local
  /// install id. Persisted in the settings box under
  /// `privacy.analytics_enabled`.
  bool analyticsEnabled = true;

  /// Guard against a second prime firing while the first one's network
  /// call is in flight (currentSongStream can emit several times back-to-
  /// back during a queue swap, and we'd double-append otherwise).
  bool _autoplayPriming = false;

  /// Selected music languages (the lowercase `value` slugs returned by
  /// `/music/languages`). Threaded into `/music/home?languages=…` so the
  /// feed is region-appropriate, and passed as `lang=` to radio session
  /// + premature-EOF refresh paths. Empty set means "let the backend
  /// pick its default" (server-side default is hindi+english).
  ///
  /// Read via [selectedLanguagesCsv] when you need the joined query
  /// string. Mutated via [toggleLanguage].
  Set<String> selectedLanguages = <String>{};

  /// Comma-joined slug list for query params, or `null` when nothing's
  /// selected (so callers can let the backend pick its default).
  String? get selectedLanguagesCsv =>
      selectedLanguages.isEmpty ? null : selectedLanguages.join(',');

  /// Toggle a language value in/out of the user's selection. Persists +
  /// invalidates the home feed cache so the next render fetches with
  /// the new language set.
  void toggleLanguage(String value) {
    final v = value.toLowerCase();
    if (selectedLanguages.contains(v)) {
      selectedLanguages = {...selectedLanguages}..remove(v);
    } else {
      selectedLanguages = {...selectedLanguages, v};
    }
    _persistPlayback();
    notifyListeners();
  }

  // ── Search recents ────────────────────────────────────────────────────
  /// Recent search queries (newest first). Persisted in the `'settings'`
  /// Hive box under `search.recents`; capped at [SettingsStore.kSearchRecentsMax].
  /// Read via [searchRecents]; add via [pushSearchRecent]; wipe via
  /// [clearSearchRecents].
  List<String> _searchRecents = const <String>[];
  List<String> get searchRecents => _searchRecents;

  void pushSearchRecent(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    // De-dupe case-insensitively while keeping the user's casing for the
    // newest entry, then cap.
    final lower = trimmed.toLowerCase();
    final next = <String>[trimmed];
    for (final q in _searchRecents) {
      if (q.toLowerCase() == lower) continue;
      next.add(q);
      if (next.length >= SettingsStore.kSearchRecentsMax) break;
    }
    _searchRecents = next;
    audioRepo?.settings.saveSearchRecents(_searchRecents);
    notifyListeners();
  }

  void clearSearchRecents() {
    if (_searchRecents.isEmpty) return;
    _searchRecents = const <String>[];
    audioRepo?.settings.saveSearchRecents(_searchRecents);
    notifyListeners();
  }

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
  /// Liked radio stations — own bucket so they don't pollute Liked
  /// Songs. Newest-first; toggled via [toggleLikedStation].
  Set<String> _likedStationIds = const <String>{};
  List<FeedItem> _likedStations = const <FeedItem>[];
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

  /// User-created playlists. Newest-first by `updatedAt`. Backed by the
  /// same Hive `library` box; mutated through `createUserPlaylist` /
  /// `addToUserPlaylist` / etc.
  List<UserPlaylist> _userPlaylists = const <UserPlaylist>[];
  List<UserPlaylist> get userPlaylists => _userPlaylists;
  UserPlaylist? userPlaylistById(String id) {
    for (final p in _userPlaylists) {
      if (p.id == id) return p;
    }
    return null;
  }

  // ── Podcasts: subscribed shows + episode progress ─────────────────────
  Set<String> _subscribedPodcastIds = const <String>{};
  List<FeedItem> _subscribedPodcasts = const <FeedItem>[];
  List<FeedItem> get subscribedPodcasts => _subscribedPodcasts;
  bool isSubscribedPodcast(String id) => _subscribedPodcastIds.contains(id);

  /// Episode-id → last-known-position-in-seconds. Loaded at startup;
  /// kept in memory so the lookup on episode open is synchronous.
  Map<String, int> _episodeProgress = <String, int>{};
  int? episodeProgressSec(String episodeId) => _episodeProgress[episodeId];

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
    AnalyticsService.instance.logSaveCollection(
      kind: kind,
      id: item.id,
      saved: shouldSave,
      title: item.title,
    );
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

  // ── User playlists ─────────────────────────────────────────────────────

  Future<UserPlaylist> createUserPlaylist(String name) async {
    final repo = audioRepo;
    final trimmed = name.trim();
    final now = DateTime.now();
    final id = '${now.microsecondsSinceEpoch.toRadixString(36)}-'
        '${now.millisecond.toRadixString(36)}';
    final p = UserPlaylist(
      id: id,
      name: trimmed.isEmpty ? 'New playlist' : trimmed,
      songs: const [],
      createdAt: now,
      updatedAt: now,
    );
    _userPlaylists = [p, ..._userPlaylists];
    notifyListeners();
    AnalyticsService.instance.logPlaylistCreate(id: p.id, name: p.name);
    if (repo != null) {
      // Fire-and-forget persistence — UI already swapped in the new list.
      try {
        await repo.library.upsertUserPlaylist(p);
      } catch (e) {
        debugPrint('[library] createUserPlaylist persist failed: $e');
      }
    }
    return p;
  }

  // ── Spotify import ──────────────────────────────────────────────────────
  //
  // Anyone can paste a public Spotify playlist URL. The backend scrapes
  // it through headless Chrome and maps each track to a Saavn song;
  // takes ~80 s for a 300-track playlist. The UI runs it on a background
  // future, surfaces a persistent banner across all screens while it's
  // in flight, and saves the result as a regular UserPlaylist on
  // completion — so the imported result is indistinguishable from a
  // hand-built playlist after the fact.
  //
  // Single import at a time. Kicking off a second one while one is in
  // flight is a no-op (the banner stays as-is) + a toast nudge.

  SpotifyImportState _spotifyImport = const SpotifyImportState.idle();
  SpotifyImportState get spotifyImport => _spotifyImport;

  Future<void> importSpotifyPlaylist(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      flashToast('Paste a Spotify playlist URL');
      return;
    }
    if (_spotifyImport.status == SpotifyImportStatus.fetching) {
      flashToast('Already importing — finish or dismiss first');
      return;
    }
    final apiClient = api;
    if (apiClient == null) {
      flashToast('Backend not configured');
      return;
    }
    _spotifyImport = SpotifyImportState(
      status: SpotifyImportStatus.fetching,
      sourceUrl: trimmed,
      startedAt: DateTime.now(),
    );
    notifyListeners();
    try {
      final result = await apiClient.importSpotifyPlaylist(trimmed);
      final songs = result.matchedSongs;
      if (songs.isEmpty) {
        _spotifyImport = SpotifyImportState(
          status: SpotifyImportStatus.failed,
          sourceUrl: trimmed,
          sourceName: result.source.name,
          errorMessage: 'No tracks could be matched on Saavn',
        );
        notifyListeners();
        return;
      }
      // Persist as a UserPlaylist so the rest of the library handles it
      // identically to a hand-built playlist (renaming, deleting,
      // reordering, "add to queue", etc. all work without specialcasing).
      final now = DateTime.now();
      final id = '${now.microsecondsSinceEpoch.toRadixString(36)}-'
          '${now.millisecond.toRadixString(36)}';
      final playlist = UserPlaylist(
        id: id,
        name: result.source.name.trim().isEmpty
            ? 'Spotify playlist'
            : result.source.name.trim(),
        songs: songs,
        createdAt: now,
        updatedAt: now,
      );
      _userPlaylists = [playlist, ..._userPlaylists];
      notifyListeners();
      AnalyticsService.instance.logPlaylistCreate(
        id: playlist.id,
        name: playlist.name,
      );
      final repo = audioRepo;
      if (repo != null) {
        try {
          await repo.library.upsertUserPlaylist(playlist);
        } catch (e) {
          debugPrint('[library] spotify import persist failed: $e');
        }
      }
      _spotifyImport = SpotifyImportState(
        status: SpotifyImportStatus.completed,
        sourceUrl: trimmed,
        sourceName: playlist.name,
        newPlaylistId: playlist.id,
        totalTracks: result.summary.total,
        matchedTracks: result.summary.matched,
      );
      notifyListeners();
    } catch (e) {
      _spotifyImport = SpotifyImportState(
        status: SpotifyImportStatus.failed,
        sourceUrl: trimmed,
        errorMessage: _humaniseImportError(e),
      );
      notifyListeners();
    }
  }

  /// Clear a completed / failed import banner. Idempotent.
  void dismissSpotifyImport() {
    if (_spotifyImport.status == SpotifyImportStatus.idle) return;
    _spotifyImport = const SpotifyImportState.idle();
    notifyListeners();
  }

  static String _humaniseImportError(Object e) {
    final raw = e.toString();
    if (raw.contains('SocketException') || raw.contains('timeout')) {
      return 'Network issue — check connection and retry';
    }
    if (raw.contains('502') || raw.contains('Could not extract')) {
      return 'Couldn’t open that playlist — check the URL';
    }
    return 'Import failed';
  }

  Future<void> renameUserPlaylist(String id, String name) async {
    final repo = audioRepo;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final current = userPlaylistById(id);
    if (current == null) return;
    final updated = current.copyWith(name: trimmed, updatedAt: DateTime.now());
    _userPlaylists = [
      updated,
      for (final p in _userPlaylists)
        if (p.id != id) p,
    ];
    notifyListeners();
    if (repo != null) {
      try {
        await repo.library.upsertUserPlaylist(updated);
      } catch (e) {
        debugPrint('[library] renameUserPlaylist failed: $e');
      }
    }
  }

  Future<void> deleteUserPlaylist(String id) async {
    final repo = audioRepo;
    _userPlaylists = _userPlaylists.where((p) => p.id != id).toList();
    notifyListeners();
    if (repo != null) {
      try {
        await repo.library.deleteUserPlaylist(id);
      } catch (e) {
        debugPrint('[library] deleteUserPlaylist failed: $e');
      }
    }
  }

  Future<void> addSongToUserPlaylist(String playlistId, FeedItem song) async {
    final repo = audioRepo;
    final current = userPlaylistById(playlistId);
    if (current == null) return;
    if (current.songs.any((s) => s.id == song.id)) {
      flashToast('Already in “${current.name}”');
      return;
    }
    final updated = current.copyWith(
      songs: [...current.songs, song],
      updatedAt: DateTime.now(),
    );
    _userPlaylists = [
      updated,
      for (final p in _userPlaylists)
        if (p.id != playlistId) p,
    ];
    flashToast('Added to “${current.name}”');
    notifyListeners();
    AnalyticsService.instance.logPlaylistAddSong(
      playlistId: playlistId,
      songId: song.id,
    );
    if (repo != null) {
      try {
        await repo.library.upsertUserPlaylist(updated);
      } catch (e) {
        debugPrint('[library] addSongToUserPlaylist failed: $e');
      }
    }
  }

  Future<void> removeSongFromUserPlaylist(
      String playlistId, String songId) async {
    final repo = audioRepo;
    final current = userPlaylistById(playlistId);
    if (current == null) return;
    final updated = current.copyWith(
      songs: current.songs.where((s) => s.id != songId).toList(),
      updatedAt: DateTime.now(),
    );
    _userPlaylists = [
      updated,
      for (final p in _userPlaylists)
        if (p.id != playlistId) p,
    ];
    notifyListeners();
    if (repo != null) {
      try {
        await repo.library.upsertUserPlaylist(updated);
      } catch (e) {
        debugPrint('[library] removeSongFromUserPlaylist failed: $e');
      }
    }
  }

  Future<void> playUserPlaylist(UserPlaylist p,
      {int startIndex = 0}) async {
    if (p.songs.isEmpty) {
      flashToast('“${p.name}” is empty');
      return;
    }
    AnalyticsService.instance.logPlaylistPlay(
      playlistId: p.id,
      songCount: p.songs.length,
    );
    await playApiQueue(p.songs, startIndex,
        sourceLabel: 'PLAYLIST · ${p.name}');
  }

  // ── Podcasts: subscribe + episode progress ────────────────────────────

  /// Toggle the subscribe state on a podcast show. Optimistic; persists
  /// via LibraryStore. Show payload must be the FeedItem-shaped result
  /// from the podcasts API so cards in the Library tab render correctly
  /// without a re-fetch.
  Future<void> toggleSubscribedPodcast(FeedItem show) async {
    final repo = audioRepo;
    if (repo == null) return;
    final wasSubscribed = _subscribedPodcastIds.contains(show.id);
    final shouldSubscribe = !wasSubscribed;
    _subscribedPodcastIds = {..._subscribedPodcastIds};
    if (shouldSubscribe) {
      _subscribedPodcastIds.add(show.id);
      _subscribedPodcasts = [
        show,
        ..._subscribedPodcasts.where((s) => s.id != show.id),
      ];
    } else {
      _subscribedPodcastIds.remove(show.id);
      _subscribedPodcasts =
          _subscribedPodcasts.where((s) => s.id != show.id).toList();
    }
    flashToast(shouldSubscribe
        ? 'Subscribed to ${show.title}'
        : 'Unsubscribed from ${show.title}');
    notifyListeners();
    try {
      final next = await repo.library
          .setSubscribedPodcast(show: show, subscribed: shouldSubscribe);
      _subscribedPodcasts = next;
      _subscribedPodcastIds = next.map((s) => s.id).toSet();
      notifyListeners();
    } catch (e) {
      debugPrint(
          '[library] toggleSubscribedPodcast(${show.id}) failed: $e');
    }
  }

  /// Persist `positionSec` for `episodeId`. Throttled at the caller side
  /// — `_pushPlayedHistory` is the natural trigger when the player
  /// advances OFF an episode. In-memory map is updated before the Hive
  /// write so subsequent `episodeProgressSec` lookups are synchronous.
  Future<void> saveEpisodeProgress(String episodeId, int positionSec) async {
    final repo = audioRepo;
    if (episodeId.isEmpty || repo == null) return;
    _episodeProgress[episodeId] = positionSec;
    try {
      await repo.library.saveEpisodeProgress(episodeId, positionSec);
    } catch (e) {
      debugPrint('[library] saveEpisodeProgress($episodeId) failed: $e');
    }
  }

  Future<void> clearEpisodeProgress(String episodeId) async {
    final repo = audioRepo;
    if (episodeId.isEmpty || repo == null) return;
    _episodeProgress.remove(episodeId);
    try {
      await repo.library.clearEpisodeProgress(episodeId);
    } catch (e) {
      debugPrint('[library] clearEpisodeProgress($episodeId) failed: $e');
    }
  }

  Future<void> moveSongInUserPlaylist(
      String playlistId, int from, int to) async {
    final repo = audioRepo;
    final current = userPlaylistById(playlistId);
    if (current == null) return;
    if (from < 0 || from >= current.songs.length) return;
    if (to < 0 || to > current.songs.length) return;
    final reordered = [...current.songs];
    final moved = reordered.removeAt(from);
    // ReorderableListView reports `to` as the index AFTER removal — the
    // semantics match List.insert directly only when moving up. When
    // moving down, the framework passes a `to` that's one too high. The
    // canonical idiom is to subtract 1 in that case.
    final insertAt = from < to ? to - 1 : to;
    reordered.insert(insertAt, moved);
    final updated = current.copyWith(
      songs: reordered,
      updatedAt: DateTime.now(),
    );
    _userPlaylists = [
      updated,
      for (final p in _userPlaylists)
        if (p.id != playlistId) p,
    ];
    notifyListeners();
    if (repo != null) {
      try {
        await repo.library.upsertUserPlaylist(updated);
      } catch (e) {
        debugPrint('[library] moveSongInUserPlaylist failed: $e');
      }
    }
  }

  /// Shuffle-and-play a song list. Picks a random start index so the user
  /// doesn't always hear the same song first when they hit shuffle on a
  /// playlist, then flips the shuffle flag on so mpv reorders the queue.
  Future<void> playShuffled(
    List<FeedItem> songs, {
    String? sourceLabel,
  }) async {
    if (songs.isEmpty) return;
    final startIndex =
        songs.length == 1 ? 0 : Random().nextInt(songs.length);
    await playApiQueue(songs, startIndex, sourceLabel: sourceLabel);
    if (!shuffle) {
      // toggleShuffle pushes to mpv, which rearranges the queue while
      // keeping the currently-playing track in place.
      toggleShuffle();
    }
  }

  /// Full liked list — newest-first.
  List<FeedItem> get likedSongs => _likedSongs;
  List<FeedItem> get likedStations => _likedStations;
  bool isLikedStationId(String id) => _likedStationIds.contains(id);

  /// Last-played API songs — newest-first, capped at LibraryStore's max.
  List<FeedItem> get playedHistory => _playedHistory;

  /// O(1) liked check by song id. Use for heart icons in lists.
  bool isLikedId(String id) => _likedIds.contains(id);

  /// True when the currently-playing API item is liked. Drives the
  /// heart in the expanded + mini players. Reads from the **correct**
  /// bucket — songs go to liked songs, radio stations go to liked
  /// stations — so a hearted station shows hearted on the player and
  /// vice versa.
  bool get isLikedCurrentApi {
    final song = currentApiSong;
    if (song == null) return likedCurrent; // dummy-path fallback
    if (song.type == 'radio_station') {
      return _likedStationIds.contains(song.id);
    }
    return _likedIds.contains(song.id);
  }

  /// Dispatcher — routes the heart action to the right bucket based on
  /// the item's `type`. Radio stations go to [toggleLikedStation],
  /// everything else (songs, episodes-treated-as-songs, …) goes to
  /// [toggleLikedSong]. Use this from the player UI; surfaces that
  /// know they're dealing with a song specifically can call
  /// [toggleLikedSong] directly.
  Future<void> toggleLikedApi(FeedItem item) =>
      item.type == 'radio_station'
          ? toggleLikedStation(item)
          : toggleLikedSong(item);

  /// Like / unlike a radio station. Independent bucket from
  /// [toggleLikedSong] so hearting a station doesn't dump it into the
  /// "Liked songs" list.
  Future<void> toggleLikedStation(FeedItem station) async {
    final repo = audioRepo;
    if (repo == null) return;
    final wasLiked = _likedStationIds.contains(station.id);
    final shouldLike = !wasLiked;
    _likedStationIds = {..._likedStationIds};
    if (shouldLike) {
      _likedStationIds.add(station.id);
      _likedStations = [
        station,
        ..._likedStations.where((s) => s.id != station.id),
      ];
    } else {
      _likedStationIds.remove(station.id);
      _likedStations =
          _likedStations.where((s) => s.id != station.id).toList();
    }
    flashToast(shouldLike ? 'Added to Liked stations' : 'Removed from Liked stations');
    notifyListeners();
    AnalyticsService.instance
        .logLike(station.id, liked: shouldLike, title: station.title);
    try {
      final next = await repo.library
          .setLikedStation(station: station, liked: shouldLike);
      _likedStations = next;
      _likedStationIds = next.map((s) => s.id).toSet();
      notifyListeners();
    } catch (e) {
      debugPrint('[library] toggleLikedStation failed for ${station.id}: $e');
    }
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
    AnalyticsService.instance
        .logLike(song.id, liked: shouldLike, title: song.title);
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
    //
    // Gated by `!isCasting` — when a Cast session is live, the receiver
    // owns the play-head and the cast position stream drives positionTick.
    // mpv is muted but still ticks its own position from 0, which would
    // clobber the cast position if we didn't gate here.
    int lastPersistedSec = 0;
    _audioSubs.add(handler.positionStream.listen((pos) {
      if (isCasting) return;
      if (currentApiSong == null) return; // dummy clock still owns the tick
      final secs = pos.inSeconds;
      // Restore guard — see `_restoredPositionGuard` for the why. mpv
      // reports position 0 while the file is loaded-but-paused (the
      // `file-local-options/start` only applies once playback begins);
      // without this gate, that 0 would overwrite the restored value
      // before the user ever hit play.
      if (_restoredPositionGuard > 0 && secs == 0) return;
      if (_restoredPositionGuard > 0 && secs > 0) _restoredPositionGuard = 0;
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
    // ICY title from live streams — "Now Playing: Artist - Song" or
    // similar metadata embedded in the audio stream. Only meaningful
    // in PlayMode.live; for track-mode the handler emits null on every
    // track change (no-op for the UI).
    _audioSubs.add(handler.icyTitleStream.listen((title) {
      final clean = (title ?? '').trim();
      final next = clean.isEmpty ? null : clean;
      if (next != _icyTitle) {
        _icyTitle = next;
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
      // Cast handoff for queue advances. mpv's playlist drives `next`
      // even when casting (mpv is muted) so we always know what comes
      // next — we just need to forward it to the receiver.
      if (isCasting) {
        unawaited(_pushCurrentSongToCast(song));
      }
      // Sleep-timer end-of-track check fires AFTER the swap so the new
      // currentApiSong.id is what `_onTrackChangedForSleep` compares to.
      _onTrackChangedForSleep(song.id);
      // Extend the queue with a radio prime when this advance lands us on
      // the last entry and autoplay is enabled. No-op when off.
      _maybeAutoplayPrime();
      notifyListeners();
    }));
  }

  /// Resolve [song] to a network URL and load it onto the active Cast
  /// session. Called for queue advances + new song selections while
  /// casting + mid-track URL refreshes. Skips the LocalSourceProvider
  /// tier (cast device can't reach `file://`) and force-refreshes so
  /// the receiver gets a fresh signed URL.
  Future<void> _pushCurrentSongToCast(
    FeedItem song, {
    Duration position = Duration.zero,
  }) async {
    final repo = audioRepo;
    if (repo == null) return;
    try {
      final resolved =
          await repo.resolver.resolve(song, forceRefresh: true, network: true);
      final ok = await CastService.instance.loadSong(
        song: song,
        url: resolved.url,
        position: position,
      );
      if (!ok) {
        debugPrint('[cast] push loadSong failed');
      }
    } catch (e, st) {
      debugPrint('[cast] push failed: $e\n$st');
    }
  }

  Future<void> _pushPlayedHistory(FeedItem song) async {
    final repo = audioRepo;
    if (repo == null) return;
    // For podcast episodes, save the position the listener stopped at
    // so the next open resumes there. Music tracks reset on track
    // change (different listening model).
    if (song.type == 'episode') {
      final pos = position;
      final dur = currentDurationSec;
      // Don't save if we're at the very end (the user finished); clear
      // any prior progress so re-listens start from scratch.
      if (dur > 0 && pos >= dur - 5) {
        unawaited(clearEpisodeProgress(song.id));
      } else if (pos > 30) {
        unawaited(saveEpisodeProgress(song.id, pos));
      }
    }
    // Optimistic update so the Library tab sees the entry immediately.
    _playedHistory = [
      song,
      ..._playedHistory.where((s) => s.id != song.id),
    ];
    if (_playedHistory.length > 50) {
      _playedHistory = _playedHistory.sublist(0, 50);
    }
    // Analytics: fired here (not on `playApiQueue` start) so we only
    // count tracks the user actually heard — history-push is called
    // when the player advances OFF a track. Mirrors RN's `useHistoryStore`.
    AnalyticsService.instance.logSongPlay(
      id: song.id,
      title: song.title,
      artist: (song.artists ?? const []).isNotEmpty
          ? song.artists!.first.name
          : null,
      provider: song.source,
      sourceLabel: apiSourceLabel,
    );
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
    // Track change invalidates any pending restore guard — we're past the
    // restored track now and subsequent 0-reports from mpv (e.g. a new
    // track loading paused) shouldn't be filtered.
    _restoredPositionGuard = 0;
    // ICY metadata is per-stream; clear so the UI doesn't briefly show
    // the previous station's "Now Playing" against the new song's title.
    _icyTitle = null;
    _refreshExtractedAccent(song.artwork);
    // Episode resume: when an episode becomes active and we have a
    // saved position for it, seek there. The seek queues against
    // mpv's load — mpv resolves it as soon as the file opens. Skip
    // very small positions to avoid the "jumped 5s ahead" feel on
    // fresh starts.
    if (song.type == 'episode') {
      final saved = _episodeProgress[song.id] ?? 0;
      if (saved > 30) {
        // ignore: discarded_futures
        Future<void>.delayed(const Duration(milliseconds: 600), () {
          if (currentApiSong?.id != song.id) return; // moved on already
          audioRepo?.seek(Duration(seconds: saved));
        });
      }
    }
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

  /// Bulk-append every [songs] entry to the end of the queue. Issues a
  /// single summary toast at the end so the user doesn't get a flood of
  /// per-track confirmations when adding a whole album.
  Future<void> addApiSongsToQueue(List<FeedItem> songs) async {
    if (songs.isEmpty) return;
    final repo = audioRepo;
    if (repo == null) {
      flashToast('Audio engine unavailable');
      return;
    }
    for (final s in songs) {
      await repo.addToQueue(s);
    }
    flashToast(
        'Added ${songs.length} ${songs.length == 1 ? 'track' : 'tracks'} to queue');
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
    // Surface the live-vs-track distinction so the player UI can adapt
    // (no scrubber / no skip buttons / no queue UI for radios).
    _isLive = mode == PlayMode.live;
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
      // mpv always loads the queue — even while casting. mpv is muted
      // (setVolume(0) on cast connect) so it produces no sound; we keep
      // it loaded so its playlist + index stay the queue source of truth
      // for skipToNext / repeat / shuffle. AUTO-advances within the
      // queue forward to the receiver via the currentSongStream listener
      // in _bindAudio.
      await repo.playQueue(songs, startIndex,
          sourceLabel: sourceLabel, sourceRef: sourceRef, mode: mode);
      // Tap-to-play handoff: `_applySong(startSong)` above already set
      // `currentApiSong = startSong`. By the time mpv's
      // currentSongStream emits `startSong`, the listener at the top of
      // _bindAudio short-circuits with "already in sync" and skips the
      // cast push inside it. Push explicitly here so the receiver
      // actually switches to the new track. Without this, the cast
      // device kept playing the previous song when the user tapped a
      // new one in search / albums / playlists.
      if (isCasting) {
        unawaited(_pushCurrentSongToCast(startSong));
      }
      // `currentSongStream` only fires on *changes*, so a 1-track queue
      // (search→play, single hero tap, etc.) never triggers the per-track
      // autoplay check. Probe here so endless autoplay still extends those
      // queues.
      _maybeAutoplayPrime();
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
      languages: selectedLanguages.toList(),
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
    AnalyticsService.instance.logEqPresetApply(presetId: preset.id);
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
    // Cast routing — when a Cast session is live, the receiver is the
    // source of truth. mpv stays paused; the cast service forwards
    // commands to the device. Position state on the phone is best-
    // effort until v2 wires the mediaStatus → positionTick bridge.
    if (isCasting) {
      if (isPlaying) {
        CastService.instance.play();
      } else {
        CastService.instance.pause();
      }
      notifyListeners();
      return;
    }
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

  // ── Chromecast ────────────────────────────────────────────────────────
  //
  // Tap of the cast button hands control of the active song to a Cast
  // receiver. The phone becomes a remote controller: mpv pauses, the
  // receiver fetches the network URL itself + reports back. On
  // disconnect we resume on mpv from the last known position.
  //
  // Only basic transport is wired in v1 (play / pause / disconnect).
  // Mid-track URL refresh on Cast, queue advance while casting, and
  // position sync from the receiver are v2.

  /// True when the currently-playing item is a live stream
  /// (`PlayMode.live` in the audio handler). Drives player-UI
  /// adaptations: hide the scrubber, hide skip-prev/skip-next, etc.
  /// — live streams have no duration / position / next-track. Set by
  /// `playApiQueue` from its `mode` param; cleared back to false the
  /// next time a track-mode queue is loaded.
  bool _isLive = false;
  bool get isLive => _isLive;

  /// "Now playing" track metadata from the live stream's ICY/Shoutcast
  /// title field. Format is usually "Artist - Song" but it's free-text
  /// — anything from "Diverse FM - Tum Hi Ho" to "ad break" can land
  /// here. Null when not in live mode OR the upstream hasn't emitted
  /// any metadata yet. UI uses this as the primary text in player
  /// surfaces (mini + expanded) when set, falling back to the station
  /// name otherwise.
  String? _icyTitle;
  String? get icyTitle => _icyTitle;

  bool _isCasting = false;
  // Stamp the moment a cast session goes live so logCastDisconnect can
  // attach a session length when it fires later. Null while no session.
  DateTime? _castConnectedAt;
  String? _castDeviceName;

  bool get isCasting => _isCasting;
  String? get castDeviceName => _castDeviceName;

  StreamSubscription? _castSessionSub;
  StreamSubscription? _castPositionSub;
  StreamSubscription? _castStatusSub;
  StreamSubscription? _castTrackEndedSub;
  StreamSubscription? _castErrorSub;
  StreamSubscription? _castRefreshSub;

  void _wireCast() {
    _castSessionSub?.cancel();
    _castPositionSub?.cancel();
    _castStatusSub?.cancel();
    _castTrackEndedSub?.cancel();
    _castErrorSub?.cancel();
    _castRefreshSub?.cancel();

    _castSessionSub =
        CastService.instance.sessionStream.listen((session) async {
      final nowConnected = CastService.instance.isConnected;
      final wasCasting = _isCasting;
      _isCasting = nowConnected;
      _castDeviceName = session?.device?.friendlyName;

      if (!wasCasting && nowConnected) {
        // Just connected → mute mpv (avoid double-audio if mpv's
        // playback bleeds during the handoff), flip the audio_service
        // bridge into cast-override mode (so the lockscreen notification
        // reflects the cast device, not mpv's now-paused state), and
        // hand off the current song.
        try {
          await audioRepo?.handler.setVolume(0);
        } catch (_) {}
        audioRepo?.bridge?.setCastingActive(
          active: true,
          playing: isPlaying,
          position: Duration(seconds: position),
        );
        _castConnectedAt = DateTime.now();
        AnalyticsService.instance
            .logCastConnect(_castDeviceName ?? 'unknown');
        await _handOffToCast();
      } else if (wasCasting && !nowConnected) {
        // Just disconnected → drop cast-override (bridge resumes
        // mirroring mpv), restore mpv volume + seek + resume.
        audioRepo?.bridge?.setCastingActive(
          active: false,
          playing: isPlaying,
          position: Duration(seconds: position),
        );
        final connectedAt = _castConnectedAt;
        _castConnectedAt = null;
        AnalyticsService.instance.logCastDisconnect(
          sessionLength:
              connectedAt == null ? null : DateTime.now().difference(connectedAt),
        );
        await _resumeOnPhone();
      }
      notifyListeners();
    });

    // Position stream from the Cast receiver. While casting we want the
    // scrubber to track the cast device's playhead, not mpv's stale 0.
    // Also push to audio_service so the lockscreen notification's
    // scrubber moves in step with the receiver.
    _castPositionSub =
        CastService.instance.positionStream.listen((pos) {
      if (!_isCasting) return;
      final secs = pos.inSeconds;
      if (secs != position) position = secs;
      audioRepo?.bridge?.setCastingPlaybackState(
        playing: isPlaying,
        position: pos,
      );
    });

    // Cast media status flips between playing / paused independently
    // (e.g. user paused via Google Home app). Mirror that to isPlaying
    // so the in-app UI + notification stay correct.
    _castStatusSub?.cancel();
    _castStatusSub =
        CastService.instance.mediaStatusStream.listen((status) {
      if (!_isCasting || status == null) return;
      final castPlaying =
          status.playerState == CastMediaPlayerState.playing;
      if (castPlaying != isPlaying) {
        isPlaying = castPlaying;
        audioRepo?.bridge?.setCastingPlaybackState(
          playing: isPlaying,
          position: CastService.instance.lastReportedPosition,
        );
        notifyListeners();
      }
    });

    // Cast track ended → advance the queue, honoring repeat mode.
    //   - LoopMode.one  : re-push the same song at position 0. mpv's
    //                     native loop-file works for it (muted), but
    //                     we have to drive the receiver explicitly.
    //   - LoopMode.all  : at end-of-queue, jump back to 0 and let the
    //                     existing `currentSongStream` listener push;
    //                     otherwise plain repo.next().
    //   - LoopMode.off  : at end-of-queue, stop cleanly (isPlaying=
    //                     false, position at song end). Otherwise
    //                     repo.next().
    _castTrackEndedSub =
        CastService.instance.trackEndedStream.listen((_) async {
      if (!_isCasting) return;
      final repo = audioRepo;
      if (repo == null) return;
      if (repo.queue.isEmpty) return;

      if (repeat == LoopMode.one) {
        final song = currentApiSong;
        if (song != null) {
          unawaited(_pushCurrentSongToCast(song));
        }
        return;
      }

      final isLast = repo.currentIndex >= repo.queue.length - 1;
      if (isLast) {
        if (repeat == LoopMode.all) {
          // Wrap to the top.
          await repo.jumpToIndex(0);
        } else {
          // Clean stop at end of queue.
          isPlaying = false;
          flashToast('End of queue');
          notifyListeners();
        }
        return;
      }
      await repo.next();
    });

    // Cast media error (network drop, bad URL, segment fetch fail on
    // HLS) → re-resolve + reload at the receiver's last known position
    // so playback can pick back up where it left off.
    _castErrorSub =
        CastService.instance.mediaErrorStream.listen((_) async {
      if (!_isCasting) return;
      final song = currentApiSong;
      if (song == null) return;
      final at = CastService.instance.lastReportedPosition;
      debugPrint('[cast] media error @ ${at.inSeconds}s — re-pushing');
      unawaited(_pushCurrentSongToCast(song, position: at));
    });

    // Proactive signed-URL refresh ~5 min before expiry. Same defense-
    // in-depth pattern as mpv's url_refresh.dart, mirrored onto the
    // cast receiver so long albums/playlists don't trip 403s mid-track.
    _castRefreshSub =
        CastService.instance.refreshNeededStream.listen((_) async {
      if (!_isCasting) return;
      final song = currentApiSong;
      if (song == null) return;
      final at = CastService.instance.lastReportedPosition;
      debugPrint('[cast] proactive URL refresh @ ${at.inSeconds}s');
      unawaited(_pushCurrentSongToCast(song, position: at));
    });
  }

  Future<void> _handOffToCast() async {
    final song = currentApiSong;
    final repo = audioRepo;
    if (song == null || repo == null) {
      // Nothing to play; user can still pick songs and they'll cast.
      return;
    }
    final wasPlaying = isPlaying;
    final atPosition = Duration(seconds: position);
    try {
      await repo.handler.pause();
    } catch (_) {}
    // Skip the local downloads tier — the Cast receiver needs a public
    // network URL it can fetch. forceRefresh also drops the resolver
    // cache so we hand the receiver a fresh signed URL.
    final resolved = await repo.resolver
        .resolve(song, forceRefresh: true, network: true);
    final ok = await CastService.instance.loadSong(
      song: song,
      url: resolved.url,
      position: atPosition,
    );
    if (ok) {
      isPlaying = wasPlaying;
      flashToast('Casting to ${_castDeviceName ?? "device"}');
    } else {
      flashToast('Couldn’t start cast');
    }
    notifyListeners();
  }

  Future<void> _resumeOnPhone() async {
    final repo = audioRepo;
    if (repo == null) return;
    // Restore mpv's volume (was muted during cast) and hand the play
    // head back from the cast device. mpv is currently sitting paused
    // at the pre-cast position; seek to wherever the cast device left
    // off, then resume if the user was playing.
    try {
      await repo.handler.setVolume(100);
    } catch (_) {}
    final lastCastPos = CastService.instance.lastReportedPosition;
    if (lastCastPos > Duration.zero) {
      try {
        await repo.seek(lastCastPos);
      } catch (_) {}
      position = lastCastPos.inSeconds;
    }
    if (isPlaying) {
      await repo.play();
    }
    flashToast('Resumed on phone');
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
    // Explicit user seek — drop the restore guard so subsequent mpv
    // 0-reports (e.g. scrubbing to 0) are honored normally.
    _restoredPositionGuard = 0;
    // Cast routing — when a session is active the receiver owns playback.
    // Send the seek to it; mpv stays where it is (muted) and will be
    // re-synced at disconnect via `_resumeOnPhone`.
    if (isCasting) {
      CastService.instance.seek(Duration(seconds: position));
      notifyListeners();
      return;
    }
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
    // ReorderableList and mpv's `playlist-move from to` use the SAME
    // "take the place of entry at <to>" convention — `to` is a
    // BEFORE-removal index. No offset is needed; pass through directly.
    // (We previously subtracted 1 here for Dart's `list.insert`, but
    // with mpv driving the playlist that semantic flipped.)
    final base = repo.currentIndex + 1;
    await repo.moveInQueue(base + oldIndex, base + newIndex);
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

  // ── Endless autoplay ───────────────────────────────────────────────────
  Future<void> setEndlessAutoplay(bool enabled) async {
    if (endlessAutoplay == enabled) return;
    endlessAutoplay = enabled;
    notifyListeners();
    await audioRepo?.settings.savePlayback(endlessAutoplay: enabled);
    // Turning it on while the user is already on the last track: prime
    // immediately so the queue extends without waiting for the next
    // track-change event (which only fires on advance).
    if (enabled) _maybeAutoplayPrime();
  }

  /// Privacy: flip Firebase Analytics collection on/off. Disable hits
  /// Firebase's own `setAnalyticsCollectionEnabled` AND resets the
  /// local install id (severs the link between any new install and
  /// already-collected events). Persisted so the choice survives
  /// restart.
  Future<void> setAnalyticsEnabled(bool enabled) async {
    if (analyticsEnabled == enabled) return;
    analyticsEnabled = enabled;
    notifyListeners();
    await audioRepo?.settings.saveAnalyticsEnabled(enabled);
    await AnalyticsService.instance.setEnabled(enabled);
  }

  /// Called from the `currentSongStream` listener (and once at the tail of
  /// `playApiQueue` for single-song queues). Checks whether autoplay is on
  /// AND we're now on the last queue entry AND no prime is already in
  /// flight; if so, fires a fresh radio session seeded by [currentApiSong]
  /// and appends the songs to the queue.
  void _maybeAutoplayPrime() {
    if (!endlessAutoplay) {
      // ignore: avoid_print
      print('[autoplay] skip: toggle off');
      return;
    }
    if (_autoplayPriming) {
      // ignore: avoid_print
      print('[autoplay] skip: already priming');
      return;
    }
    final repo = audioRepo;
    final apiClient = api;
    if (repo == null || apiClient == null) {
      // ignore: avoid_print
      print('[autoplay] skip: repo=${repo == null ? 'null' : 'ok'} '
          'api=${apiClient == null ? 'null' : 'ok'}');
      return;
    }
    final seed = currentApiSong;
    if (seed == null) {
      // ignore: avoid_print
      print('[autoplay] skip: currentApiSong null');
      return;
    }
    final q = repo.queue;
    if (q.isEmpty) {
      // ignore: avoid_print
      print('[autoplay] skip: queue empty');
      return;
    }
    // Threshold-based trigger: fire when there are AT MOST
    // `_autoplayPrimeThreshold` tracks left after the current one.
    // The previous "only on the very last entry" check gave the
    // network round trip zero headroom — if the user rapid-tapped
    // next, the player ran out of queue before the prime's serial
    // addToQueue loop could land, the EOF event cleared the queue,
    // and autoplay silently failed. The threshold matches RN's
    // `useAutoQueue` shape.
    final remaining = q.length - repo.currentIndex - 1;
    if (remaining > _autoplayPrimeThreshold) {
      // ignore: avoid_print
      print('[autoplay] skip: $remaining tracks ahead '
          '(idx=${repo.currentIndex}, len=${q.length}, '
          'threshold=$_autoplayPrimeThreshold)');
      return;
    }
    _autoplayPriming = true;
    // ignore: discarded_futures
    _runAutoplayPrime(seed, apiClient, repo);
  }

  /// Fire the prime when fewer than this many tracks remain after the
  /// active one. 3 gives ~3-track buffer for the recommendation fetch
  /// + serial addToQueue loop to complete (~1-2s on a healthy network)
  /// before the user reaches the end of the queue.
  static const int _autoplayPrimeThreshold = 3;

  Future<void> _runAutoplayPrime(
      FeedItem seed, SunohApi apiClient, AudioRepo repo) async {
    // Backed by `/music/recommend` — a single call that internally hits
    // Saavn's reco.getreco + the song-detail sections + a derived radio
    // station + the explicit Similar Songs endpoint, merges + dedupes
    // them, and filters out the seed. Replaces the older two-step
    // (radio/session + radio/<id>) which sometimes returned 0 songs
    // for Gaana seeds and required a client-side Saavn pivot.
    //
    // We pass both `q` (so the backend can search Saavn when the seed
    // is a Gaana slug) and `songId` (used directly when the seed is
    // already a Saavn id). The backend prefers songId over q.
    final lang = (seed.language ?? '').isNotEmpty
        ? seed.language
        : selectedLanguagesCsv;
    final isSaavnId = (seed.source ?? '').toLowerCase() == 'saavn';
    final q = '${seed.title} ${seed.subtitle ?? ''}'.trim();
    // Capture playback state at prime start so we can recover if the
    // user blew through the queue end during the in-flight fetch.
    // `wasPlaying` is the only honest signal of intent — if the user
    // had paused before the prime fired, we don't auto-resume.
    // `origQueueLen` is the threshold for "user reached the end of the
    // original queue" — without this check, a user who manually
    // pauses mid-queue AFTER the threshold trigger would get force-
    // restarted when prime lands. We only resume when the user is at
    // (or past) the original last track, i.e. they actually ran out.
    final wasPlaying = isPlaying;
    final origQueueLen = repo.queue.length;
    final resumeIndex = repo.currentIndex + 1;
    // ignore: avoid_print
    print('[autoplay] priming recs from id="${seed.id}" '
        'title="${seed.title}" source="${seed.source ?? '?'}" '
        'wasPlaying=$wasPlaying resumeIndex=$resumeIndex');
    try {
      final songs = await apiClient.fetchRecommendations(
        // Only pass songId when we're sure it's a Saavn id; for Gaana
        // seeds the backend's q-based search produces a clean songId
        // internally.
        songId: isSaavnId ? seed.id : null,
        query: q,
        lang: lang,
      );
      if (songs.isEmpty) {
        // ignore: avoid_print
        print('[autoplay] prime failed — 0 recommendations');
        return;
      }
      // Three-layer dedup before appending:
      //   1. By Saavn songId — catches exact repeats from the queue.
      //   2. By a normalized "title | primary artist | duration" key —
      //      catches near-duplicates Saavn ships as separate ids: e.g.
      //      "Gehra Hua" and "Gehra Hua (From \"Dhurandhar\")" are the
      //      same recording with different titles. RN's findBestMatch
      //      uses a similar normalization.
      //   3. Within the new batch itself — Saavn's reco aggregation can
      //      return both versions inside the same response.
      final queueIds = repo.queue.map((s) => s.id).toSet();
      final seenKeys = <String>{
        _autoplayDedupKey(seed),
        for (final s in repo.queue) _autoplayDedupKey(s),
      };
      final filtered = <FeedItem>[];
      var idDups = 0;
      var titleDups = 0;
      for (final s in songs) {
        if (queueIds.contains(s.id)) {
          idDups++;
          continue;
        }
        final key = _autoplayDedupKey(s);
        if (seenKeys.contains(key)) {
          titleDups++;
          continue;
        }
        seenKeys.add(key);
        filtered.add(s);
      }
      // ignore: avoid_print
      print('[autoplay] appending ${filtered.length} song(s) to queue '
          '(api returned ${songs.length}, id-dups=$idDups, title-dups=$titleDups)');
      for (final s in filtered) {
        await repo.addToQueue(s);
      }
      AnalyticsService.instance.logAutoplayPrime(
        songsAppended: filtered.length,
        seedId: seed.id,
      );
      // If the player stopped while we were appending — the race the
      // threshold trigger is supposed to avoid, but can still happen
      // if the user skips fast on a short queue — jump to the first
      // newly-appended track and resume. Three gates:
      //   - wasPlaying: user was actually listening at prime start.
      //   - !isPlaying: player has stopped (vs still going naturally).
      //   - currentIndex >= origQueueLen - 1: user reached or passed
      //     the ORIGINAL last track, so the stop is from running out
      //     of queue (not an intentional pause mid-queue).
      final reachedOriginalEnd = repo.currentIndex >= origQueueLen - 1;
      if (wasPlaying && !isPlaying && filtered.isNotEmpty && reachedOriginalEnd) {
        final newLen = repo.queue.length;
        if (resumeIndex >= 0 && resumeIndex < newLen) {
          // ignore: avoid_print
          print('[autoplay] player died waiting for prime — '
              'jumping to index $resumeIndex of $newLen');
          try {
            await repo.jumpToIndex(resumeIndex);
          } catch (e) {
            // ignore: avoid_print
            print('[autoplay] resume jumpToIndex($resumeIndex) failed: $e');
          }
        }
      }
    } catch (e, st) {
      // ignore: avoid_print
      print('[autoplay] prime threw: $e\n$st');
    } finally {
      _autoplayPriming = false;
    }
  }

  /// Title + primary artist + duration key for catching same-recording-
  /// different-title duplicates from Saavn's recommendation set. Strips
  /// `(From "Xyz")` / `(from Xyz)` / `(In "Xyz")` suffixes that Saavn
  /// uses to disambiguate OST releases of the same recording.
  static final RegExp _autoplayFromSuffix =
      RegExp(r'\s*\((from|in)\s+["“]?[^)]*["”]?\)\s*',
          caseSensitive: false);
  String _autoplayDedupKey(FeedItem s) {
    final title = s.title
        .toLowerCase()
        .replaceAll(_autoplayFromSuffix, ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final primaryArtist = ((s.artists ?? const <ApiArtistRef>[]).isNotEmpty
            ? s.artists!.first.name
            : '')
        .toLowerCase()
        .trim();
    final dur = int.tryParse(s.duration ?? '') ?? 0;
    return '$title|$primaryArtist|$dur';
  }

  // ── Sleep timer API ────────────────────────────────────────────────────
  void armSleepTimer({Duration? duration, bool endOfTrack = false}) {
    cancelSleepTimer(silent: true);
    AnalyticsService.instance.logSleepTimerSet(
      minutes: duration?.inMinutes,
      endOfTrack: endOfTrack,
    );
    if (endOfTrack) {
      sleepAtTrackEnd = true;
      _sleepCapturedSongId = currentApiSong?.id;
    } else if (duration != null && duration.inSeconds > 0) {
      sleepRemaining = duration;
      _sleepTickTimer =
          Timer.periodic(const Duration(seconds: 1), (_) async {
        final r = sleepRemaining;
        if (r == null) return;
        final next = r - const Duration(seconds: 1);
        if (next.inSeconds <= 0) {
          _sleepTickTimer?.cancel();
          _sleepTickTimer = null;
          sleepRemaining = null;
          notifyListeners();
          await _fadeAndPause();
        } else {
          sleepRemaining = next;
          notifyListeners();
        }
      });
    }
    notifyListeners();
  }

  void cancelSleepTimer({bool silent = false}) {
    final wasArmed = sleepArmed;
    _sleepTickTimer?.cancel();
    _sleepTickTimer = null;
    sleepRemaining = null;
    sleepAtTrackEnd = false;
    _sleepCapturedSongId = null;
    if (!silent) notifyListeners();
    // Only log a cancel when something WAS armed — silent re-arm cycles
    // call cancelSleepTimer(silent:true) under the hood.
    if (!silent && wasArmed) AnalyticsService.instance.logSleepTimerCancel();
  }

  // Called from the `currentSongStream` listener (in _bindAudio) when the
  // active track changes. If end-of-track mode is armed AND the captured
  // song was the previous one, pause now.
  void _onTrackChangedForSleep(String? newId) {
    if (!sleepAtTrackEnd) return;
    if (_sleepCapturedSongId == null) return;
    if (newId == _sleepCapturedSongId) return; // unchanged
    final wasArmed = sleepAtTrackEnd;
    cancelSleepTimer(silent: true);
    notifyListeners();
    if (wasArmed) {
      // ignore: discarded_futures
      _fadeAndPause();
    }
  }

  Future<void> _fadeAndPause() async {
    final repo = audioRepo;
    if (repo == null) return;
    // When casting, mpv is muted — fading mpv's volume changes nothing the
    // user can hear. Just pause through the cast layer.
    if (isCasting) {
      await CastService.instance.pause();
      return;
    }
    const totalMs = 1400;
    const steps = 14;
    for (var i = steps; i >= 0; i--) {
      final vol = (i / steps) * 100.0;
      await repo.handler.setVolume(vol);
      await Future<void>.delayed(
          const Duration(milliseconds: totalMs ~/ steps));
    }
    await repo.pause();
    // Restore so the next manual play isn't silent.
    await repo.handler.setVolume(100);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    _toastTimer?.cancel();
    _sleepTickTimer?.cancel();
    for (final s in _audioSubs) {
      s.cancel();
    }
    _castSessionSub?.cancel();
    _castPositionSub?.cancel();
    _castStatusSub?.cancel();
    _castTrackEndedSub?.cancel();
    _castErrorSub?.cancel();
    _castRefreshSub?.cancel();
    positionTick.dispose();
    super.dispose();
  }
}
