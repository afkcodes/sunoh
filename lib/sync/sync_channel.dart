// Dart side of the sync bridge.
//
// The native half (android/.../sync/SyncBridge.kt) owns the Storage Access
// Framework and AES-GCM. This is a thin wrapper: every method returns a
// benign empty result rather than throwing, because a synced folder can be
// unmounted, revoked, or mid-upload at any moment and none of that should
// reach the user as an error.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SyncChannel {
  SyncChannel._();
  static final SyncChannel instance = SyncChannel._();

  static const MethodChannel _channel = MethodChannel('codes.afk.sunoh/sync');

  bool get _supported => defaultTargetPlatform == TargetPlatform.android;

  /// Show the system folder picker. Null when the user backs out, which is a
  /// normal outcome rather than a failure.
  Future<String?> pickFolder() async {
    if (!_supported) return null;
    try {
      return await _channel.invokeMethod<String>('pickFolder');
    } on PlatformException catch (e) {
      debugPrint('[sync] pickFolder failed: ${e.message}');
      return null;
    }
  }

  /// Whether the saved folder is still readable. The user can revoke the
  /// grant from system settings, or the volume can disappear, so this is
  /// checked before every sync rather than trusted from setup time.
  Future<bool> hasAccess(String treeUri) async {
    if (!_supported) return false;
    try {
      return await _channel.invokeMethod<bool>('hasAccess', {
            'tree': treeUri,
          }) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  Future<String?> folderName(String treeUri) async {
    if (!_supported) return null;
    try {
      return await _channel.invokeMethod<String>('folderName', {
        'tree': treeUri,
      });
    } on PlatformException {
      return null;
    }
  }

  /// A fresh random key, base64. Shown to the user once as a recovery code.
  Future<String?> generateKey() async {
    if (!_supported) return null;
    try {
      return await _channel.invokeMethod<String>('generateKey');
    } on PlatformException {
      return null;
    }
  }

  /// Every sync file in the folder that decrypts with [key], as name to
  /// plaintext bytes. Files written with another key are absent rather than
  /// erroring: the folder may hold an unrelated setup's data.
  Future<Map<String, Uint8List>> readAll({
    required String treeUri,
    required String key,
  }) async {
    if (!_supported) return {};
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>('readAll', {
        'tree': treeUri,
        'key': key,
      });
      if (raw == null) return {};
      final out = <String, Uint8List>{};
      raw.forEach((name, bytes) {
        if (bytes is Uint8List) out[name] = bytes;
      });
      return out;
    } on PlatformException catch (e) {
      debugPrint('[sync] readAll failed: ${e.message}');
      return {};
    }
  }

  /// Write this device's file, encrypted. Returns false on any failure, which
  /// the caller treats as "try again next time" rather than surfacing.
  Future<bool> write({
    required String treeUri,
    required String name,
    required String key,
    required Uint8List bytes,
  }) async {
    if (!_supported) return false;
    try {
      return await _channel.invokeMethod<bool>('write', {
            'tree': treeUri,
            'name': name,
            'key': key,
            'bytes': bytes,
          }) ??
          false;
    } on PlatformException catch (e) {
      debugPrint('[sync] write failed: ${e.message}');
      return false;
    }
  }

  /// Remove this device's own file, when the user turns sync off.
  Future<bool> delete({required String treeUri, required String name}) async {
    if (!_supported) return false;
    try {
      return await _channel.invokeMethod<bool>('delete', {
            'tree': treeUri,
            'name': name,
          }) ??
          false;
    } on PlatformException {
      return false;
    }
  }
}
