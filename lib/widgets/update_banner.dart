// "Update available" ribbon rendered at the top of Home (and as a card
// in Settings → About). Reads the AsyncValue at
// `availableUpdateProvider` — when it yields a non-null UpdateInfo, the
// banner draws itself; otherwise it's a zero-height SizedBox.
//
// Two affordances: the whole row taps through to the GitHub release URL
// (via url_launcher), and a trailing × dismisses the banner until the
// next published version.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/updates.dart';
import '../providers/app_state_provider.dart';
import '../providers/update_provider.dart';
import '../theme/tokens.dart';
import 'ui.dart';

/// Slim ribbon variant — used at the top of Home so it never steals
/// vertical real-estate from the feed.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final accent = s.resolvedAccent;
    final async = ref.watch(availableUpdateProvider);
    final info = async.asData?.value;
    if (info == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: _UpdateRow(info: info, colors: c, accent: accent, slim: true),
    );
  }
}

/// Card variant — used inside Settings → About so the same info has a
/// home if the user dismissed the Home ribbon. Lives next to "Version".
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: _UpdateRow(info: info, colors: c, accent: accent, slim: false),
    );
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
      onTap: () => _open(info.url),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: slim ? 12 : 16),
        decoration: squircleDecoration(
          radius: 14,
          // Subtle tinted surface — accent at low alpha layered over the
          // section bg so the ribbon reads as "soft notice" not "warning".
          color: Color.alphaBlend(
              accent.withValues(alpha: 0.13), c.surface),
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
              child: Icon(SolarIconsBold.downloadMinimalistic,
                  size: 16, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Update available · v${info.version}',
                      style: SunohType.sans(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: c.fg)),
                  if ((info.notes ?? '').isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(info.notes!,
                        maxLines: slim ? 1 : 3,
                        overflow: TextOverflow.ellipsis,
                        style: SunohType.sans(
                            fontSize: 12, color: c.fgMute, height: 1.3)),
                  ] else ...[
                    const SizedBox(height: 2),
                    Text('Tap to open the release on GitHub',
                        style: SunohType.sans(fontSize: 12, color: c.fgMute)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () =>
                  dismissAvailableUpdate(ref, info.version),
              child: SizedBox(
                width: 32,
                height: 32,
                child: Icon(SolarIconsOutline.closeCircle,
                    size: 18, color: c.fgMute),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {/* user can re-tap; no toast spam */}
  }
}
