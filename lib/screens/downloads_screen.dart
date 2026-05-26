// Downloads tab — flat list of every song the user has cached on device,
// plus the in-flight rows so tapping "Download" feels alive instead of
// silent. Reuses `_TrackMenuSheet` for per-row actions (Play next /
// Remove / etc) by routing through `s.playApiSong`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';

import '../audio/download_store.dart';
import '../providers/app_state_provider.dart';
import '../providers/downloads_provider.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/ui.dart';

class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final async = ref.watch(downloadEntriesProvider);
    final entries = async.asData?.value ?? const <DownloadEntry>[];

    return ColoredBox(
      color: c.bg,
      child: ListView(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 12,
          bottom: 140,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(
              children: [
                IconBtn(
                    icon: SolarIconsOutline.altArrowLeft,
                    color: c.fgDim,
                    size: 18,
                    onTap: () => context.pop()),
                const SizedBox(width: 4),
                Text('Downloads',
                    style: SunohType.heading(
                        fontSize: 24, color: c.fg, letterSpacing: -0.4)),
                const Spacer(),
                Text('${entries.length}',
                    style: SunohType.mono(fontSize: 13, color: c.fgMute)),
              ],
            ),
          ),
          if (entries.isEmpty)
            _Empty(colors: c)
          else
            for (final e in entries)
              _DownloadRow(entry: e, colors: c, accent: s.resolvedAccent),
        ],
      ),
    );
  }
}

class _DownloadRow extends ConsumerWidget {
  const _DownloadRow({
    required this.entry,
    required this.colors,
    required this.accent,
  });
  final DownloadEntry entry;
  final SunohColors colors;
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    final s = ref.read(appStateProvider);
    final mgr = ref.read(downloadManagerProvider);
    final song = entry.song;
    final artistsLabel = (song.artists ?? const [])
        .map((a) => a.name.trim())
        .where((n) => n.isNotEmpty)
        .take(2)
        .join(', ');

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (entry.state == DownloadState.done) {
          // Play just the downloaded song. The handler/resolver will
          // pick up file:// via LocalSourceProvider without going out
          // to the network.
          s.playApiSong(song, sourceLabel: 'DOWNLOADS');
        } else if (entry.state == DownloadState.failed ||
            entry.state == DownloadState.paused) {
          mgr.resume(song.id);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            SunohArt(
                id: song.id, imageUrl: song.artwork, size: 46, radius: 6),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SunohType.sans(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w500,
                          color: c.fg)),
                  if (artistsLabel.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(artistsLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SunohType.sans(
                            fontSize: 12, color: c.fgMute)),
                  ],
                  const SizedBox(height: 4),
                  _StateLine(entry: entry, colors: c, accent: accent),
                ],
              ),
            ),
            IconBtn(
                icon: SolarIconsOutline.trashBin2,
                color: c.fgMute,
                size: 16,
                width: 36,
                height: 36,
                onTap: () => mgr.remove(song.id)),
          ],
        ),
      ),
    );
  }
}

class _StateLine extends ConsumerWidget {
  const _StateLine({
    required this.entry,
    required this.colors,
    required this.accent,
  });
  final DownloadEntry entry;
  final SunohColors colors;
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    switch (entry.state) {
      case DownloadState.done:
        return Row(
          children: [
            Icon(SolarIconsBold.checkCircle, size: 11, color: accent),
            const SizedBox(width: 5),
            Text('Saved on device',
                style: SunohType.sans(fontSize: 11, color: c.fgMute)),
          ],
        );
      case DownloadState.queued:
        return Text('Queued',
            style: SunohType.sans(fontSize: 11, color: c.fgMute));
      case DownloadState.downloading:
        // Live percent. Falls back to "Downloading…" while we wait for
        // the first Dio chunk (a hundred ms or so).
        final p = ref
            .watch(downloadProgressProvider(entry.song.id))
            .asData
            ?.value;
        final pct = p == null ? null : (p.fraction * 100).round();
        return Text(
            pct == null ? 'Downloading…' : 'Downloading… $pct%',
            style: SunohType.sans(fontSize: 11, color: c.fgMute));
      case DownloadState.paused:
        return Text('Paused — tap to resume',
            style: SunohType.sans(fontSize: 11, color: c.fgMute));
      case DownloadState.failed:
        return Text(
            'Failed — ${entry.error ?? "tap to retry"}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SunohType.sans(fontSize: 11, color: c.fgMute));
    }
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.colors});
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 80, 28, 80),
      child: Center(
        child: Column(
          children: [
            Icon(SolarIconsOutline.downloadMinimalistic,
                size: 36, color: c.fgMute),
            const SizedBox(height: 14),
            Text('No downloads yet',
                style: SunohType.heading(fontSize: 22, color: c.fgDim)),
            const SizedBox(height: 8),
            Text(
                'Open a saavn song, album, or playlist and tap '
                'Download to save it for offline listening.',
                textAlign: TextAlign.center,
                style: SunohType.sans(fontSize: 13, color: c.fgMute)),
          ],
        ),
      ),
    );
  }
}
