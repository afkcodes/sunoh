// Whether Android will let playback survive being backgrounded.
//
// ## Why a music player has to ask this
//
// A listener reported playback dying whenever the app went to the background.
// The foreground service was being created correctly — `mediaPlayback` type,
// While-In-Use capability, promoted while the activity was still visible — and
// Android was stripping it about thirteen seconds later regardless. Nothing in
// the app called `stopForeground`, nothing was logged, and no exception was
// raised. The cause was one AppOps entry on that phone:
//
//     RUN_ANY_IN_BACKGROUND: ignore
//
// That is Android's "restricted" flag. While it is set the platform revokes
// foreground-service status on backgrounding, and the app has no say. A user
// can set it under Battery > Restricted — but the reason this is worth
// detecting is that the battery managers on Motorola, Xiaomi, Samsung and
// OnePlus also set it *silently*, so the person holding the phone never chose
// it and has no reason to suspect it.
//
// From inside the app the symptom is indistinguishable from a bug of our own:
// the media session goes on reporting PLAYING with the audio stopped. Reading
// the flag is what turns an invisible OS setting into a sentence somebody can
// act on.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What the OS will do to background playback.
enum BackgroundPolicy {
  /// Playback will survive backgrounding.
  ok,

  /// `RUN_ANY_IN_BACKGROUND` is denied — the foreground service will be
  /// stripped and playback will stop, silently.
  restricted,

  /// The platform would not say, or this is not Android. Treated as [ok]
  /// everywhere it matters: warning someone about a restriction that may not
  /// exist is worse than staying quiet.
  unknown,
}

/// Reads Android's background-execution policy for this app.
class BackgroundPolicyService {
  static const _channel = MethodChannel('codes.afk.sunoh/background');

  /// Whether the OS will strip our foreground service when backgrounded.
  BackgroundPolicy policy = BackgroundPolicy.unknown;

  /// Whether the app is still subject to Doze.
  ///
  /// Tracked separately from [policy] because it is a different setting with a
  /// similar symptom — battery optimisation *delays* background work, the
  /// restriction *removes the service*. Naming the wrong one sends someone to
  /// the wrong switch.
  bool batteryOptimized = false;

  /// True only when we know playback will be cut off.
  ///
  /// Deliberately false for [BackgroundPolicy.unknown]: a warning shown to
  /// someone whose playback works fine trains them to ignore warnings.
  bool get willBeInterrupted => policy == BackgroundPolicy.restricted;

  /// Re-read the policy. Cheap — an AppOps lookup, no permission, no prompt.
  ///
  /// Worth calling on resume as well as at startup, because the setting can
  /// change while the app is away: it is exactly what the user has gone to
  /// Settings to alter, and an OEM battery manager can apply it at any time.
  Future<void> refresh() async {
    debugPrint('[background] refresh called, platform=$defaultTargetPlatform');
    if (!defaultTargetPlatform.isAndroid) return;
    try {
      final result = await _channel.invokeMapMethod<String, Object?>('status');
      if (result == null) return;
      policy = switch (result['background']) {
        'ok' => BackgroundPolicy.ok,
        'restricted' => BackgroundPolicy.restricted,
        _ => BackgroundPolicy.unknown,
      };
      batteryOptimized = result['batteryOptimized'] == true;
      debugPrint(
        '[background] policy=${policy.name} batteryOptimized=$batteryOptimized',
      );
    } on PlatformException catch (e) {
      // A diagnostic that cannot be read is not a reason to change behaviour.
      debugPrint('[background] could not read policy: ${e.message}');
    } on MissingPluginException {
      debugPrint('[background] channel missing');
    }
  }

  /// Opens this app's settings page, where the restriction can be lifted.
  ///
  /// There is no intent that deep-links to the Battery section and no API to
  /// request the restriction be removed, so the caller has to tell the user
  /// which switch to look for once they arrive.
  Future<bool> openSettings() async {
    if (!defaultTargetPlatform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('openSettings') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

extension on TargetPlatform {
  bool get isAndroid => this == TargetPlatform.android;
}
