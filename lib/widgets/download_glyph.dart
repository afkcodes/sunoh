// A song's download state, small enough to live in a track row.
//
// The percentage used to exist only inside the track menu sheet, which meant
// starting a download and then wanting to know how it was going cost two taps
// and covered the list you were looking at. A row can say it itself.
//
// The ring is the reason this is split into two widgets. Per-byte progress
// arrives on a stream per chunk, and a row that watched it would rebuild
// constantly for every song in the list — including the overwhelming majority
// that are not downloading. Only [_ProgressRing] subscribes, and it only
// exists while a download is actually running, so an idle list holds no
// subscriptions at all.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../audio/download_store.dart';
import '../providers/downloads_provider.dart';
import '../theme/tokens.dart';

class DownloadGlyph extends ConsumerWidget {
  const DownloadGlyph({
    super.key,
    required this.songId,
    required this.colors,
    this.size = 13,
  });

  final String songId;
  final SunohColors colors;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = watchDownloadEntry(ref, songId)?.state;
    // The common case by a wide margin: nothing to say, so nothing rendered.
    if (state == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: switch (state) {
        DownloadState.downloading => _ProgressRing(
          songId: songId,
          colors: colors,
          size: size,
        ),
        DownloadState.done => Icon(
          SolarIconsBold.checkCircle,
          size: size,
          color: colors.accent,
        ),
        DownloadState.queued => Icon(
          SolarIconsOutline.clockCircle,
          size: size,
          color: colors.fgMute,
        ),
        DownloadState.paused => Icon(
          SolarIconsOutline.pauseCircle,
          size: size,
          color: colors.fgMute,
        ),
        DownloadState.failed => Icon(
          SolarIconsOutline.dangerCircle,
          size: size,
          color: colors.fgMute,
        ),
      },
    );
  }
}

/// The live ring. Mounted only while a song is downloading — see the file
/// header for why that matters.
class _ProgressRing extends ConsumerWidget {
  const _ProgressRing({
    required this.songId,
    required this.colors,
    required this.size,
  });

  final String songId;
  final SunohColors colors;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(downloadProgressProvider(songId)).asData?.value;
    // Null until the first chunk lands, and null when the server sends no
    // content-length. CircularProgressIndicator spins on a null value, which
    // is the honest thing to show for "started, size unknown" rather than a
    // ring frozen at zero that looks stuck.
    final value = progress == null || progress.total <= 0
        ? null
        : progress.fraction;

    return RepaintBoundary(
      child: SizedBox(
        width: size + 3,
        height: size + 3,
        child: CircularProgressIndicator(
          value: value,
          strokeWidth: 2,
          color: colors.accent,
          backgroundColor: colors.line,
        ),
      ),
    );
  }
}
