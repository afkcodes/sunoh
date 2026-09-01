// Persistent user-settings store. Holds EQ + appearance + playback prefs.
// All keys live in the same Hive 'settings' box.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

class SavedEqState {
  const SavedEqState({required this.bands, this.presetId});
  final List<double> bands;
  final String? presetId;
}

class SavedAppearance {
  const SavedAppearance({
    this.accentValue,
    this.density,
    this.tintFromArt,
    this.tintIntensity,
    this.theme,
  });
  final int? accentValue; // ARGB int (Color.value)
  final String? density; // 'compact' / 'regular' / 'comfy'
  final bool? tintFromArt;
  final double? tintIntensity; // 0.0..1.0
  /// `SunohTheme.name` — 'system' / 'light' / 'dark'. Null on saves that
  /// predate light mode, which resolve to dark: the app shipped dark-only, so
  /// that is what an existing user already has on screen.
  final String? theme;
}

class SavedPlayback {
  const SavedPlayback({
    this.streamQuality,
    this.repeatMode,
    this.languages,
    this.endlessAutoplay,
    this.sponsorBlock,
    this.ytCountry,
    this.ytLanguage,
  });
  final String? streamQuality; // 'auto' / 'high' / 'data'
  /// Persisted as the `LoopMode.name` ('off' / 'all' / 'one'). Null on
  /// fresh installs / older saves that predate this field.
  final String? repeatMode;

  /// Selected music languages (lowercase slugs like 'hindi', 'english').
  /// Null on fresh installs / older saves; consumers treat null +
  /// empty list as "use backend default".
  final List<String>? languages;

  /// When the queue's last track ends, AppState seeds a radio from that
  /// track and appends the songs. Null on fresh installs (treated as off).
  final bool? endlessAutoplay;
  final bool? sponsorBlock;

  /// Explicit YouTube region / interface language. Null means auto-detect.
  final String? ytCountry;
  final String? ytLanguage;
}

class SettingsStore {
  SettingsStore();

  static const _boxName = 'settings';

  // EQ
  static const _kEqBands = 'eq_bands';
  static const _kEqPresetId = 'eq_preset_id';

  // Appearance
  static const _kAccent = 'appearance.accent';
  static const _kDensity = 'appearance.density';
  static const _kTintFromArt = 'appearance.tint_from_art';
  static const _kTheme = 'appearance.theme';
  static const _kTintIntensity = 'appearance.tint_intensity';

  // Playback
  static const _kStreamQuality = 'playback.stream_quality';
  // `_kCrossfadeSec` retired with the crossfade feature 2026-05-26 — old
  // installs may still have the key on disk but nothing reads it now.
  static const _kRepeatMode = 'playback.repeat_mode';
  static const _kLanguages = 'playback.languages';
  static const _kEndlessAutoplay = 'playback.endless_autoplay';
  // Skip non-music segments (sponsor reads, intros/outros) on YouTube
  // tracks using community SponsorBlock data.
  static const _kSponsorBlock = 'playback.sponsorblock';
  // Explicit YouTube region / interface language. Empty string = auto.
  static const _kYtCountry = 'playback.yt_country';
  static const _kYtLanguage = 'playback.yt_language';

  // Search
  static const _kSearchRecents = 'search.recents';

  // ── Library sync ─────────────────────────────────────────────────────
  // The tree URI is a persisted SAF grant, the key is the base64 AES key
  // shown to the user once as a recovery code, and the device id names this
  // device's file in the folder. All three live here rather than in the
  // library box because they configure sync, they are not synced by it.
  /// Absolute folder roots the on-device library takes music from. Empty
  /// means the whole device.
  ///
  /// Not synced between devices: the same music sits under different paths on
  /// different phones, so one device's folder choice is meaningless on another
  /// and would silently hide the wrong music.
  static const _kIncludedFolders = 'local.included_folders';

  static const _kSyncTree = 'sync.tree_uri';
  static const _kSyncKey = 'sync.key';
  static const _kSyncDevice = 'sync.device_id';
  static const _kSyncLastAt = 'sync.last_at';
  static const _kSyncSettingsAt = 'sync.settings_at';

  /// Cap on persisted search recents — older queries fall off the list
  /// once we cross this. 10 is plenty for the chips UI without forcing
  /// the user to scroll.
  static const int kSearchRecentsMax = 10;

