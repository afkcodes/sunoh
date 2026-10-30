// Settings — full-route replacement of the legacy bottom-sheet tweaks panel.
// Sections: Playback, Appearance, Library, Community, About. Lives inside the
// active tab branch so back returns to wherever you opened it from.
//
// Layout is the prototype's settings page: a solid bar with the title
// centred, the support card first, then groups — an eyebrow label over a
// key/value list whose rows are at least 56 tall with a rule under each. The
// rules are the point: this is the one list in the app read across, label to
// value, and they carry the eye. density.scale sets the gap between groups.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remixicon/remixicon.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/yt_locale.dart';
import '../audio/storage_stats.dart';
import '../overlays/language_sheet.dart';
import '../overlays/yt_locale_sheet.dart';
import '../overlays/yt_sign_out_sheet.dart';
import '../providers/app_state_provider.dart';
import '../providers/languages_provider.dart';
import '../providers/update_provider.dart';
import '../providers/yt_auth_provider.dart';
import '../providers/ytmusic_provider.dart';
import '../router/router.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/background_warning.dart';
import '../widgets/motion.dart';
import '../widgets/support_card.dart';
import '../widgets/ui.dart';
import '../widgets/update_banner.dart';
import 'sub_page_bar.dart';

part 'settings_pickers.dart';
part 'settings_rows.dart';

