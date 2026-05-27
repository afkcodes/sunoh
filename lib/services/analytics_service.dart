// Firebase Analytics facade.
//
// Mirrors the RN app's `AnalyticsService` (logScreenView / logSongPlay /
// logSearch / logCustomEvent) and adds first-class events for the
// surfaces the Flutter app has that the RN app didn't, or that the RN
// app under-tracked:
//
//   like_song / unlike_song          like or unlike (toggle outcome)
//   save_collection                  bookmark album / playlist / artist
//   start_radio_station              tap on a radio_station tile
//   share                            share sheet completed for any kind
//   download_song                    user queues / removes a download
//   cast_connect / cast_disconnect   Chromecast session lifecycle
//   sleep_timer_set                  arm a duration or end-of-track
//   autoplay_prime                   endless-autoplay batch appended
//   playlist_create                  new user playlist made
//   playlist_add_song                song added to a user playlist
//   playlist_play                    user playlist played
//   eq_preset_apply                  EQ preset selected (preset id)
//   lyrics_open                      lyrics overlay opened
//   update_banner_tap                update notifier tapped (→ GitHub)
//
// Everything is **fire-and-forget**: callers never await. Each method
// catches its own exceptions so a broken analytics path can never crash
// the calling feature. The whole service is gated behind `_ready` —
// flipped on by [init] after `Firebase.initializeApp` succeeds; if init
// fails (missing google-services.json, no Play Services, etc.) every
// log call becomes a cheap no-op.
//
// Logs to debug-mode console are gated on `kDebugMode` so release
// builds don't spam logcat.

