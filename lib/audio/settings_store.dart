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
  });
  final int? accentValue; // ARGB int (Color.value)
  final String? density; // 'compact' / 'regular' / 'comfy'
  final bool? tintFromArt;
  final double? tintIntensity; // 0.0..1.0
}

class SavedPlayback {
  const SavedPlayback({
    this.streamQuality,
    this.repeatMode,
    this.languages,
    this.endlessAutoplay,
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
  static const _kTintIntensity = 'appearance.tint_intensity';

  // Playback
  static const _kStreamQuality = 'playback.stream_quality';
  // `_kCrossfadeSec` retired with the crossfade feature 2026-05-26 — old
  // installs may still have the key on disk but nothing reads it now.
  static const _kRepeatMode = 'playback.repeat_mode';
  static const _kLanguages = 'playback.languages';
  static const _kEndlessAutoplay = 'playback.endless_autoplay';

  // Search
  static const _kSearchRecents = 'search.recents';
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
      print('[settings-store] ⚠ openBox("$_boxName") FAILED: $e\n$st\n'
          '[settings-store] deleting corrupted box file and retrying…');
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
    print('[settings-store] opened "$_boxName" at ${box.path} '
        '(file=${boxBytes}b) — '
        'accent=${box.get(_kAccent) ?? '-'} '
        'density=${box.get(_kDensity) ?? '-'} '
        'tintFromArt=${box.get(_kTintFromArt) ?? '-'} '
        'streamQ=${box.get(_kStreamQuality) ?? '-'} '
        'repeat=${box.get(_kRepeatMode) ?? '-'} '
        'eqPreset=${box.get(_kEqPresetId) ?? '-'}');
    return box;
  }

  // ── EQ ──────────────────────────────────────────────────────────────────

  Future<void> saveEq({
    required List<double> bands,
    required String? presetId,
  }) async {
    final box = await _box();
    await box.putAll({
      _kEqBands: bands,
      _kEqPresetId: presetId,
    });
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
  }) async {
    final box = await _box();
    final map = <String, dynamic>{};
    if (accent != null) {
      // Pack Color into a single ARGB int. Using floor() to coerce the new
      // double channels in Flutter 3.27+ back to 0–255 ints.
      final argb = ((accent.a * 255).round() << 24) |
          ((accent.r * 255).round() << 16) |
          ((accent.g * 255).round() << 8) |
          (accent.b * 255).round();
      map[_kAccent] = argb;
    }
    if (density != null) map[_kDensity] = density.toString().split('.').last;
    if (tintFromArt != null) map[_kTintFromArt] = tintFromArt;
    if (tintIntensity != null) map[_kTintIntensity] = tintIntensity;
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
}
