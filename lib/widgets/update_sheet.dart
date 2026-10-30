// "Update available" sheet — replaces the inline UpdateBanner on Home.
//
// Auto-shown by HomeScreen on the first build where
// `availableUpdateProvider` yields a non-null UpdateInfo AND the user
// hasn't dismissed-this-session. The sheet drives a [UpdaterController]
// through prepare → downloading → installing, surfacing progress and
// final hand-off to the OS installer.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ChangeNotifierProvider lives in the legacy namespace as of
// flutter_riverpod 2.x.
import 'package:flutter_riverpod/legacy.dart';
import 'package:remixicon/remixicon.dart';

import '../api/updates.dart';
import '../overlays/sheet.dart';
import '../providers/app_state_provider.dart';
import '../providers/update_provider.dart';
import '../services/updater.dart';
import '../theme/tokens.dart';
import 'ui.dart';

/// Riverpod provider for the singleton updater controller — kept
/// outside the sheet so the download survives the sheet being
/// dismissed and re-opened (e.g. user hits Later by accident).
final updaterControllerProvider = ChangeNotifierProvider<UpdaterController>(
  (ref) => UpdaterController(),
);

/// Show the update sheet. Idempotent — pops at most once per call.
///
/// A sheet rather than the dialog this used to be: the buttons land under the
/// thumb instead of at the top of a tall phone, a long changelog scrolls
/// inside it rather than turning the whole thing into a floating scroll box,
/// and it shares its chrome with every other sheet in the app instead of
/// carrying its own radius, padding and hardcoded background.
///
/// Returns when the user dismisses it. The download lives on the controller,
/// so dismissing mid-download does not cancel it and re-opening re-attaches.
Future<void> showUpdateSheet(BuildContext context, UpdateInfo info) {
  return showSunohSheet<void>(
    context,
    builder: (_) => _UpdateSheet(info: info),
  );
}

class _UpdateSheet extends ConsumerWidget {
  const _UpdateSheet({required this.info});
  final UpdateInfo info;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final updater = ref.watch(updaterControllerProvider);
    final notes = info.notes ?? '';
    // Closing mid-download would strand a running job behind a sheet with no
    // way back to it, so the way out is only offered when nothing is running.
    final canClose =
        updater.stage == UpdateStage.idle ||
        updater.stage == UpdateStage.failed;

    return SunohSheet(
      title: 'Update available',
      subtitle: 'Version ${info.version}',
      trailing: canClose
          ? IconBtn(
              icon: RemixIcons.close_circle_line,
              color: c.fgDim,
              onTap: () => Navigator.of(context).pop(),
            )
          : null,
      actions: _Body(info: info, updater: updater, colors: c),
      // A card on a sheet takes surface2: bgSoft is already a step up.
      child: notes.isEmpty
          ? const SizedBox.shrink()
          : Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              padding: const EdgeInsets.all(14),
              decoration: squircleDecoration(
                radius: SunohRadius.card,
                color: c.surface2,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  eyebrow(
                    "What's new",
                    c.fgMute,
                    size: 10.5,
                    letterSpacing: 0.84,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    notes,
                    style: SunohType.sans(
                      fontSize: 13.5,
                      color: c.fgDim,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.info,
    required this.updater,
    required this.colors,
  });
  final UpdateInfo info;
  final UpdaterController updater;
  final SunohColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (updater.stage) {
      case UpdateStage.idle:
        return _IdleActions(info: info);
      case UpdateStage.preparing:
      case UpdateStage.downloading:
        return _ProgressBody(updater: updater, colors: colors);
      case UpdateStage.installing:
        return _InstallingBody(colors: colors);
      case UpdateStage.failed:
        return _FailedBody(info: info, updater: updater, colors: colors);
    }
  }
}

class _IdleActions extends ConsumerWidget {
  const _IdleActions({required this.info});
  final UpdateInfo info;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SheetActions(
      secondary: SheetButton(
        label: 'Skip this version',
        onTap: () {
          dismissAvailableUpdate(ref, info.version);
          Navigator.of(context).pop();
        },
      ),
      primary: SheetButton(
        label: 'Update',
        filled: true,
        onTap: () =>
            ref.read(updaterControllerProvider).downloadAndInstall(info),
      ),
    );
  }
}

class _ProgressBody extends StatelessWidget {
  const _ProgressBody({required this.updater, required this.colors});
  final UpdaterController updater;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final pct = (updater.progress * 100).clamp(0, 100).toStringAsFixed(0);
    final mbReceived = updater.bytesReceived > 0
        ? updater.bytesReceived / 1024 / 1024
        : 0.0;
    final mbTotal = updater.totalBytes > 0
        ? updater.totalBytes / 1024 / 1024
        : 0.0;
    // The prototype's download bar: a 2 px rule in the line colour, filled
    // in ink, with the figures under it in tabular digits so they do not
    // shuffle as they count.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(
          value: updater.progress > 0 ? updater.progress : null,
          minHeight: 2,
          backgroundColor: c.line,
          color: c.fg,
        ),
        const SizedBox(height: 10),
        Text(
          updater.totalBytes > 0
              ? 'Downloading · $pct%  ·  ${mbReceived.toStringAsFixed(1)} / ${mbTotal.toStringAsFixed(1)} MB'
              : 'Preparing…',
          style: SunohType.mono(fontSize: 12.5, color: c.fgDim),
        ),
      ],
    );
  }
}

class _InstallingBody extends ConsumerWidget {
  const _InstallingBody({required this.colors});
  final SunohColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(RemixIcons.checkbox_circle_fill, color: c.accent, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Downloaded. Continue in the system installer.',
                style: SunohType.sans(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: c.fg,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SheetButton(
          label: 'Close',
          onTap: () {
            ref.read(updaterControllerProvider).reset();
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}

class _FailedBody extends ConsumerWidget {
  const _FailedBody({
    required this.info,
    required this.updater,
    required this.colors,
  });
  final UpdateInfo info;
  final UpdaterController updater;
  final SunohColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(RemixIcons.error_warning_fill, color: c.danger, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                updater.errorMessage ?? 'Update failed.',
                style: SunohType.sans(fontSize: 14, color: c.fg, height: 1.4),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SheetActions(
          secondary: SheetButton(
            label: 'View release',
            onTap: () {
              ref.read(updaterControllerProvider).openReleasePage(info);
              ref.read(updaterControllerProvider).reset();
              Navigator.of(context).pop();
            },
          ),
          primary: SheetButton(
            label: 'Retry',
            filled: true,
            onTap: () =>
                ref.read(updaterControllerProvider).downloadAndInstall(info),
          ),
        ),
      ],
    );
  }
}
