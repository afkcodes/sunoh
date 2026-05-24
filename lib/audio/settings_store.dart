// Persistent user-settings store. Holds EQ + appearance + playback prefs.
// All keys live in the same Hive 'settings' box.

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
  const SavedPlayback({this.streamQuality, this.crossfadeSec});
  final String? streamQuality; // 'auto' / 'high' / 'data'
  final int? crossfadeSec;
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
  static const _kCrossfadeSec = 'playback.crossfade_sec';

  Future<Box> _box() async {
    if (Hive.isBoxOpen(_boxName)) return Hive.box(_boxName);
    return Hive.openBox(_boxName);
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
    int? crossfadeSec,
  }) async {
    final box = await _box();
    final map = <String, dynamic>{};
    if (streamQuality != null) map[_kStreamQuality] = streamQuality;
    if (crossfadeSec != null) map[_kCrossfadeSec] = crossfadeSec;
    if (map.isEmpty) return;
    await box.putAll(map);
  }

  Future<SavedPlayback?> loadPlayback() async {
    try {
      final box = await _box();
      return SavedPlayback(
        streamQuality: box.get(_kStreamQuality) as String?,
        crossfadeSec: (box.get(_kCrossfadeSec) as num?)?.toInt(),
      );
    } catch (e) {
      debugPrint('[settings-store] loadPlayback failed: $e');
      return null;
    }
  }
}
