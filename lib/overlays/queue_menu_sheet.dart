// Queue-level action sheet — opened from the menu-dots in the top-right
// of the queue overlay. Lightweight on purpose; the only action we ship
// today is "Clear queue" (which leaves the currently-playing track in
// place and drops everything after it).
//
// Future additions land here: Save queue as playlist, Sort A→Z, etc.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../providers/app_state_provider.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';

Future<void> showQueueMenuSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useRootNavigator: true,
    builder: (_) => const _QueueMenuSheet(),
  );
}

class _QueueMenuSheet extends ConsumerWidget {
  const _QueueMenuSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final topInset = MediaQuery.of(context).padding.bottom;
    final repo = s.audioRepo;
    final upNext =
        repo == null ? 0 : (repo.queue.length - repo.currentIndex - 1);

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        decoration: squircleDecoration(
          radius: 20,
          color: const Color(0xFF15151A),
          borderColor: c.line,
        ),
        padding: EdgeInsets.fromLTRB(0, 8, 0, 8 + topInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 6, 22, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Queue',
                            style: SunohType.sans(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w500,
                                color: c.fg)),
                        const SizedBox(height: 3),
                        Text(
                            upNext > 0
                                ? '$upNext upcoming'
                                : 'Nothing up next',
                            style: SunohType.sans(
                                fontSize: 12, color: c.fgMute)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
                height: 0.5,
                color: c.line,
                margin: const EdgeInsets.symmetric(horizontal: 12)),
            _QueueMenuRow(
              icon: SolarIconsOutline.trashBinTrash,
              label: 'Clear queue',
              enabled: upNext > 0,
              onTap: () {
                Navigator.of(context).pop();
                s.apiClearUpNext();
                s.flashToast('Queue cleared');
              },
              colors: c,
            ),
          ],
        ),
      ),
    );
  }
}

class _QueueMenuRow extends StatelessWidget {
  const _QueueMenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.colors,
    this.enabled = true,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final SunohColors colors;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final color = enabled ? c.fg : c.fgMute;
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 16),
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SunohType.sans(fontSize: 14, color: color)),
            ),
          ],
        ),
      ),
    );
  }
}
