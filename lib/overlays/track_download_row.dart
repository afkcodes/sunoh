// The Download row of the track menu, in every one of its states.
//
// Split out of `track_menu_sheet.dart`: every other row there is a label and
// an action, and this one is a small state machine over the download manager
// with its own live subscription, which is a different kind of thing.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remixicon/remixicon.dart';

import '../api/dto.dart';
import '../audio/download_store.dart';
import '../providers/app_state_provider.dart';
import '../providers/downloads_provider.dart';
import '../theme/tokens.dart';
import 'sheet_row.dart';

/// The Download row in the track-action sheet. Renders one state per
/// [DownloadEntry] state (or absence of one):
///   * no entry     → "Download" with a download glyph; tap queues
///   * queued       → "Queued…", disabled
///   * downloading  → "Downloading…" with live percent; tap pauses
///   * paused       → "Resume download"
///   * done         → "Downloaded" with a check + tap to remove
///   * failed       → "Retry download" with a refresh glyph
///
/// Subscribes to [downloadProgressProvider] for the live percent so the
/// row stays in sync while staying decoupled from the manager internals.
class TrackDownloadRow extends ConsumerWidget {
  const TrackDownloadRow({super.key, required this.song, required this.colors});
  final FeedItem song;
  final SunohColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    final entry = watchDownloadEntry(ref, song.id);
    final mgr = ref.read(downloadManagerProvider);

    IconData icon;
    String label;
    VoidCallback? onTap;
    Color? iconColor;

    switch (entry?.state) {
      case null:
        icon = RemixIcons.download_2_line;
        label = 'Download';
        onTap = () {
          Navigator.of(context).pop();
          mgr.enqueue(song);
          ref.read(appStateProvider).flashToast('Downloading…');
        };
      case DownloadState.queued:
        icon = RemixIcons.time_line;
        label = 'Queued…';
        onTap = null;
      case DownloadState.downloading:
        final progress = ref
            .watch(downloadProgressProvider(song.id))
            .asData
            ?.value;
        final pct = progress == null
            ? null
            : (progress.fraction * 100).clamp(0.0, 100.0);
        icon = RemixIcons.download_2_line;
        label = pct == null
            ? 'Downloading…'
            : 'Downloading… ${pct.toStringAsFixed(0)}%';
        onTap = () {
          Navigator.of(context).pop();
          mgr.pause(song.id);
          ref.read(appStateProvider).flashToast('Paused');
        };
      case DownloadState.paused:
        icon = RemixIcons.play_circle_line;
        label = 'Resume download';
        onTap = () {
          Navigator.of(context).pop();
          mgr.resume(song.id);
        };
      case DownloadState.done:
        icon = RemixIcons.checkbox_circle_fill;
        iconColor = c.accent;
        label = 'Downloaded — tap to remove';
        onTap = () {
          Navigator.of(context).pop();
          mgr.remove(song.id);
          ref.read(appStateProvider).flashToast('Removed from downloads');
        };
      case DownloadState.failed:
        icon = RemixIcons.refresh_line;
        label = 'Retry download';
        onTap = () {
          Navigator.of(context).pop();
          mgr.resume(song.id);
        };
    }

    // Queued has nothing to do on tap, and now looks it: the row drops to
    // fgMute instead of sitting at full ink and ignoring the thumb.
    return SheetRow(
      icon: icon,
      label: label,
      iconColor: iconColor,
      onTap: onTap,
      enabled: onTap != null,
      colors: c,
    );
  }
}
