// Chromecast / Google Cast integration.
//
// The phone is the *remote control*: the Cast receiver fetches the audio
// URL itself, plays it, and reports state. mpv on the phone goes silent
// while a session is active — AudioRepo routes transport commands to
// whichever backend currently owns playback.
//
// Lifecycle:
//
//   1. `CastService.init()` runs once at startup. Sets the shared
//      `GoogleCastContext` with the default media-receiver app id.
//      Failure is swallowed — devices without Google Play Services
//      simply never discover anything; the rest of the app still works.
//
//   2. Discovery is started lazily on first device-picker open and
//      stopped when the picker closes (saves battery + LAN chatter).
//
//   3. Connecting to a device emits a non-null `currentSession` on
//      `sessionStream`. Loading media is a second explicit step via
//      `loadSong(song, url, position)`.
//
// What this wrapper deliberately doesn't do (yet):
//   * Queue management on Cast — we load tracks one-at-a-time. mpv's
//     internal playlist remains the source of truth for "what's next";
//     when the current Cast item ends we'd push the next song via
//     loadSong again. That advance loop lives in AudioRepo.
//   * Mid-track signed-URL refresh on Cast — Saavn/Gaana URLs can
//     expire mid-album. A follow-up will mirror url_refresh.dart's
//     timer onto the Cast side.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_chrome_cast/cast_context.dart';
import 'package:flutter_chrome_cast/common.dart';
import 'package:flutter_chrome_cast/discovery.dart';
import 'package:flutter_chrome_cast/entities.dart';
import 'package:flutter_chrome_cast/enums.dart';
import 'package:flutter_chrome_cast/media.dart';
import 'package:flutter_chrome_cast/models.dart';
import 'package:flutter_chrome_cast/session.dart';
import 'package:permission_handler/permission_handler.dart';

import '../api/dto.dart';
import '../audio/url_refresh.dart';

class CastService {
  CastService._() {
    // Internal mediator: derive "track ended" + cache last-known
    // position from the SDK's streams. We hold these subscriptions
    // for the lifetime of the singleton — they're cheap when no
    // session is active and never need to be torn down.
    GoogleCastRemoteMediaClient.instance.mediaStatusStream
        .listen(_onMediaStatus);
    GoogleCastRemoteMediaClient.instance.playerPositionStream.listen(
      (pos) => _lastReportedPosition = pos,
    );
  }
  static final CastService instance = CastService._();

  bool _inited = false;
  bool get inited => _inited;

  /// Most recent player position the receiver reported. Used by
  /// AppState on disconnect to hand the play-head back to mpv (mpv
  /// seeks to this position before resuming).
  Duration _lastReportedPosition = Duration.zero;
  Duration get lastReportedPosition => _lastReportedPosition;

  /// Emits when a track finishes naturally on the receiver (player
  /// state goes idle with `idleReason == finished`). AppState listens
  /// + advances the queue.
  final StreamController<void> _trackEndedCtrl =
      StreamController<void>.broadcast();
  Stream<void> get trackEndedStream => _trackEndedCtrl.stream;

  /// Emits when the receiver goes idle with `idleReason == error` —
  /// network drop, bad URL, segment-fetch failure on HLS, etc. AppState
  /// reacts by re-resolving the current song (fresh signed URL) and
  /// pushing it back to the receiver at the last known position.
  final StreamController<void> _mediaErrorCtrl =
      StreamController<void>.broadcast();
  Stream<void> get mediaErrorStream => _mediaErrorCtrl.stream;

  /// Fired by the per-track URL-refresh timer when the loaded URL is
  /// about to expire (parsed via [UrlRefreshScheduler.parseExpiry]).
  /// AppState pushes a re-resolved URL at the last reported position
  /// so the receiver doesn't hit a 403 mid-track.
  final StreamController<void> _refreshNeededCtrl =
      StreamController<void>.broadcast();
  Stream<void> get refreshNeededStream => _refreshNeededCtrl.stream;

  /// Last seen player state, so we only fire `trackEnded` on a real
  /// transition into idle+finished (not on every status push).
  CastMediaPlayerState? _lastPlayerState;

  /// Per-track refresh timer. Cleared on each new loadSong call.
  Timer? _refreshTimer;

  void _onMediaStatus(GoggleCastMediaStatus? status) {
    if (status == null) return;
    final wasIdle = _lastPlayerState == CastMediaPlayerState.idle;
    final nowIdle = status.playerState == CastMediaPlayerState.idle;
    final reason = status.idleReason;
    if (!wasIdle && nowIdle) {
      if (reason == GoogleCastMediaIdleReason.finished) {
        _trackEndedCtrl.add(null);
      } else if (reason == GoogleCastMediaIdleReason.error) {
        _mediaErrorCtrl.add(null);
      }
    }
    _lastPlayerState = status.playerState;
  }

