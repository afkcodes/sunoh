// Confirming a YouTube sign-out.
//
// Signing out is asked about and signing in is not, because the two are not
// symmetrical: signing in adds a home feed, and signing out throws away the
// session, empties the personal library shelves and drops the cookie. Getting
// back means Google's login flow again, possibly with a second factor.
//
// The sheet says where the session actually lives. "Sign in with Google" in a
// third-party app is exactly the kind of thing a careful person should be
// suspicious of, and the honest answer is the reassuring one.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remixicon/remixicon.dart';

import '../providers/app_state_provider.dart';
import '../theme/tokens.dart';
import 'sheet.dart';

/// True when the user confirmed. Dismissing the sheet is a no.
Future<bool> showYtSignOutSheet(
  BuildContext context,
  String accountName,
) async {
  final result = await showSunohSheet<bool>(
    context,
    builder: (_) => _SignOutSheet(accountName: accountName),
  );
  return result ?? false;
}

class _SignOutSheet extends ConsumerWidget {
  const _SignOutSheet({required this.accountName});
  final String accountName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(appStateProvider).colors;
    return SunohSheet(
      title: 'Sign out of YouTube Music?',
      subtitle: accountName.isEmpty ? null : accountName,
      actions: SheetActions(
        secondary: SheetButton(
          label: 'Stay signed in',
          onTap: () => Navigator.of(context).pop(false),
        ),
        primary: SheetButton(
          label: 'Sign out',
          filled: true,
          onTap: () => Navigator.of(context).pop(true),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Point(
              icon: RemixIcons.play_list_add_line,
              text:
                  'Your recommendations and YouTube library shelves go back '
                  'to the generic ones.',
              colors: c,
            ),
            const SizedBox(height: 14),
            _Point(
              icon: RemixIcons.heart_3_line,
              text:
                  'Everything you saved in sunoh stays. Nothing on your '
                  'YouTube account is changed.',
              colors: c,
            ),
            const SizedBox(height: 14),
            _Point(
              icon: RemixIcons.shield_check_line,
              text:
                  'The session is deleted from this phone. It was only ever '
                  'stored here, encrypted, and never sent anywhere.',
              colors: c,
            ),
          ],
        ),
      ),
    );
  }
}

/// One reassurance, with its own icon. A wall of prose in a confirmation is
/// not read; three short lines with a mark against each are. The icon takes
/// the sheet row's size and ink, so the three read as the same family as the
/// option rows on every other sheet.
class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text, required this.colors});

  final IconData icon;
  final String text;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22, color: c.fgDim),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            text,
            style: SunohType.sans(fontSize: 14, color: c.fgDim, height: 1.45),
          ),
        ),
      ],
    );
  }
}