import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  FirebaseAnalytics? _fa;
  bool _ready = false;
  // User opt-out flag. Flipped by `setEnabled` (driven by the Settings
  // toggle in AppState). Independent of `_ready` — `_ready` is "Firebase
  // initialised at all", `_enabledByUser` is "user wants tracking on".
  // BOTH must be true for events to actually fire.
  bool _enabledByUser = true;

  /// Called from `main.dart` after the audio engine init. Wrapped in
  /// try/catch so a missing/invalid `google-services.json` is just a
  /// "analytics disabled" log line, not a crash on app startup.
  Future<void> init() async {
    try {
      await Firebase.initializeApp();
      _fa = FirebaseAnalytics.instance;
      _ready = true;
      _debug('Firebase initialized, analytics ready');
    } catch (e) {
      _ready = false;
      _debug('Firebase init failed → analytics disabled: $e');
    }
  }

  /// User-driven opt-out. Wired into Firebase's own
  /// `setAnalyticsCollectionEnabled` so even queued events are dropped
  /// and the SDK stops uploading. On disable we also call
  /// `resetAnalyticsData` which generates a new install id, severing
  /// the link to anything already collected on this device.
  ///
  /// Safe to call before [init] resolves — the wanted state is cached
  /// and applied on the next event. Caller should also persist the
  /// flag via AppState so the choice survives restart.
  Future<void> setEnabled(bool enabled) async {
    _enabledByUser = enabled;
    _debug('user toggled analytics → ${enabled ? 'enabled' : 'disabled'}');
    final fa = _fa;
    if (fa == null) return;
    try {
      await fa.setAnalyticsCollectionEnabled(enabled);
      if (!enabled) {
        await fa.resetAnalyticsData();
        _debug('analytics data reset (new install id will be issued)');
      }
    } catch (e) {
      _debug('setEnabled($enabled) failed: $e');
    }
  }

  /// Attach app-level settings to every subsequent event. Cheap; safe
  /// to call multiple times (e.g. when the user changes a setting).
  Future<void> setUserProperties({
    String? languages,
    String? density,
    bool? tintFromArt,
    String? streamQuality,
    bool? endlessAutoplay,
  }) async {
    if (!_ready || _fa == null) return;
    try {
      final fa = _fa!;
      await Future.wait([
        if (languages != null)
          fa.setUserProperty(name: 'languages', value: languages),
        if (density != null)
          fa.setUserProperty(name: 'density', value: density),
        if (tintFromArt != null)
          fa.setUserProperty(name: 'tint_from_art', value: '$tintFromArt'),
        if (streamQuality != null)
          fa.setUserProperty(name: 'stream_quality', value: streamQuality),
        if (endlessAutoplay != null)
          fa.setUserProperty(
              name: 'endless_autoplay', value: '$endlessAutoplay'),
      ]);
    } catch (e) {
      _debug('setUserProperties failed: $e');
    }
  }

  // ── Core events (mirror RN) ────────────────────────────────────────────

  void logScreenView(String name, {String? klass}) =>
      _safe('screen_view', () async {
        await _fa!.logScreenView(
          screenName: name,
          screenClass: klass ?? name,
        );
      });

  void logSongPlay({
    required String id,
    required String title,
    String? artist,
    String? provider,
    String? sourceLabel,
  }) =>
      _safe('song_play', () async {
        await _fa!.logEvent(name: 'song_play', parameters: {
          'item_id': id,
          'item_name': _truncate(title, 100),
          'artist_name': _truncate(artist ?? 'Unknown', 100),
          'provider': provider ?? 'unknown',
          if (sourceLabel != null && sourceLabel.isNotEmpty)
            'source_label': _truncate(sourceLabel, 100),
        });
      });

  void logSearch(String query) => _safe('search', () async {
        await _fa!.logSearch(searchTerm: _truncate(query, 100));
      });

  /// Generic escape hatch — prefer the typed helpers below for things
  /// they exist for, since param keys then stay consistent.
  void logCustomEvent(String name, [Map<String, Object>? params]) =>
      _safe(name, () async {
        await _fa!.logEvent(name: name, parameters: params);
      });

  // ── App-specific events ────────────────────────────────────────────────

  void logLike(String songId, {required bool liked, String? title}) =>
      _safe(liked ? 'like_song' : 'unlike_song', () async {
        await _fa!.logEvent(
          name: liked ? 'like_song' : 'unlike_song',
          parameters: {
            'item_id': songId,
            if (title != null) 'item_name': _truncate(title, 100),
          },
        );
      });

  void logSaveCollection({
    required String kind, // album / playlist / artist
    required String id,
    required bool saved,
    String? title,
  }) =>
      _safe('save_collection', () async {
        await _fa!.logEvent(name: 'save_collection', parameters: {
          'kind': kind,
          'item_id': id,
          'saved': saved.toString(),
          if (title != null) 'item_name': _truncate(title, 100),
        });
      });

  void logRadioStart({
    required String id,
    required String name,
    String? kind,
    String? provider,
  }) =>
      _safe('start_radio_station', () async {
        await _fa!.logEvent(name: 'start_radio_station', parameters: {
          'item_id': id,
          'item_name': _truncate(name, 100),
          'station_kind': ?kind,
          'provider': ?provider,
        });
      });

  void logShare({required String kind, required String id, String? title}) =>
      _safe('share', () async {
        await _fa!.logShare(
          contentType: kind,
          itemId: id,
          method: 'system_share_sheet',
        );
        // logShare doesn't carry title — log a sibling event so the title
        // is queryable in BigQuery / Firebase console.
        await _fa!.logEvent(name: 'share_detail', parameters: {
          'kind': kind,
          'item_id': id,
          if (title != null) 'item_name': _truncate(title, 100),
        });
      });

  void logDownload({
    required String songId,
    required String action, // queued / removed / completed / failed
    String? title,
  }) =>
      _safe('download_$action', () async {
        await _fa!.logEvent(name: 'download_song', parameters: {
          'item_id': songId,
          'action': action,
          if (title != null) 'item_name': _truncate(title, 100),
        });
      });

  void logCastConnect(String deviceName) =>
      _safe('cast_connect', () async {
        await _fa!.logEvent(name: 'cast_connect', parameters: {
          'device_name': _truncate(deviceName, 100),
        });
      });

  void logCastDisconnect({Duration? sessionLength}) =>
      _safe('cast_disconnect', () async {
        await _fa!.logEvent(name: 'cast_disconnect', parameters: {
          if (sessionLength != null)
            'session_seconds': sessionLength.inSeconds,
        });
      });

  void logSleepTimerSet({int? minutes, required bool endOfTrack}) =>
      _safe('sleep_timer_set', () async {
        await _fa!.logEvent(name: 'sleep_timer_set', parameters: {
          'mode': endOfTrack ? 'end_of_track' : 'duration',
          'minutes': ?minutes,
        });
      });

  void logSleepTimerCancel() => _safe('sleep_timer_cancel', () async {
        await _fa!.logEvent(name: 'sleep_timer_cancel');
      });

  void logAutoplayPrime({required int songsAppended, required String seedId}) =>
      _safe('autoplay_prime', () async {
        await _fa!.logEvent(name: 'autoplay_prime', parameters: {
          'songs_appended': songsAppended,
          'seed_id': seedId,
        });
      });

  void logPlaylistCreate({required String id, required String name}) =>
      _safe('playlist_create', () async {
        await _fa!.logEvent(name: 'playlist_create', parameters: {
          'playlist_id': id,
          'playlist_name': _truncate(name, 100),
        });
      });

  void logPlaylistAddSong({
    required String playlistId,
    required String songId,
  }) =>
      _safe('playlist_add_song', () async {
        await _fa!.logEvent(name: 'playlist_add_song', parameters: {
          'playlist_id': playlistId,
          'item_id': songId,
        });
      });

  void logPlaylistPlay({required String playlistId, required int songCount}) =>
      _safe('playlist_play', () async {
        await _fa!.logEvent(name: 'playlist_play', parameters: {
          'playlist_id': playlistId,
          'song_count': songCount,
        });
      });

  void logEqPresetApply({required String presetId}) =>
      _safe('eq_preset_apply', () async {
        await _fa!.logEvent(name: 'eq_preset_apply', parameters: {
          'preset_id': presetId,
        });
      });

  void logLyricsOpen({required String songId}) =>
      _safe('lyrics_open', () async {
        await _fa!.logEvent(name: 'lyrics_open', parameters: {
          'item_id': songId,
        });
      });

  void logUpdateBannerTap(String version) =>
      _safe('update_banner_tap', () async {
        await _fa!.logEvent(name: 'update_banner_tap', parameters: {
          'version': version,
        });
      });

  // ── Internals ──────────────────────────────────────────────────────────

  /// Wraps a log call so each event runs fire-and-forget with its own
  /// try/catch. A failure on one event never breaks the next.
  void _safe(String tag, Future<void> Function() fn) {
    if (!_ready || _fa == null) return;
    if (!_enabledByUser) return;
    () async {
      try {
        await fn();
        _debug('logged $tag');
      } catch (e) {
        _debug('$tag failed: $e');
      }
    }();
  }

  void _debug(String msg) {
    if (kDebugMode) debugPrint('[analytics] $msg');
  }

  /// Firebase truncates event-name + parameter values past their limits;
  /// pre-truncate so the BigQuery export carries readable values. 100
  /// chars is Firebase's per-param limit.
  static String _truncate(String s, int max) =>
      s.length <= max ? s : s.substring(0, max);
}
