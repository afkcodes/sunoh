// Android's background-execution policy, kept fresh across app resumes.
//
// The value can change while the app is away — it is precisely what the user
// goes to Settings to alter, and an OEM battery manager can apply it at any
// moment without telling anyone. So this re-reads on every resume rather than
// caching an answer from launch. See `audio/background_policy.dart` for why a
// music player needs to know at all.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../audio/background_policy.dart';

/// Reads the policy and re-reads it whenever the app comes back to the front.
class BackgroundPolicyNotifier extends StateNotifier<BackgroundPolicy>
    with WidgetsBindingObserver {
  BackgroundPolicyNotifier() : super(BackgroundPolicy.unknown) {
    WidgetsBinding.instance.addObserver(this);
    refresh();
  }

  final _service = BackgroundPolicyService();

  /// True when the OS is subjecting us to Doze on top of anything else.
  bool get batteryOptimized => _service.batteryOptimized;

  Future<void> refresh() async {
    await _service.refresh();
    if (mounted) state = _service.policy;
  }

  /// Opens the app's settings page so the restriction can be lifted.
  Future<bool> openSettings() => _service.openSettings();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The one moment worth re-reading: the listener may have just come back
    // from the very settings page this sends them to.
    if (state == AppLifecycleState.resumed) refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

final backgroundPolicyProvider =
    StateNotifierProvider<BackgroundPolicyNotifier, BackgroundPolicy>(
      (ref) => BackgroundPolicyNotifier(),
    );
