// "Update available" card rendered inside Settings → About.
//
// The home-screen banner variant lived here too once — it was replaced
// (v1.7.2) by the auto-show update DIALOG (see widgets/update_dialog.dart)
// because users were ignoring the slim ribbon. The Settings card stays
// as a discoverability backstop: if the user dismisses the dialog or
// skips the version, they can still find the update via Settings →
// About. Tapping the card re-opens the same dialog.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../api/updates.dart';
import '../providers/app_state_provider.dart';
import '../providers/update_provider.dart';
import '../theme/tokens.dart';
import 'ui.dart';
import 'update_sheet.dart';

/// Card variant — used inside Settings → About so the same info has a
/// home if the user dismissed the auto-shown dialog on Home. Designed
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
    final accent = s.resolvedAccent;
    final async = ref.watch(availableUpdateProvider);
    final info = async.asData?.value;
    if (info == null) return const SizedBox.shrink();
    return _UpdateRow(info: info, colors: c, accent: accent, slim: false);
  }
}

class _UpdateRow extends ConsumerWidget {
  const _UpdateRow({
    required this.info,
    required this.colors,
    required this.accent,
    required this.slim,
  });
  final UpdateInfo info;
  final SunohColors colors;
  final Color accent;
  final bool slim;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // Re-open the auto-show dialog — keeps Settings as a backstop
      // for the user who dismissed the home dialog with "Later" and
      // came back later to actually update.
      onTap: () => showUpdateSheet(context, info),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: slim ? 12 : 16),
        decoration: squircleDecoration(
          radius: 14,
          // Subtle tinted surface — accent at low alpha layered over the
          // section bg so the ribbon reads as "soft notice" not "warning".
          color: Color.alphaBlend(accent.withValues(alpha: 0.13), c.surface),
          borderColor: accent.withValues(alpha: 0.45),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.22),
                shape: BoxShape.circle,
              ),
              child: Icon(
                SolarIconsBold.downloadMinimalistic,
                size: 16,
                color: accent,
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
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: c.fg,
                    ),
                  ),
                  if ((info.notes ?? '').isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      info.notes!,
                      maxLines: slim ? 1 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: SunohType.sans(
                        fontSize: 12,
                        color: c.fgMute,
                        height: 1.3,
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 2),
                    Text(
                      'Tap to open the release on GitHub',
                      style: SunohType.sans(fontSize: 12, color: c.fgMute),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => dismissAvailableUpdate(ref, info.version),
              child: SizedBox(
                width: 32,
                height: 32,
                child: Icon(
                  SolarIconsOutline.closeCircle,
                  size: 18,
                  color: c.fgMute,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
