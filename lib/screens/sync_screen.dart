// Library sync setup and status.
//
// Two paths in: set up a new folder (this device generates the key and shows
// it once), or join an existing one (enter the code from the first device).
// Both then pick a folder with the system picker.
//
// The recovery code is the only thing that can decrypt the folder, and it is
// never sent anywhere. If it is lost, the files in the folder are unreadable —
// that is the point, and the screen says so rather than burying it.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';

import '../providers/app_state_provider.dart';
import '../providers/sync_provider.dart';
import '../sync/sync_service.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';

class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});
  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  final _codeController = TextEditingController();
  bool _busy = false;
  String? _revealedCode;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final sync = ref.watch(syncProvider);

    return ColoredBox(
      color: c.bg,
      child: ListView(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 20,
          bottom: 140,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                IconBtn(
                  icon: SolarIconsOutline.altArrowLeft,
                  color: c.fgDim,
                  size: 18,
                  onTap: () => context.pop(),
                ),
                const SizedBox(width: 4),
                Text(
                  'Sync',
                  style: SunohType.heading(
                    fontSize: 24,
                    color: c.fg,
                    letterSpacing: -0.4,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Text(
              'Keep liked songs, playlists and settings the same on two '
              'phones. sunoh writes an encrypted file into a folder you '
              'choose. Whatever syncs that folder moves it. There is no '
              'account and nothing is sent to us.',
              style: SunohType.sans(fontSize: 13, color: c.fgMute, height: 1.5),
            ),
          ),
          if (sync.isConfigured)
            _Configured(sync: sync, colors: c, busy: _busy, run: _run)
          else
            _Setup(
              colors: c,
              busy: _busy,
              controller: _codeController,
              onSetUp: () => _run(() async {
                final code = await sync.setUp();
                if (code != null && mounted) {
                  setState(() => _revealedCode = code);
                }
              }),
              onJoin: () => _run(() async {
                final ok = await sync.joinWithCode(_codeController.text);
                if (!mounted) return;
                s.flashToast(
                  ok ? 'Synced' : 'Could not read that folder with this code',
                );
              }),
            ),
          if (_revealedCode != null)
            _RecoveryCode(code: _revealedCode!, colors: c),
        ],
      ),
    );
  }
}

class _Setup extends StatelessWidget {
  const _Setup({
    required this.colors,
    required this.busy,
    required this.controller,
    required this.onSetUp,
    required this.onJoin,
  });
  final SunohColors colors;
  final bool busy;
  final TextEditingController controller;
  final VoidCallback onSetUp;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _Card(
            colors: c,
            title: 'Set up on this phone',
            body:
                'Pick a folder that already syncs between your devices, such '
                'as a Syncthing, Nextcloud or Drive folder. You will get a '
                'recovery code to enter on the second phone.',
            action: busy ? 'Working…' : 'Choose folder',
            onTap: busy ? null : onSetUp,
            filled: true,
          ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _Card(
            colors: c,
            title: 'Join from another phone',
            body:
                'Enter the recovery code from the phone you set up first, '
                'then pick the same folder.',
            action: busy ? 'Working…' : 'Pick folder and join',
            onTap: busy ? null : onJoin,
            child: TextField(
              controller: controller,
              autocorrect: false,
              enableSuggestions: false,
              style: SunohType.mono(fontSize: 13, color: c.fg),
              decoration: InputDecoration(
                hintText: 'Recovery code',
                hintStyle: SunohType.mono(fontSize: 13, color: c.fgMute),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Configured extends StatelessWidget {
  const _Configured({
    required this.sync,
    required this.colors,
    required this.busy,
    required this.run,
  });
  final SyncService sync;
  final SunohColors colors;
  final bool busy;
  final Future<void> Function(Future<void> Function()) run;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final last = sync.lastSync;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Card(
            colors: c,
            title: sync.folderName ?? 'Synced folder',
            body: switch (sync.status) {
              SyncStatus.noAccess =>
                'Access to this folder was lost. Pick it again to carry on.',
              SyncStatus.failed =>
                'The last sync did not finish. It will try again.',
              SyncStatus.syncing => 'Syncing…',
              _ when last == null => 'Not synced yet.',
              _ => 'Last synced ${_ago(last)}.',
            },
            action: busy ? 'Syncing…' : 'Sync now',
            onTap: busy
                ? null
                : () => run(() async {
                    await sync.syncNow();
                  }),
            filled: true,
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: busy
                ? null
                : () => run(() async {
                    await sync.disable();
                  }),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'Stop syncing on this phone',
                style: SunohType.sans(fontSize: 13, color: c.fgMute),
              ),
            ),
          ),
          Text(
            'Your library stays on this phone. Only this device\'s file is '
            'removed from the folder.',
            style: SunohType.sans(fontSize: 12, color: c.fgMute, height: 1.4),
          ),
        ],
      ),
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }
}

/// Shown once, immediately after setup.
class _RecoveryCode extends StatelessWidget {
  const _RecoveryCode({required this.code, required this.colors});
  final String code;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: squircleDecoration(
          radius: 14,
          color: c.surface,
          borderColor: c.accent,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            eyebrow('RECOVERY CODE', c.accent),
            const SizedBox(height: 10),
            SelectableText(
              code,
              style: SunohType.mono(fontSize: 13, color: c.fg, height: 1.5),
            ),
            const SizedBox(height: 12),
            Text(
              'Enter this on your other phone. Keep a copy somewhere safe: it '
              'is the only thing that can read the folder, it is never sent '
              'anywhere, and it cannot be recovered if lost.',
              style: SunohType.sans(
                fontSize: 12,
                color: c.fgMute,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => Clipboard.setData(ClipboardData(text: code)),
              behavior: HitTestBehavior.opaque,
              child: Text(
                'Copy code',
                style: SunohType.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: c.accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.colors,
    required this.title,
    required this.body,
    required this.action,
    required this.onTap,
    this.child,
    this.filled = false,
  });
  final SunohColors colors;
  final String title;
  final String body;
  final String action;
  final VoidCallback? onTap;
  final Widget? child;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: squircleDecoration(
        radius: 14,
        color: c.surface,
        borderColor: c.line,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: SunohType.sans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: c.fg,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: SunohType.sans(
              fontSize: 12.5,
              color: c.fgMute,
              height: 1.45,
            ),
          ),
          if (child != null) ...[const SizedBox(height: 10), child!],
          const SizedBox(height: 14),
          GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: squircleDecoration(
                radius: 999,
                color: filled ? c.accent : Colors.transparent,
                borderColor: filled ? null : c.line,
              ),
              child: Text(
                action,
                style: SunohType.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: filled ? c.onAccent : c.fg,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
