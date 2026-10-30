// A yes/no question asked as a sheet.
//
// The app asks before it throws something away (the play history, a
// playlist), and those questions used to be centre-screen dialogs: the last
// place the app still spoke a second navigation language. They are sheets now,
// for the reasons sheet.dart gives, and they share this one so every "are you
// sure?" reads the same: the question as the title, the consequence under it,
// the way out on the left and the commitment on the right.
//
// The sign-out sheet does not use this. It has a body of its own (three
// reassurances), and a helper that took arbitrary content would be
// SunohSheet again with extra steps.

import 'package:flutter/material.dart';

import 'sheet.dart';

/// True when the user confirmed. Dismissing the sheet is a no, so a stray
/// backdrop tap or a swipe down never deletes anything.
Future<bool> showConfirmSheet(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final result = await showSunohSheet<bool>(
    context,
    builder: (ctx) => SunohSheet(
      title: title,
      subtitle: message,
      actions: SheetActions(
        secondary: SheetButton(
          label: 'Cancel',
          onTap: () => Navigator.of(ctx).pop(false),
        ),
        // Every question here is about throwing something away.
        primary: SheetButton(
          label: confirmLabel,
          danger: true,
          onTap: () => Navigator.of(ctx).pop(true),
        ),
      ),
      // No body: the subtitle already says what happens, and a body would
      // only repeat it further from the buttons.
      child: const SizedBox.shrink(),
    ),
  );
  return result ?? false;
}