/// Async cache + Hive box footprint, surfaced on the Library section.
/// Invalidated on "Clear cache" so the row reflects the freed bytes.
final _storageStatsProvider = FutureProvider.autoDispose<StorageStats>(
  (_) => computeStorageStats(),
);

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  /// Opens the Telegram community group. Same external-launcher path
  /// the donation links use — hand the URL off to the OS and let it
  /// pick Telegram-app-or-browser.
  Future<void> _openCommunity(BuildContext context, WidgetRef ref) async {
    final s = ref.read(appStateProvider);
    // Telegram t.me/+invite-hash deeplink — Android picks Telegram-app
    // when installed, falls back to the web join page otherwise.
    final uri = Uri.parse('https://t.me/+uVuFSUN4lp01M2Y1');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) s.flashToast('Couldn’t open Telegram');
    } catch (_) {
      s.flashToast('Couldn’t open Telegram');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final scale = s.density.scale;

    return ColoredBox(
      color: c.bg,
      child: _Page(
        colors: c,
        children: [
          SupportCard(colors: c, accent: s.resolvedAccent),

          _Section(
            label: 'PLAYBACK',
            colors: c,
            scale: scale,
            rows: [
              // Only draws anything when Android is set to restrict us, in
              // which case it explains why music stops when the screen locks.
              // First in Playback rather than loose above it, so that when it
              // draws nothing it leaves no gap behind.
              BackgroundWarning(colors: c),
              _RadioRow<String>(
                label: 'Stream quality',
                value: s.streamQuality,
                options: const {
                  'auto': 'Auto',
                  'high': 'High',
                  'data': 'Data saver',
                },
                onChange: s.setStreamQuality,
                colors: c,
              ),
              _NavRow(
                label: 'Music languages',
                summary: _languagesSummary(ref, s),
                onTap: () => showLanguageSheet(context),
                colors: c,
              ),
              _ToggleRow(
                label: 'Endless autoplay',
                summary:
                    'Keep music going by seeding a radio when the queue ends.',
                value: s.endlessAutoplay,
                onChange: s.setEndlessAutoplay,
                colors: c,
              ),
              _NavRow(
                label: 'YouTube account',
                summary: _ytAccountSummary(ref),
                onTap: () => _toggleYtAccount(context, ref),
                colors: c,
              ),
              _NavRow(
                label: 'YouTube region',
                summary: _ytRegionSummary(ref, s),
                onTap: () => showYtRegionSheet(context),
                colors: c,
              ),
              _NavRow(
                label: 'YouTube language',
                summary: _ytLanguageSummary(ref, s),
                onTap: () => showYtLanguageSheet(context),
                colors: c,
              ),
              _ToggleRow(
                label: 'Show Cast button',
                summary:
                    'The cast icon beside the player controls. Turn it off if '
                    'you have nothing to cast to.',
                value: s.showCastButton,
                onChange: s.setShowCastButton,
                colors: c,
              ),
              _ToggleRow(
                label: 'Skip non-music parts',
                summary:
                    'Uses SponsorBlock to jump sponsor reads, intros and '
                    'talking sections on YouTube tracks. Only a hash of the '
                    'track id is sent, never the id itself.',
                value: s.sponsorBlockEnabled,
                onChange: s.setSponsorBlock,
                colors: c,
              ),
            ],
          ),

          _Section(
            label: 'APPEARANCE',
            colors: c,
            scale: scale,
            rows: [
              _NavRow(
                label: 'Sync',
                summary: 'Keep two phones in step',
                onTap: () => context.openSync(),
                colors: c,
              ),
              _RadioRow<SunohTheme>(
                label: 'Theme',
                value: s.theme,
                options: {for (final t in SunohTheme.values) t: t.label},
                onChange: s.setTheme,
                colors: c,
              ),
              _AccentRow(s: s, colors: c, scale: scale),
              _ToggleRow(
                label: 'Tint from artwork',
                value: s.tintFromArt,
                onChange: s.setTintFromArt,
                colors: c,
              ),
              if (s.tintFromArt)
                _SliderRow(
                  label: 'Tint intensity',
                  value: s.tintIntensity,
                  min: 0,
                  max: 1,
                  divisions: 20,
                  suffix: '${(s.tintIntensity * 100).round()}%',
                  onChange: s.setTintIntensity,
                  colors: c,
                ),
              _RadioRow<Density>(
                label: 'Density',
                value: s.density,
                options: const {
                  Density.compact: 'Compact',
                  Density.regular: 'Regular',
                  Density.comfy: 'Comfy',
                },
                onChange: s.setDensity,
                colors: c,
              ),
            ],
          ),

          Consumer(
            builder: (ctx, innerRef, _) {
              final async = innerRef.watch(_storageStatsProvider);
              final stats = async.asData?.value ?? StorageStats.empty;
              return _Section(
                label: 'LIBRARY',
                colors: c,
                scale: scale,
                rows: [
                  _Link(
                    // Total = Hive (queue + library + settings) + cached
                    // network images. Shown as a single number — the user
                    // doesn't care about the split, just how much sunoh.
                    // is sitting on.
                    label: 'Storage',
                    trailing: async.isLoading
                        ? '…'
                        : formatBytes(stats.totalBytes),
                    colors: c,
                    onTap: () => innerRef.invalidate(_storageStatsProvider),
                  ),
                  _Link(
                    // Wipes the network image cache (and the in-RAM decoded
                    // image cache, so freshly-cleared art doesn't snap back
                    // from the previous scroll). Hive data is untouched.
                    label: 'Clear cache',
                    trailing: stats.imageBytes > 0
                        ? formatBytes(stats.imageBytes)
                        : null,
                    colors: c,
                    onTap: () async {
                      await clearImageCache();
                      s.flashToast('Cache cleared');
                      innerRef.invalidate(_storageStatsProvider);
                    },
                  ),
                ],
              );
            },
          ),

          // COMMUNITY — single-row section linking to the Telegram
          // group. Placed above ABOUT because users look for "join the
          // discussion" near the bottom of Settings; the version/about
          // bits stay at the very bottom as the conventional anchor.
          _Section(
            label: 'COMMUNITY',
            colors: c,
            scale: scale,
            rows: [
              _Link(
                label: 'Join on Telegram',
                trailing: 'Open',
                colors: c,
                onTap: () => _openCommunity(context, ref),
              ),
            ],
          ),

          // ABOUT — wrapped in a Consumer so we can conditionally
          // include the "Update available" row INSIDE the section (so
          // it lives under the ABOUT eyebrow, not as an orphan above).
          Consumer(
            builder: (ctx, innerRef, _) {
              final updateInfo = innerRef
                  .watch(availableUpdateProvider)
                  .asData
                  ?.value;
              return _Section(
                label: 'ABOUT',
                colors: c,
                scale: scale,
                rows: [
                  if (updateInfo != null) const UpdateAboutCard(),
                  _Link(
                    label: 'Version',
                    // Pull the live versionName+versionCode from the running
                    // APK via package_info_plus (shared with the update
                    // notifier so the two can't drift). Falls back to a dash
                    // while loading / on error.
                    trailing:
                        innerRef
                            .watch(currentVersionProvider)
                            .whenOrNull(
                              data: (v) => v.build == null
                                  ? v.version
                                  : '${v.version} (${v.build})',
                            ) ??
                        '—',
                    colors: c,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Compose the "Music languages" trailing summary. Shows up to two
/// selected language names; if more are selected, uses a "+N" suffix.
/// "All defaults" when the user hasn't picked any (= backend default
/// kicks in). Reads from the languages provider to map slugs → names —
/// the provider is autoDispose with 24-h keepAlive, so this read is
/// cheap and won't bounce a refetch.
/// Who the YouTube feed belongs to. Names the account when there is one, so
/// there is never any doubt whose recommendations are on the home screen.
String _ytAccountSummary(WidgetRef ref) {
  final auth = ref.watch(ytAuthProvider);
  if (auth.isBusy) return 'Working…';
  if (!auth.isSignedIn) return 'Sign in';
  return auth.account.name.isEmpty ? 'Signed in' : auth.account.name;
}

/// One row, both directions. Signing out is the destructive half, so it asks
/// first; signing in is not, so it does not.
Future<void> _toggleYtAccount(BuildContext context, WidgetRef ref) async {
  final auth = ref.read(ytAuthProvider);
  final state = ref.read(appStateProvider);
  if (auth.isBusy) return;

  if (!auth.isSignedIn) {
    final ok = await auth.signIn();
    if (!context.mounted) return;
    state.flashToast(ok ? 'Signed in to YouTube Music' : 'Not signed in');
    return;
  }

  final confirmed = await showYtSignOutSheet(context, auth.account.name);
  if (!confirmed || !context.mounted) return;
  await auth.signOut();
  if (!context.mounted) return;
  state.flashToast('Signed out');
}

/// "Auto (India)" or "United States" — always says what's in effect, so
/// the row reads the same whether or not an override is set.
String _ytRegionSummary(WidgetRef ref, AppState s) {
  final locale = ref.watch(ytLocaleProvider);
  final name = kYtRegions[locale.country] ?? locale.country;
  return locale.countryIsAuto ? 'Auto ($name)' : name;
}

String _ytLanguageSummary(WidgetRef ref, AppState s) {
  final locale = ref.watch(ytLocaleProvider);
  final name = kYtLanguages[locale.language] ?? locale.language;
  return locale.languageIsAuto ? 'Auto ($name)' : name;
}

String _languagesSummary(WidgetRef ref, AppState s) {
  final selected = s.selectedLanguages;
  if (selected.isEmpty) return 'All defaults';
  final all = ref.watch(languagesProvider).value;
  if (all == null || all.isEmpty) {
    // Names not loaded yet — fall back to the raw slug count.
    return selected.length == 1
        ? selected.first
        : '${selected.length} selected';
  }
  final names = all
      .where((l) => selected.contains(l.value))
      .map((l) => l.name)
      .toList();
  if (names.isEmpty) return '${selected.length} selected';
  if (names.length <= 2) return names.join(', ');
  return '${names.take(2).join(', ')} +${names.length - 2}';
}
