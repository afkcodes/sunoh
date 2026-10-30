// Downloads — flat list of every song the user has cached on device, plus
// the in-flight rows so tapping "Download" feels alive instead of silent.
// A big page title, then list rows; the pinned bar takes the title over once
// it scrolls away.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remixicon/remixicon.dart';

import '../api/dto.dart';
import '../audio/download_store.dart';
import '../providers/app_state_provider.dart';
import '../providers/downloads_provider.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/motion.dart';
import '../widgets/ui.dart';
import 'detail_chrome.dart';
import 'detail_hero.dart';

const String _kLabel = 'DOWNLOADS';

final Expando<List<FeedItem>> _playable = Expando('downloaded songs');

/// The finished downloads, in list order: what Play, Shuffle and a row tap
/// queue. Memoised on the entry list, which the provider replaces on change.
List<FeedItem> _doneSongs(List<DownloadEntry> entries) =>
    _playable[entries] ??= [
      for (final e in entries)
        if (e.state == DownloadState.done) e.song,
    ];

class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final async = ref.watch(downloadEntriesProvider);
    final entries = async.asData?.value ?? const <DownloadEntry>[];
    final songs = _doneSongs(entries);
    // This list is the queue when it was started from here.
    final here = s.apiSourceRef == null && s.apiSourceLabel == _kLabel;

    return DetailPage(
      colors: c,
      colour: c.bg,
      title: 'Downloads',
      solidAt: PageTitle.solidAt,
      builder: (_) => [
        SliverToBoxAdapter(
          child: PageTitle(
            colors: c,
            title: 'Downloads',
            trailing: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '${entries.length}',
                style: SunohType.mono(fontSize: 13, color: c.fgMute),
              ),
            ),
          ),
        ),
        if (entries.isEmpty)
          SliverToBoxAdapter(child: _Empty(colors: c))
        else ...[
          SliverToBoxAdapter(
            child: DetailActions(
              colors: c,
              colour: c.accent,
              playing: here && s.isPlaying,
              onShuffle: songs.isEmpty
                  ? null
                  : () => s.playShuffled(songs, sourceLabel: _kLabel),
              onPlay: songs.isEmpty
                  ? null
                  : () => here
                        ? s.playPause()
                        : s.playApiQueue(songs, 0, sourceLabel: _kLabel),
            ),
          ),
          SliverList.builder(
            itemCount: entries.length,
            itemBuilder: (context, i) {
              final row = _DownloadRow(
                entry: entries[i],
                colors: c,
                queue: songs,
              );
              return i < 9 ? Entrance(index: 1 + i, child: row) : row;
            },
          ),
        ],
      ],
    );
  }
}

/// A downloaded (or downloading) song as a list row. Finished ones carry the
/// downloaded badge before their artists; the rest say where they have got
/// to, which is also what a tap does to them — play, or resume.
class _DownloadRow extends ConsumerWidget {
  const _DownloadRow({
    required this.entry,
    required this.colors,
    required this.queue,
  });
  final DownloadEntry entry;
  final SunohColors colors;

  /// The finished downloads; a tap plays them from this song on.
  final List<FeedItem> queue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    final s = ref.read(appStateProvider);
    final mgr = ref.read(downloadManagerProvider);
    final song = entry.song;

    return Pressable(
      scale: 0.99,
      onTap: () {
        if (entry.state == DownloadState.done) {
          // The downloads from this song on, like any other list. The
          // resolver plays each from its file without the network.
          s.playApiQueue(
            queue,
            queue.indexOf(song).clamp(0, queue.length - 1),
            sourceLabel: _kLabel,
          );
        } else if (entry.state == DownloadState.failed ||
            entry.state == DownloadState.paused) {
          mgr.resume(song.id);
        }
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
        child: Row(
          children: [
            SunohArt(
              id: song.id,
              imageUrl: song.artwork,
              size: 48,
              radius: SunohRadius.row,
              shadow: false,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SunohType.sans(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: c.fg,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 1),
                  _Subtitle(entry: entry, colors: c),
                ],
              ),
            ),
            IconBtn(
              icon: RemixIcons.delete_bin_2_line,
              color: c.fgMute,
              size: 18,
              onTap: () => mgr.remove(song.id),
            ),
          ],
        ),
      ),
    );
  }
}

class _Subtitle extends ConsumerWidget {
  const _Subtitle({required this.entry, required this.colors});
  final DownloadEntry entry;
  final SunohColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    final artists = (entry.song.artists ?? const [])
        .map((a) => a.name.trim())
        .where((n) => n.isNotEmpty)
        .take(2)
        .join(', ');
    final String state;
    switch (entry.state) {
      case DownloadState.done:
        // The 14 accent square that marks a song as on the device.
        return Row(
          children: [
            Container(
              width: 14,
              height: 14,
              margin: const EdgeInsets.only(right: 6),
              decoration: squircleDecoration(
                radius: SunohRadius.xs,
                color: c.accent,
              ),
              child: Icon(
                RemixIcons.download_2_line,
                size: 10,
                color: c.onAccent,
              ),
            ),
            Flexible(
              child: Text(
                artists,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SunohType.sans(fontSize: 13, color: c.fgDim),
              ),
            ),
          ],
        );
      case DownloadState.queued:
        state = 'Queued';
      case DownloadState.downloading:
        // Live percent. "Downloading…" until the first Dio chunk lands, a
        // hundred ms or so in.
        final p = ref
            .watch(downloadProgressProvider(entry.song.id))
            .asData
            ?.value;
        state = p == null
            ? 'Downloading…'
            : 'Downloading… ${(p.fraction * 100).round()}%';
      case DownloadState.paused:
        state = 'Paused — tap to resume';
      case DownloadState.failed:
        state = 'Failed — ${entry.error ?? "tap to retry"}';
    }
    return Text(
      artists.isEmpty ? state : '$state · $artists',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: SunohType.sans(fontSize: 13, color: c.fgMute),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.colors});
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 60, 16, 60),
      child: Center(
        child: Column(
          children: [
            Icon(RemixIcons.download_2_line, size: 36, color: c.fgMute),
            const SizedBox(height: 14),
            Text(
              'No downloads yet',
              style: SunohType.heading(fontSize: 22, color: c.fgDim),
            ),
            const SizedBox(height: 8),
            Text(
              'Open a saavn song, album, or playlist and tap '
              'Download to save it for offline listening.',
              textAlign: TextAlign.center,
              style: SunohType.sans(fontSize: 13, color: c.fgMute),
            ),
          ],
        ),
      ),
    );
  }
}