  // Update notifier — version-string of the most recent update banner the
  // user dismissed. When the published version equals this, we stay quiet;
  // when it surpasses it (next release), the banner returns.
  static const _kDismissedUpdate = 'updates.dismissed_version';

  /// Cached in-flight open so concurrent loaders share one openBox call
  /// — same race-avoidance idiom as library_store.
  Future<Box>? _openFuture;

  Future<Box> _box() async {
    if (Hive.isBoxOpen(_boxName)) return Hive.box(_boxName);
    return _openFuture ??= _openOnce();
  }

  Future<Box> _openOnce() async {
    Box box;
    try {
      box = await Hive.openBox(_boxName);
    } catch (e, st) {
      // ignore: avoid_print
      print(
        '[settings-store] ⚠ openBox("$_boxName") FAILED: $e\n$st\n'
        '[settings-store] deleting corrupted box file and retrying…',
      );
      try {
        await Hive.deleteBoxFromDisk(_boxName);
      } catch (_) {}
      box = await Hive.openBox(_boxName);
    }
    int boxBytes = -1;
    try {
      final p = box.path;
      if (p != null) {
        final f = File(p);
        if (await f.exists()) boxBytes = await f.length();
      }
    } catch (_) {}
    // `print` (not debugPrint) so this surfaces in release logcat too —
    // mirrors library-store / playback-store cold-start lines for easy
    // diffing when the user reports "settings not preserved".
    // ignore: avoid_print
    print(
      '[settings-store] opened "$_boxName" at ${box.path} '
      '(file=${boxBytes}b) — '
      'accent=${box.get(_kAccent) ?? '-'} '
      'density=${box.get(_kDensity) ?? '-'} '
      'tintFromArt=${box.get(_kTintFromArt) ?? '-'} '
      'streamQ=${box.get(_kStreamQuality) ?? '-'} '
      'repeat=${box.get(_kRepeatMode) ?? '-'} '
      'eqPreset=${box.get(_kEqPresetId) ?? '-'}',
    );
    return box;
  }

  // ── EQ ──────────────────────────────────────────────────────────────────

  Future<void> saveEq({
    required List<double> bands,
    required String? presetId,
  }) async {
    final box = await _box();
    await box.putAll({_kEqBands: bands, _kEqPresetId: presetId});
    // Force fsync — without flush, Hive buffers writes and a fast process
    // kill (adb install, app swipe, etc.) drops them silently. Settings
    // were lost across upgrades for exactly this reason.
    await box.flush();
    debugPrint('[settings-store] saved EQ preset=$presetId');
  }

  Future<SavedEqState?> loadEq() async {
    try {
      final box = await _box();
      final raw = box.get(_kEqBands);
      if (raw is! List) return null;
      final bands = raw.whereType<num>().map((n) => n.toDouble()).toList();
      if (bands.length != 10) return null;
      final presetId = box.get(_kEqPresetId) as String?;
      return SavedEqState(bands: bands, presetId: presetId);
    } catch (e) {
      debugPrint('[settings-store] loadEq failed: $e');
      return null;
    }
  }

  // ── Appearance ──────────────────────────────────────────────────────────

  Future<void> saveAppearance({
    Color? accent,
    Object? density, // accept any enum (caller passes .name)
    bool? tintFromArt,
    double? tintIntensity,
    Object? theme, // SunohTheme; caller passes the enum
  }) async {
    final box = await _box();
    final map = <String, dynamic>{};
    if (accent != null) {
      // Pack Color into a single ARGB int. Using floor() to coerce the new
      // double channels in Flutter 3.27+ back to 0–255 ints.
      final argb =
          ((accent.a * 255).round() << 24) |
          ((accent.r * 255).round() << 16) |
          ((accent.g * 255).round() << 8) |
          (accent.b * 255).round();
      map[_kAccent] = argb;
    }
    if (density != null) map[_kDensity] = density.toString().split('.').last;
    if (tintFromArt != null) map[_kTintFromArt] = tintFromArt;
    if (tintIntensity != null) map[_kTintIntensity] = tintIntensity;
    if (theme != null) map[_kTheme] = theme.toString().split('.').last;
    if (map.isEmpty) return;
    await box.putAll(map);
    await box.flush();
    debugPrint('[settings-store] saved appearance ${map.keys.join(",")}');
  }

