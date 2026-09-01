// "Update available" dialog — replaces the inline UpdateBanner on Home.
//
// Auto-shown by HomeScreen on the first build where
// `availableUpdateProvider` yields a non-null UpdateInfo AND the user
// hasn't dismissed-this-session. The dialog drives a [UpdaterController]
// through prepare → downloading → installing, surfacing progress and
// final hand-off to the OS installer.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ChangeNotifierProvider lives in the legacy namespace as of
// flutter_riverpod 2.x.
import 'package:flutter_riverpod/legacy.dart';
import 'package:solar_icons/solar_icons.dart';

import '../api/updates.dart';
import '../providers/app_state_provider.dart';
import '../providers/update_provider.dart';
import '../services/updater.dart';
import '../theme/tokens.dart';
import 'ui.dart';

/// Riverpod provider for the singleton updater controller — kept
/// outside the dialog so the download survives the dialog being
/// dismissed and re-opened (e.g. user hits Later by accident).
final updaterControllerProvider = ChangeNotifierProvider<UpdaterController>(
  (ref) => UpdaterController(),
);

/// Show the update dialog. Idempotent — pops at most once per call.
/// Returns when the user dismisses (Later / Install / × / errored
/// fallback). Doesn't block any subsequent code; the actual update
/// progress lives on the controller and the dialog re-attaches if
/// re-shown.
Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _UpdateDialog(info: info),
  );
}

class _UpdateDialog extends ConsumerWidget {
  const _UpdateDialog({required this.info});
  final UpdateInfo info;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final accent = s.resolvedAccent;
    final updater = ref.watch(updaterControllerProvider);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        decoration: squircleDecoration(
          radius: 20,
          color: const Color(0xFF15151A),
          borderColor: c.line,
        ),
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header — accent medallion + title + version pill.
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    SolarIconsBold.downloadMinimalistic,
                    size: 20,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Update available',
                        style: SunohType.heading(
                          fontSize: 17,
                          color: c.fg,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'v${info.version}',
                        style: SunohType.sans(fontSize: 12, color: c.fgMute),
                      ),
                    ],
                  ),
                ),
                if (updater.stage == UpdateStage.idle ||
                    updater.stage == UpdateStage.failed)
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(
                      SolarIconsOutline.closeCircle,
                      size: 20,
                      color: c.fgDim,
                    ),
                    splashRadius: 18,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
            if ((info.notes ?? '').isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: squircleDecoration(
                  radius: 12,
                  color: c.surface,
                  borderColor: c.line,
                ),
                child: Text(
                  info.notes!,
                  style: SunohType.sans(
                    fontSize: 13,
                    color: c.fg,
                    height: 1.45,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            _Body(info: info, updater: updater, accent: accent, colors: c),
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
    required this.accent,
    required this.colors,
  });
  final UpdateInfo info;
  final UpdaterController updater;
  final Color accent;
  final SunohColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (updater.stage) {
      case UpdateStage.idle:
        return _IdleActions(info: info, accent: accent, colors: colors);
      case UpdateStage.preparing:
      case UpdateStage.downloading:
        return _ProgressBody(updater: updater, accent: accent, colors: colors);
      case UpdateStage.installing:
        return _InstallingBody(info: info, accent: accent, colors: colors);
      case UpdateStage.failed:
        return _FailedBody(
          info: info,
          updater: updater,
          accent: accent,
          colors: colors,
        );
    }
  }
}

class _IdleActions extends ConsumerWidget {
  const _IdleActions({
    required this.info,
    required this.accent,
    required this.colors,
  });
  final UpdateInfo info;
  final Color accent;
  final SunohColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    return Row(
      children: [
        Expanded(
          child: _DialogButton(
            label: 'Skip this version',
            kind: _DialogButtonKind.subtle,
            colors: c,
            accent: accent,
            onTap: () {
              dismissAvailableUpdate(ref, info.version);
              Navigator.of(context).pop();
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _DialogButton(
            label: 'Update',
            kind: _DialogButtonKind.primary,
            colors: c,
            accent: accent,
            onTap: () =>
                ref.read(updaterControllerProvider).downloadAndInstall(info),
          ),
        ),
      ],
    );
  }
}

class _ProgressBody extends StatelessWidget {
  const _ProgressBody({
    required this.updater,
    required this.accent,
    required this.colors,
  });
  final UpdaterController updater;
  final Color accent;
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: updater.progress > 0 ? updater.progress : null,
            minHeight: 6,
            backgroundColor: c.surface,
            color: accent,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          updater.totalBytes > 0
              ? 'Downloading · $pct%  ·  ${mbReceived.toStringAsFixed(1)} / ${mbTotal.toStringAsFixed(1)} MB'
              : 'Preparing…',
          style: SunohType.sans(fontSize: 12, color: c.fgMute),
        ),
      ],
    );
  }
}

class _InstallingBody extends ConsumerWidget {
  const _InstallingBody({
    required this.info,
    required this.accent,
    required this.colors,
  });
  final UpdateInfo info;
  final Color accent;
  final SunohColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(SolarIconsBold.checkCircle, color: accent, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Downloaded. Continue in the system installer.',
                style: SunohType.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: c.fg,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _DialogButton(
                label: 'Close',
                kind: _DialogButtonKind.subtle,
                colors: c,
                accent: accent,
                onTap: () {
                  ref.read(updaterControllerProvider).reset();
                  Navigator.of(context).pop();
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FailedBody extends ConsumerWidget {
  const _FailedBody({
    required this.info,
    required this.updater,
    required this.accent,
    required this.colors,
  });
  final UpdateInfo info;
  final UpdaterController updater;
  final Color accent;
  final SunohColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              SolarIconsBold.dangerCircle,
              color: Color(0xFFE05656),
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                updater.errorMessage ?? 'Update failed.',
                style: SunohType.sans(fontSize: 13, color: c.fg, height: 1.4),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _DialogButton(
                label: 'View release',
                kind: _DialogButtonKind.subtle,
                colors: c,
                accent: accent,
                onTap: () {
                  ref.read(updaterControllerProvider).openReleasePage(info);
                  ref.read(updaterControllerProvider).reset();
                  Navigator.of(context).pop();
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _DialogButton(
                label: 'Retry',
                kind: _DialogButtonKind.primary,
                colors: c,
                accent: accent,
                onTap: () => ref
                    .read(updaterControllerProvider)
                    .downloadAndInstall(info),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

enum _DialogButtonKind { primary, subtle }

class _DialogButton extends StatelessWidget {
  const _DialogButton({
    required this.label,
    required this.kind,
    required this.colors,
    required this.accent,
    required this.onTap,
  });
  final String label;
  final _DialogButtonKind kind;
  final SunohColors colors;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final isPrimary = kind == _DialogButtonKind.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 42,
        alignment: Alignment.center,
        decoration: squircleDecoration(
          radius: 12,
          color: isPrimary
              ? accent
              : Color.alphaBlend(accent.withValues(alpha: 0.08), c.surface),
          borderColor: isPrimary ? Colors.transparent : c.line,
        ),
        child: Text(
          label,
          style: SunohType.sans(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: isPrimary ? Colors.white : c.fg,
          ),
        ),
      ),
    );
  }
}
