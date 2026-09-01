// In-app updater — silently downloads the release APK for the device's
// ABI, then asks the OS to install it. Replaces the "tap to open in
// browser" fallback that the UpdateBanner used to drive.
//
// Flow:
//   1. Pick the right APK URL from the manifest's `apks` map based on
//      the device's primary supported ABI (arm64-v8a / armeabi-v7a /
//      x86_64). Falls back to launching the release page in a browser
//      if there's no match (older manifest, exotic ABI).
//   2. Stream the download via Dio with onReceiveProgress so the UI
//      can render a real percentage.
//   3. Save to the app's external storage / cache dir so the system
//      package installer can read the file URI we hand it.
//   4. Trigger install via `open_filex` — Android pops the system
//      installer with a "Continue" button. The first time, the user
//      gets prompted to grant "Install unknown apps" for sunoh; after
//      that subsequent updates are one tap.
//
// State is exposed via a ChangeNotifier so the UpdateDialog can
// rebuild on progress / completion / failure without us needing a
// fancy Riverpod state model.

import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/updates.dart';

/// Lifecycle of an in-app update.
enum UpdateStage {
  /// Ready to start — user hasn't tapped Update yet.
  idle,

  /// Picking ABI / preparing the destination path.
  preparing,

  /// Bytes streaming in. `progress` is 0.0–1.0.
  downloading,

  /// Download finished, install prompt was launched. The OS now owns
  /// the rest of the flow — we don't see the install completion event.
  installing,

  /// Something failed before the install prompt fired. `errorMessage`
  /// has a human-readable cause.
  failed,
}

class UpdaterController extends ChangeNotifier {
  UpdaterController({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  UpdateStage _stage = UpdateStage.idle;
  double _progress = 0.0;
  int _bytesReceived = 0;
  int _totalBytes = 0;
  String? _errorMessage;
  String? _downloadedApkPath;

  UpdateStage get stage => _stage;
  double get progress => _progress;
  int get bytesReceived => _bytesReceived;
  int get totalBytes => _totalBytes;
  String? get errorMessage => _errorMessage;
  String? get downloadedApkPath => _downloadedApkPath;
  bool get isActive =>
      _stage == UpdateStage.preparing ||
      _stage == UpdateStage.downloading ||
      _stage == UpdateStage.installing;

  /// Reset the controller back to idle. Called when the dialog
  /// dismisses after a successful install-prompt OR when the user
  /// dismisses an error so the next attempt starts fresh.
  void reset() {
    _stage = UpdateStage.idle;
    _progress = 0.0;
    _bytesReceived = 0;
    _totalBytes = 0;
    _errorMessage = null;
    _downloadedApkPath = null;
    notifyListeners();
  }

  /// Begin a download + install for [info]. On any unrecoverable
  /// failure (no matching APK in the manifest, IO error, etc.) the
  /// stage becomes `failed` and [errorMessage] is set; the dialog
  /// surfaces a "View release on GitHub" fallback that launches
  /// [info.url] in the user's browser.
  Future<void> downloadAndInstall(UpdateInfo info) async {
    if (isActive) return; // ignore double-tap
    _stage = UpdateStage.preparing;
    _progress = 0.0;
    _bytesReceived = 0;
    _totalBytes = 0;
    _errorMessage = null;
    _downloadedApkPath = null;
    notifyListeners();
    try {
      final apkUrl = await _pickApkUrl(info);
      if (apkUrl == null) {
        throw _UpdaterException(
          'No APK matches this device. Opening the release page instead.',
        );
      }
      final dest = await _destinationPath(info.version);
      _stage = UpdateStage.downloading;
      notifyListeners();
      await _dio.download(
        apkUrl,
        dest,
        onReceiveProgress: (received, total) {
          _bytesReceived = received;
          _totalBytes = total > 0 ? total : 0;
          if (total > 0) _progress = (received / total).clamp(0.0, 1.0);
          notifyListeners();
        },
        options: Options(
          receiveTimeout: const Duration(minutes: 5),
          responseType: ResponseType.bytes,
        ),
      );
      _downloadedApkPath = dest;
      _stage = UpdateStage.installing;
      notifyListeners();
      // Hand off to the OS. The result type indicates whether
      // open_filex managed to spawn the system installer; from there
      // the user accepts the "Install unknown apps" + "Install"
      // prompts in the Android-system UI.
      final result = await OpenFilex.open(dest);
      if (result.type != ResultType.done) {
        throw _UpdaterException(
          'Couldn’t open the installer: ${result.message}',
        );
      }
      // We never reach "done" from our side — the install happens in
      // the system UI and the app may be killed during install. Stage
      // stays `installing`; the dialog reads that as "ready, system
      // is in charge now".
    } catch (e) {
      _stage = UpdateStage.failed;
      _errorMessage = e is _UpdaterException
          ? e.message
          : 'Update failed: ${e.toString()}';
      notifyListeners();
    }
  }

  /// Fallback for when no matching APK can be downloaded — open the
  /// release page in the user's browser so they can pick + sideload
  /// manually. The dialog calls this on the "View on GitHub" action.
  Future<void> openReleasePage(UpdateInfo info) async {
    final uri = Uri.tryParse(info.url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      /* swallow — user can retry */
    }
  }

  /// Pick the right APK URL from the manifest's `apks` map based on
  /// the device's supported ABIs. Returns null when the manifest has
  /// no `apks` entries (old shape) OR none of the device's ABIs are
  /// listed (rare; covers x86 emulators etc.). Order in
  /// `supportedAbis` is "best first" per Android — so the first ABI
  /// that has an APK wins.
  Future<String?> _pickApkUrl(UpdateInfo info) async {
    if (info.apks.isEmpty) return null;
    if (!Platform.isAndroid) return null;
    final di = await DeviceInfoPlugin().androidInfo;
    for (final abi in di.supportedAbis) {
      final url = info.apks[abi];
      if (url != null && url.isNotEmpty) return url;
    }
    // No exact match — fall back to arm64-v8a if listed (covers ~all
    // modern devices). If even that's absent, return null and the
    // caller routes the user to the browser.
    return info.apks['arm64-v8a'];
  }

  /// Where to drop the downloaded APK.
  ///
  /// Uses the app's INTERNAL temp directory (`/data/user/0/<pkg>/cache/…`),
  /// NOT external storage. open_filex's Android pre-flight rejects any
  /// path containing `/storage/` unless MANAGE_EXTERNAL_STORAGE is held
  /// (a heavyweight Google-restricted permission we don't want to ask
  /// for). open_filex itself uses a FileProvider to grant the system
  /// installer temporary read access to the internal-cache file, so
  /// the installer reads it fine — no shared-storage requirement.
  ///
  /// File name includes the version so older half-downloaded files
  /// don't get confused with newer ones.
  Future<String> _destinationPath(String version) async {
    final dir = await getTemporaryDirectory();
    final safeVersion = version.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final file = File('${dir.path}/sunoh-update-v$safeVersion.apk');
    if (await file.exists()) {
      // Older session may have left a partial / completed download
      // under the same name. Delete so the new download can't pick up
      // half-baked bytes.
      try {
        await file.delete();
      } catch (_) {}
    }
    return file.path;
  }
}

class _UpdaterException implements Exception {
  _UpdaterException(this.message);
  final String message;
}
