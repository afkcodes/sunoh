// Queue-level action sheet — opened from the menu-dots in the top-right
// of the queue overlay. Lightweight on purpose; the only action we ship
// today is "Clear queue" (which leaves the currently-playing track in
// place and drops everything after it).
//
// Future additions land here: Save queue as playlist, Sort A→Z, etc.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remixicon/remixicon.dart';

import '../providers/app_state_provider.dart';
import 'sheet.dart';
import 'sheet_row.dart';

Future<void> showQueueMenuSheet(BuildContext context) =>
    showSunohSheet<void>(context, builder: (_) => const _QueueMenuSheet());

class _QueueMenuSheet extends ConsumerWidget {
  const _QueueMenuSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final repo = s.audioRepo;
    final upNext = repo == null
        ? 0
        : (repo.queue.length - repo.currentIndex - 1);

    return SunohSheet(
      title: 'Queue',
      subtitle: upNext > 0 ? '$upNext upcoming' : 'Nothing up next',
      // Disabled rather than hidden when there is nothing to clear, so the
      // sheet does not open onto a title and no actions at all.
      child: SheetRow(
        icon: RemixIcons.delete_bin_line,
        label: 'Clear queue',
        enabled: upNext > 0,
        onTap: () {
          Navigator.of(context).pop();
          s.apiClearUpNext();
          s.flashToast('Queue cleared');
        },
        colors: c,
      ),
    );
  }
}