  /// Parse the loaded URL's signed-expiry and schedule a pre-emptive
  /// refresh ~5 min before. Mirrors [UrlRefreshScheduler] for the mpv
  /// side. If the URL has no parseable expiry, no timer is scheduled —
  /// the reactive `mediaErrorStream` is the safety net for those.
  void _scheduleRefresh(String url) {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    final expiry = UrlRefreshScheduler.parseExpiry(url);
    if (expiry == null) return;
    final fireAt = expiry.subtract(const Duration(minutes: 5));
    final delay = fireAt.difference(DateTime.now());
    if (delay.inSeconds <= 5) {
      // Already past safety — fire shortly so the receiver doesn't
      // start playing on an already-expiring URL.
      _refreshTimer = Timer(const Duration(seconds: 5), () {
        if (isConnected) _refreshNeededCtrl.add(null);
      });
      return;
    }
    _refreshTimer = Timer(delay, () {
      if (isConnected) _refreshNeededCtrl.add(null);
    });
  }

  void _cancelRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  /// Set once at startup. Failures are swallowed — Cast is opt-in and
  /// the user should still be able to play music on the phone if the
  /// SDK can't initialise (e.g. emulators without Play Services).
  Future<void> init() async {
    if (_inited) return;
    try {
      const appId = GoogleCastDiscoveryCriteria.kDefaultApplicationId;
      GoogleCastOptions? options;
      if (Platform.isIOS) {
        options = IOSGoogleCastOptions(
          GoogleCastDiscoveryCriteriaInitialize.initWithApplicationID(appId),
          stopCastingOnAppTerminated: false,
        );
      } else if (Platform.isAndroid) {
        options = GoogleCastOptionsAndroid(
          appId: appId,
          stopCastingOnAppTerminated: false,
        );
      } else {
        // Other platforms — desktop, web — Cast is unsupported. Skip.
        return;
      }
      await GoogleCastContext.instance.setSharedInstanceWithOptions(options);
      _inited = true;
      debugPrint('[cast] context ready');
    } catch (e, st) {
      debugPrint('[cast] init failed (continuing without cast): $e\n$st');
    }
  }

  // ── Discovery ─────────────────────────────────────────────────────────

  Stream<List<GoogleCastDevice>> get devicesStream =>
      GoogleCastDiscoveryManager.instance.devicesStream;

  Future<void> startDiscovery() async {
    if (!_inited) return;
    // Android 13+ (API 33) gates mDNS-based LAN scanning behind the
    // NEARBY_WIFI_DEVICES runtime permission. Older Androids don't have
    // it (`isDenied` returns true but `request` is a no-op success) and
    // iOS doesn't need it at all. Permission denial is non-fatal — we
    // still call startDiscovery and just won't see any devices.
    try {
      final status = await Permission.nearbyWifiDevices.status;
      if (status.isDenied || status.isPermanentlyDenied) {
        final req = await Permission.nearbyWifiDevices.request();
        debugPrint('[cast] NEARBY_WIFI_DEVICES → ${req.toString()}');
      }
    } catch (e) {
      // No-op on platforms / SDK levels where this permission isn't
      // known. `permission_handler` throws on Android < 13 / iOS for
      // some permissions; we don't want that to block discovery.
      debugPrint('[cast] permission probe non-fatal: $e');
    }
    try {
      GoogleCastDiscoveryManager.instance.startDiscovery();
    } catch (e) {
      debugPrint('[cast] startDiscovery failed: $e');
    }
  }

  Future<void> stopDiscovery() async {
    if (!_inited) return;
    try {
      GoogleCastDiscoveryManager.instance.stopDiscovery();
    } catch (e) {
      debugPrint('[cast] stopDiscovery failed: $e');
    }
  }

  // ── Session ───────────────────────────────────────────────────────────

  Stream<GoogleCastSession?> get sessionStream =>
      GoogleCastSessionManager.instance.currentSessionStream;

  GoogleCastSession? get currentSession =>
      GoogleCastSessionManager.instance.currentSession;

  bool get isConnected =>
      GoogleCastSessionManager.instance.connectionState ==
      GoogleCastConnectState.connected;

  Future<bool> connect(GoogleCastDevice device) async {
    // ignore: avoid_print
    print('[cast] connect() called, inited=$_inited, '
        'device="${device.friendlyName}"');
    if (!_inited) {
      // ignore: avoid_print
      print('[cast] BAIL: cast context not initialised');
      return false;
    }
    try {
      // ignore: avoid_print
      print('[cast] startSessionWithDevice…');
      await GoogleCastSessionManager.instance.startSessionWithDevice(device);
      // ignore: avoid_print
      print('[cast] startSessionWithDevice returned, '
          'connectionState=${GoogleCastSessionManager.instance.connectionState}');
      return true;
    } catch (e, st) {
      // ignore: avoid_print
      print('[cast] connect FAILED: $e\n$st');
      return false;
    }
  }

