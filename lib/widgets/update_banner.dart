// "Update available" card rendered inside Settings → About.
//
// The home-screen banner variant lived here too once — it was replaced
// (v1.7.2) by the auto-show update sheet (see widgets/update_sheet.dart)
// because users were ignoring the slim ribbon. The Settings card stays
// as a discoverability backstop: if the user dismisses the sheet or
// skips the version, they can still find the update via Settings →
// About. Tapping the card re-opens the same sheet.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remixicon/remixicon.dart';

import '../api/updates.dart';
import '../providers/app_state_provider.dart';
import '../providers/update_provider.dart';
import '../theme/tokens.dart';
import 'motion.dart';
import 'ui.dart';
import 'update_sheet.dart';

/// Card variant — used inside Settings → About so the same info has a
/// home if the user dismissed the auto-shown sheet on Home. Designed
/// to live as the first row inside a `_Section`, so it inherits the
/// section's horizontal padding — no extra padding here. Returns
/// SizedBox.shrink when no update is published so the caller doesn't
/// need to gate.
class UpdateAboutCard extends ConsumerWidget {
  const UpdateAboutCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final async = ref.watch(availableUpdateProvider);
    final info = async.asData?.value;
    if (info == null) return const SizedBox.shrink();
    return _UpdateCard(info: info, colors: c);
  }
}

/// The prototype's card: surface fill, card radius, no outline, title over a
/// dimmer line. The accent is spent on one small mark, not on tinting the
/// whole card — a notice, not a warning.
class _UpdateCard extends ConsumerWidget {
  const _UpdateCard({required this.info, required this.colors});
  final UpdateInfo info;
  final SunohColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    final notes = info.notes ?? '';
    return Pressable(
      // Re-open the auto-show sheet — keeps Settings as a backstop for the
      // user who dismissed it on Home and came back later to update.
      onTap: () => showUpdateSheet(context, info),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
        decoration: squircleDecoration(
          radius: SunohRadius.card,
          color: c.surface,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: squircleDecoration(
                radius: SunohRadius.tile,
                color: c.accent,
              ),
              child: Icon(
                RemixIcons.download_2_fill,
                size: 20,
                color: c.onAccent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Update available · v${info.version}',
                    style: SunohType.sans(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: c.fg,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    notes.isNotEmpty
                        ? notes
                        : 'Tap to open the release on GitHub',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: SunohType.sans(
                      fontSize: 12.5,
                      color: c.fgDim,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            IconBtn(
              icon: RemixIcons.close_circle_line,
              size: 18,
              color: c.fgMute,
              onTap: () => dismissAvailableUpdate(ref, info.version),
            ),
          ],
        ),
      ),
    );
  }
}
