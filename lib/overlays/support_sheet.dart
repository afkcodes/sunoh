// The "Support sunoh." card, opened as a sheet from the heart on Home.
//
// Same card as the one pinned in Settings (widgets/support_card.dart), so the
// two entry points cannot drift apart. A sheet rather than a push to
// Settings: supporting the app is a ten-second action, and landing on a long
// settings page to find it at the top would make it feel like a chore.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_state_provider.dart';
import '../widgets/support_card.dart';
import 'sheet.dart';

Future<void> showSupportSheet(BuildContext context) => showSunohSheet<void>(
  context,
  builder: (_) => const SunohSheet(child: _SupportBody()),
);

class _SupportBody extends ConsumerWidget {
  const _SupportBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SupportCard(colors: s.colors, accent: s.resolvedAccent),
    );
  }
}
