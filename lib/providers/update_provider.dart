// Reactive state for the in-app update notifier.
//
// `availableUpdateProvider` fetches the published manifest once at app
// start (and again when explicitly invalidated), compares it to the
// installed APK version via `package_info_plus`, and returns the
// [UpdateInfo] only when:
//   * the published version is strictly newer than the running one, AND
//   * the user hasn't already dismissed that exact version.
//
// On any failure (no network, malformed JSON, missing fields) the
// provider yields null — the UI just doesn't show a banner.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../api/updates.dart';
import '../providers/app_state_provider.dart';

final _updatesClientProvider = Provider((_) => UpdatesClient());

class CurrentAppVersion {
  const CurrentAppVersion({required this.version, required this.build});
  final String version;
  final int? build;
}

/// Reads the running APK's versionName + versionCode from
/// `package_info_plus`. Used by the update-notifier check AND by the
/// Settings → ABOUT → Version row so they can't disagree.
final currentVersionProvider = FutureProvider<CurrentAppVersion>((_) async {
  final info = await PackageInfo.fromPlatform();
  return CurrentAppVersion(
    version: info.version,
    build: int.tryParse(info.buildNumber),
  );
});

/// Latest available update — or null when current is up to date or the
/// user has dismissed this exact version.
///
/// One fetch per app session. Pull-to-refresh / Settings → "Check for
/// updates" should `ref.invalidate(availableUpdateProvider)` to recheck.
final availableUpdateProvider =
    FutureProvider.autoDispose<UpdateInfo?>((ref) async {
  // Keep alive for the whole session — otherwise leaving Home (where the
  // banner lives) would refetch on every return.
  ref.keepAlive();

  final client = ref.read(_updatesClientProvider);
  final info = await client.fetch();
  if (info == null) return null;

  final current = await ref.read(currentVersionProvider.future);
  if (!info.isNewerThan(current.version)) return null;

  // Honour the user's "Dismiss" — same exact version shouldn't nag.
  final repo = ref.read(appStateProvider).audioRepo;
  final dismissed = await repo?.settings.loadDismissedUpdate();
  if (dismissed != null && dismissed == info.version) return null;

  return info;
});

/// Persist a dismiss + drop the banner. Re-evaluating the provider after
/// this returns null until the published JSON bumps version again.
/// Accepts [WidgetRef] (widgets) or [Ref] (providers) via the shared
/// [Refreshable]-friendly `read` + `invalidate` surface.
Future<void> dismissAvailableUpdate(WidgetRef ref, String version) async {
  final repo = ref.read(appStateProvider).audioRepo;
  await repo?.settings.saveDismissedUpdate(version);
  ref.invalidate(availableUpdateProvider);
}