  Future<SavedAppearance?> loadAppearance() async {
    try {
      final box = await _box();
      return SavedAppearance(
        accentValue: box.get(_kAccent) as int?,
        theme: box.get(_kTheme) as String?,
        density: box.get(_kDensity) as String?,
        tintFromArt: box.get(_kTintFromArt) as bool?,
        tintIntensity: (box.get(_kTintIntensity) as num?)?.toDouble(),
      );
    } catch (e) {
      debugPrint('[settings-store] loadAppearance failed: $e');
      return null;
    }
  }

  // ── Playback ────────────────────────────────────────────────────────────

  Future<void> savePlayback({
    String? streamQuality,
    String? repeatMode,
    List<String>? languages,
    bool? endlessAutoplay,
    bool? sponsorBlock,
    String? ytCountry,
    String? ytLanguage,
  }) async {
    final box = await _box();
    final map = <String, dynamic>{};
    if (streamQuality != null) map[_kStreamQuality] = streamQuality;
    if (repeatMode != null) map[_kRepeatMode] = repeatMode;
    // Always write languages when present (including empty list) — the
    // user explicitly clearing all selections should persist as "use
    // backend default" not "leave previous value alone."
    if (languages != null) map[_kLanguages] = languages;
    if (endlessAutoplay != null) map[_kEndlessAutoplay] = endlessAutoplay;
    if (sponsorBlock != null) map[_kSponsorBlock] = sponsorBlock;
    // Empty string is meaningful here: it's how "back to auto" is stored,
    // since a null would be indistinguishable from "don't change this".
    if (ytCountry != null) map[_kYtCountry] = ytCountry;
    if (ytLanguage != null) map[_kYtLanguage] = ytLanguage;
    if (map.isEmpty) return;
    await box.putAll(map);
    await box.flush();
    debugPrint('[settings-store] saved playback ${map.keys.join(",")}');
  }

  Future<SavedPlayback?> loadPlayback() async {
    try {
      final box = await _box();
      final langsRaw = box.get(_kLanguages);
      final langs = (langsRaw is List)
          ? langsRaw.whereType<String>().toList()
          : null;
      return SavedPlayback(
        streamQuality: box.get(_kStreamQuality) as String?,
        repeatMode: box.get(_kRepeatMode) as String?,
        languages: langs,
        endlessAutoplay: box.get(_kEndlessAutoplay) as bool?,
        sponsorBlock: box.get(_kSponsorBlock) as bool?,
        ytCountry: box.get(_kYtCountry) as String?,
        ytLanguage: box.get(_kYtLanguage) as String?,
      );
    } catch (e) {
      debugPrint('[settings-store] loadPlayback failed: $e');
      return null;
    }
  }

  // ── Search ──────────────────────────────────────────────────────────────

  Future<List<String>> loadSearchRecents() async {
    try {
      final box = await _box();
      final raw = box.get(_kSearchRecents);
      if (raw is! List) return const [];
      return raw.whereType<String>().toList(growable: false);
    } catch (e) {
      debugPrint('[settings-store] loadSearchRecents failed: $e');
      return const [];
    }
  }

  Future<void> saveSearchRecents(List<String> recents) async {
    final box = await _box();
    await box.put(_kSearchRecents, recents);
    await box.flush();
  }

  // ── Update notifier ─────────────────────────────────────────────────────

  Future<String?> loadDismissedUpdate() async {
    try {
      final box = await _box();
      return box.get(_kDismissedUpdate) as String?;
    } catch (e) {
      debugPrint('[settings-store] loadDismissedUpdate failed: $e');
      return null;
    }
  }

  Future<void> saveDismissedUpdate(String version) async {
    final box = await _box();
    await box.put(_kDismissedUpdate, version);
    await box.flush();
  }

  // ── Privacy ─────────────────────────────────────────────────────────────
}

/// Sync configuration as stored.
class SavedSync {
  const SavedSync({this.treeUri, this.key, this.deviceId, this.lastSyncAt});
  final String? treeUri;
  final String? key;
  final String? deviceId;
  final int? lastSyncAt;
}

/// The settings that travel between devices, with the time they last changed.
class SyncableSettings {
  const SyncableSettings({required this.values, required this.updatedAt});
  final Map<String, dynamic> values;
  final int updatedAt;
}