  Future<void> disconnect() async {
    if (!_inited) return;
    _cancelRefresh();
    try {
      await GoogleCastSessionManager.instance.endSessionAndStopCasting();
    } catch (e) {
      debugPrint('[cast] disconnect failed: $e');
    }
  }

  // ── Media ─────────────────────────────────────────────────────────────

  /// Live media-status snapshot from the Cast receiver. UI position +
  /// play state mirror this. Note: `position` isn't on the snapshot
  /// directly — call `streamPosition()` on the remote client for that.
  Stream<GoggleCastMediaStatus?> get mediaStatusStream =>
      GoogleCastRemoteMediaClient.instance.mediaStatusStream;

  /// Live position from the Cast receiver. Drives the scrubber + tick
  /// while casting (mpv's position is meaningless during a session).
  Stream<Duration> get positionStream =>
      GoogleCastRemoteMediaClient.instance.playerPositionStream;

  GoggleCastMediaStatus? get mediaStatus =>
      GoogleCastRemoteMediaClient.instance.mediaStatus;

  bool get isPlayingOnCast {
    final s = mediaStatus;
    if (s == null) return false;
    return s.playerState == CastMediaPlayerState.playing;
  }

  /// Push [song] to the connected Cast receiver. Caller resolves [url]
  /// via the StreamResolver (with `forceRefresh:true` if needed so we
  /// don't hand the receiver an already-expired URL). [position] is
  /// seconds; pass 0 for a fresh start.
  ///
  /// Returns false when there's no active session.
  Future<bool> loadSong({
    required FeedItem song,
    required String url,
    Duration position = Duration.zero,
  }) async {
    if (!isConnected) return false;
    try {
      final contentType = _guessContentType(url);
      final artists = (song.artists ?? const <ApiArtistRef>[])
          .map((a) => a.name.trim())
          .where((n) => n.isNotEmpty)
          .toList();
      final artworkUrl = song.artwork;
      // SDK exposes Generic + Movie metadata flavours; there's no
      // dedicated MusicTrack flavour in this package version, but the
      // Cast media receiver renders generic metadata correctly for
      // audio. Title carries the song; subtitle gets the artists line.
      final subtitle = [
        if (artists.isNotEmpty) artists.join(', '),
        if (song.subtitle != null && song.subtitle!.isNotEmpty &&
            (artists.isEmpty || !artists.contains(song.subtitle)))
          song.subtitle!,
      ].join(' · ');
      final info = GoogleCastMediaInformation(
        contentId: song.id,
        streamType: CastMediaStreamType.buffered,
        contentUrl: Uri.parse(url),
        contentType: contentType,
        metadata: GoogleCastGenericMediaMetadata(
          title: song.title,
          subtitle: subtitle.isEmpty ? null : subtitle,
          images: [
            if (artworkUrl != null && artworkUrl.isNotEmpty)
              GoogleCastImage(url: Uri.parse(artworkUrl)),
          ],
        ),
      );
      await GoogleCastRemoteMediaClient.instance.loadMedia(
        info,
        autoPlay: true,
        playPosition: position,
      );
      _scheduleRefresh(url);
      debugPrint('[cast] loaded "${song.title}" @ ${position.inSeconds}s');
      return true;
    } catch (e, st) {
      debugPrint('[cast] loadSong failed: $e\n$st');
      return false;
    }
  }

  Future<void> play() async {
    if (!isConnected) return;
    try {
      await GoogleCastRemoteMediaClient.instance.play();
    } catch (e) {
      debugPrint('[cast] play failed: $e');
    }
  }

  Future<void> pause() async {
    if (!isConnected) return;
    try {
      await GoogleCastRemoteMediaClient.instance.pause();
    } catch (e) {
      debugPrint('[cast] pause failed: $e');
    }
  }

  Future<void> seek(Duration position) async {
    if (!isConnected) return;
    try {
      await GoogleCastRemoteMediaClient.instance.seek(
        GoogleCastMediaSeekOption(position: position),
      );
    } catch (e) {
      debugPrint('[cast] seek failed: $e');
    }
  }

  /// Best-effort MIME-type guess from the URL extension. The Cast
  /// receiver is permissive — getting this slightly wrong usually
  /// still works because the player content-sniffs.
  String _guessContentType(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('.m3u8') || lower.contains('hls')) {
      return 'application/x-mpegURL';
    }
    if (lower.contains('.mp3')) return 'audio/mpeg';
    if (lower.contains('.aac')) return 'audio/aac';
    if (lower.contains('.opus')) return 'audio/opus';
    if (lower.contains('.ogg')) return 'audio/ogg';
    // .m4a + everything else — saavn's typical mp4-aac container.
    return 'audio/mp4';
  }
}
