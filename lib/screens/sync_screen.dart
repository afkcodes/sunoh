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

import '../providers/app_state_provider.dart';
import '../providers/sync_provider.dart';
import '../sync/sync_service.dart';
import '../theme/tokens.dart';
import '../widgets/motion.dart';
import '../widgets/ui.dart';
import 'pill_button.dart';
import 'sub_page_bar.dart';

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

  Future<void> _setUp(SyncService sync) => _run(() async {
    final code = await sync.setUp();
    if (code != null && mounted) setState(() => _revealedCode = code);
  });

  Future<void> _join(SyncService sync) => _run(() async {
    final ok = await sync.joinWithCode(_codeController.text);
    if (!mounted) return;
    ref
        .read(appStateProvider)
        .flashToast(
          ok ? 'Synced' : 'Could not read that folder with this code',
        );
  });

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(appStateProvider).colors;
    final sync = ref.watch(syncProvider);
    final intro = Text(
      'Keep liked songs, playlists and settings the same on two '
      'phones. sunoh writes an encrypted file into a folder you '
      'choose. Whatever syncs that folder moves it. There is no '
      'account and nothing is sent to us.',
      style: SunohType.sans(fontSize: 14, color: c.fgDim, height: 1.45),
    );
    final body = sync.isConfigured
        ? _Configured(sync: sync, colors: c, busy: _busy, run: _run)
        : _Setup(
            colors: c,
            busy: _busy,
            controller: _codeController,
            onSetUp: () => _setUp(sync),
            onJoin: () => _join(sync),
          );

    return ColoredBox(
      color: c.bg,
      child: Column(
        children: [
          SubPageBar(title: 'Sync', colors: c),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 140),
              children: [
                FadeSlideIn(child: intro),
                const SizedBox(height: 20),
                FadeSlideIn(index: 1, child: body),
                if (_revealedCode != null)
                  FadeSlideIn(
                    child: _RecoveryCode(code: _revealedCode!, colors: c),
                  ),
              ],
            ),
          ),
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Card(
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
        const SizedBox(height: 12),
        _Card(
          colors: c,
          title: 'Join from another phone',
          body:
              'Enter the recovery code from the phone you set up first, '
              'then pick the same folder.',
          action: busy ? 'Working…' : 'Pick folder and join',
          onTap: busy ? null : onJoin,
          // The field is a well on the card: surface2 on surface, the way a
          // control sits on a card everywhere else.
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: squircleDecoration(
              radius: SunohRadius.tile,
              color: c.surface2,
            ),
            child: TextField(
              controller: controller,
              autocorrect: false,
              enableSuggestions: false,
              style: SunohType.mono(fontSize: 13.5, color: c.fg),
              decoration: InputDecoration(
                hintText: 'Recovery code',
                hintStyle: SunohType.mono(fontSize: 13.5, color: c.fgMute),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: PillButton(
            label: 'Stop syncing on this phone',
            colors: c,
            onTap: busy
                ? null
                : () => run(() async {
                    await sync.disable();
                  }),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Your library stays on this phone. Only this device\'s file is '
          'removed from the folder.',
          style: SunohType.sans(fontSize: 12.5, color: c.fgMute, height: 1.4),
        ),
      ],
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
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      // Tinted rather than outlined: it is the one card on the screen that
      // must not be skimmed past, and a hairline does not stop anyone.
      decoration: squircleDecoration(
        radius: SunohRadius.card,
        color: c.accent.withValues(alpha: 0.12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          eyebrow('RECOVERY CODE', c.accent, size: 10.5, letterSpacing: 0.84),
          const SizedBox(height: 10),
          SelectableText(
            code,
            style: SunohType.mono(fontSize: 13.5, color: c.fg, height: 1.5),
          ),
          const SizedBox(height: 10),
          Text(
            'Enter this on your other phone. Keep a copy somewhere safe: it '
            'is the only thing that can read the folder, it is never sent '
            'anywhere, and it cannot be recovered if lost.',
            style: SunohType.sans(fontSize: 13, color: c.fgDim, height: 1.45),
          ),
          const SizedBox(height: 14),
          PillButton(
            label: 'Copy code',
            colors: c,
            primary: true,
            onTap: () => Clipboard.setData(ClipboardData(text: code)),
          ),
        ],
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
      padding: const EdgeInsets.all(14),
      decoration: squircleDecoration(
        radius: SunohRadius.card,
        color: c.surface,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: SunohType.sans(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: c.fg,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: SunohType.sans(fontSize: 13, color: c.fgDim, height: 1.45),
          ),
          if (child != null) ...[const SizedBox(height: 12), child!],
          const SizedBox(height: 14),
          PillButton(label: action, colors: c, primary: filled, onTap: onTap),
        ],
      ),
    );
  }
}