extension SyncSettings on SettingsStore {
  /// Keys that sync.
  ///
  /// Appearance and playback preferences travel; anything describing *this*
  /// device or its history does not. Search recents are deliberately excluded:
  /// they are a local convenience and carry what you typed, which is the last
  /// thing that should be copied into a shared folder.
  static const syncableKeys = [
    'appearance.accent',
    'appearance.density',
    'appearance.tint_from_art',
    'appearance.tint_intensity',
    'appearance.theme',
    'playback.stream_quality',
    'playback.repeat_mode',
    'playback.languages',
    'playback.endless_autoplay',
    'playback.sponsorblock',
    'playback.yt_country',
    'playback.yt_language',
  ];

  Future<Set<String>> loadIncludedFolders() async {
    try {
      final box = await _box();
      final raw = box.get(SettingsStore._kIncludedFolders);
      if (raw is! List) return <String>{};
      return raw.whereType<String>().toSet();
    } catch (e) {
      debugPrint('[settings-store] loadIncludedFolders failed: $e');
      return <String>{};
    }
  }

  Future<void> saveIncludedFolders(Set<String> folders) async {
    try {
      final box = await _box();
      await box.put(SettingsStore._kIncludedFolders, folders.toList());
      await box.flush();
    } catch (e) {
      debugPrint('[settings-store] saveIncludedFolders failed: $e');
    }
  }

  Future<SavedSync> loadSync() async {
    try {
      final box = await _box();
      String? nonEmpty(Object? v) {
        final s = v?.toString();
        return (s == null || s.isEmpty) ? null : s;
      }

      return SavedSync(
        treeUri: nonEmpty(box.get(SettingsStore._kSyncTree)),
        key: nonEmpty(box.get(SettingsStore._kSyncKey)),
        deviceId: nonEmpty(box.get(SettingsStore._kSyncDevice)),
        lastSyncAt: (box.get(SettingsStore._kSyncLastAt) as num?)?.toInt(),
      );
    } catch (e) {
      debugPrint('[settings-store] loadSync failed: $e');
      return const SavedSync();
    }
  }

  Future<void> saveSync({
    required String treeUri,
    required String key,
    required String deviceId,
    int? lastSyncAt,
  }) async {
    try {
      final box = await _box();
      await box.putAll({
        SettingsStore._kSyncTree: treeUri,
        SettingsStore._kSyncKey: key,
        SettingsStore._kSyncDevice: deviceId,
        SettingsStore._kSyncLastAt: ?lastSyncAt,
      });
      await box.flush();
    } catch (e) {
      debugPrint('[settings-store] saveSync failed: $e');
    }
  }

  Future<SyncableSettings> loadSyncableSettings() async {
    try {
      final box = await _box();
      return SyncableSettings(
        values: {
          for (final k in syncableKeys)
            if (box.get(k) != null) k: box.get(k),
        },
        updatedAt:
            (box.get(SettingsStore._kSyncSettingsAt) as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      debugPrint('[settings-store] loadSyncableSettings failed: $e');
      return const SyncableSettings(values: {}, updatedAt: 0);
    }
  }

  /// Apply another device's settings, whole-set.
  ///
  /// Only keys in [syncableKeys] are written, however the incoming file is
  /// shaped: the payload comes out of a folder the user controls, so it is
  /// treated as untrusted input rather than as our own data coming home.
  Future<void> applySyncableSettings(
    Map<String, dynamic> values,
    int updatedAt,
  ) async {
    try {
      final box = await _box();
      final allowed = {
        for (final e in values.entries)
          if (syncableKeys.contains(e.key)) e.key: e.value,
      };
      if (allowed.isEmpty) return;
      await box.putAll({...allowed, SettingsStore._kSyncSettingsAt: updatedAt});
      await box.flush();
      debugPrint(
        '[settings-store] applied ${allowed.length} synced setting(s)',
      );
    } catch (e) {
      debugPrint('[settings-store] applySyncableSettings failed: $e');
    }
  }

  /// Stamp the moment local settings last changed, so the newest set wins a
  /// merge. Called from the settings mutators.
  Future<void> touchSettingsChanged() async {
    try {
      final box = await _box();
      await box.put(
        SettingsStore._kSyncSettingsAt,
        DateTime.now().millisecondsSinceEpoch,
      );
      await box.flush();
    } catch (_) {
      // A missed stamp only costs this device a tie-break, not correctness.
    }
  }
}
