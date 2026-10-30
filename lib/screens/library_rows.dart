// The Library tab's big list row, and the three shortcut rows that lead the
// list.
//
// Liked songs, Recently played and Downloads used to be three stacked tiles
// sharing a row above the list. In the prototype they are simply its first
// rows — same 56 art, same title and subtitle — with a painted square where a
// cover would be. That reads as "these are in your library too" rather than
// as a toolbar, and it gives the titles a full row instead of a third of one.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remixicon/remixicon.dart';

import '../audio/download_store.dart';
import '../providers/downloads_provider.dart';
import '../router/router.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/motion.dart';
import '../widgets/playing_bars.dart';
import '../widgets/ui.dart';

/// Ids of songs whose download has finished, rebuilt only when the download
/// list changes. Rows ask it about one id through `select`, so a download
/// landing repaints that song's badge and nothing else — the alternative,
/// every row scanning the whole download list, is quadratic in the library.
final _finishedDownloads = Provider.autoDispose<Set<String>>((ref) {
  final entries =
      ref.watch(downloadEntriesProvider).asData?.value ??
      const <DownloadEntry>[];
  return {
    for (final e in entries)
      if (e.state == DownloadState.done) e.id,
  };
});

class LibraryRow extends StatelessWidget {
  const LibraryRow({
    super.key,
    required this.art,
    required this.title,
    required this.subtitle,
    required this.colors,
    required this.onTap,
    this.downloadId,
    this.playing = false,
    this.animate = false,
  });

  /// 56 square, already clipped by the caller.
  final Widget art;
  final String title;
  final String subtitle;
  final SunohColors colors;
  final VoidCallback onTap;

  /// The song to check for a finished download, which earns the row the
  /// small accent badge before its subtitle. Null for anything that is not a
  /// single song: nothing records a whole album or playlist as downloaded.
  final String? downloadId;

  /// This row's song is the one loaded in the player: accent title and bars.
  final bool playing;

  /// Whether the bars move — they hold still while playback is paused.
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Pressable(
      scale: 0.99,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            art,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SunohType.sans(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: playing ? c.accent : c.fg,
                            height: 1.3,
                          ),
                        ),
                      ),
                      if (playing) ...[
                        const SizedBox(width: 8),
                        // 13: three 3-wide bars and two 2 gaps.
                        PlayingBars(
                          color: c.accent,
                          size: 13,
                          animate: animate,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 1),
                  Row(
                    children: [
                      if (downloadId != null)
                        _DownloadedBadge(id: downloadId!, colors: c),
                      Expanded(
                        child: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SunohType.sans(fontSize: 13, color: c.fgDim),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 14 square accent badge with a download glyph, only once the song is on
/// disk. Queued and in-flight downloads say nothing here; the Downloads screen
/// is where progress lives.
class _DownloadedBadge extends ConsumerWidget {
  const _DownloadedBadge({required this.id, required this.colors});
  final String id;
  final SunohColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final done = ref.watch(_finishedDownloads.select((s) => s.contains(id)));
    if (!done) return const SizedBox.shrink();
    return Container(
      width: 14,
      height: 14,
      margin: const EdgeInsets.only(right: 6),
      alignment: Alignment.center,
      decoration: squircleDecoration(
        radius: SunohRadius.xs,
        color: colors.accent,
      ),
      child: Icon(
        RemixIcons.download_2_fill,
        size: 10,
        color: colors.onAccent,
      ),
    );
  }
}

/// A painted 56 square for the rows that have no cover of their own. Liked
/// songs is the accent, lit from the top left; the others sit on surface2 so
/// the one collection the user built by hand stands out from the two the app
/// keeps for them. The accent follows the artwork when tinting is on, so the
/// fill tweens rather than snapping on every track change.
class LibraryGlyphArt extends StatelessWidget {
  const LibraryGlyphArt({
    super.key,
    required this.icon,
    required this.colors,
    this.liked = false,
  });

  final IconData icon;
  final SunohColors colors;
  final bool liked;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    if (!liked) {
      return Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: squircleDecoration(
          radius: SunohRadius.row,
          color: c.surface2,
        ),
        child: Icon(icon, size: 24, color: c.fgDim),
      );
    }
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: c.accent),
      duration: const Duration(milliseconds: 700),
      curve: SunohMotion.ease,
      builder: (_, accent, child) => Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: squircleDecoration(
          radius: SunohRadius.row,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color.lerp(accent, Colors.white, 0.25)!, accent!],
          ),
        ),
        child: child,
      ),
      child: Icon(icon, size: 24, color: c.onAccent),
    );
  }
}

/// Liked songs, Recently played and Downloads as the list's first rows. Each
/// shows a real count and opens its own screen.
class LibraryShortcuts extends StatelessWidget {
  const LibraryShortcuts({
    super.key,
    required this.state,
    required this.colors,
  });

  final AppState state;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final liked = state.likedSongs.length;
    final played = state.playedHistory.length;
    return Column(
      children: [
        LibraryRow(
          art: LibraryGlyphArt(
            icon: RemixIcons.heart_3_fill,
            colors: c,
            liked: true,
          ),
          title: 'Liked songs',
          subtitle: 'Playlist · $liked ${liked == 1 ? 'song' : 'songs'}',
          colors: c,
          onTap: () => context.openLikedSongs(),
        ),
        LibraryRow(
          art: LibraryGlyphArt(icon: RemixIcons.time_line, colors: c),
          title: 'Recently played',
          subtitle: played == 0
              ? 'No history yet'
              : '$played recent ${played == 1 ? 'song' : 'songs'}',
          colors: c,
          onTap: () => context.openRecentlyPlayed(),
        ),
        Consumer(
          builder: (context, ref, _) {
            // The live download list, so the count moves the moment a
            // download lands without rebuilding the whole Library through
            // AppState.
            final n =
                ref.watch(downloadEntriesProvider).asData?.value.length ?? 0;
            return LibraryRow(
              art: LibraryGlyphArt(
                icon: RemixIcons.download_2_line,
                colors: c,
              ),
              title: 'Downloads',
              subtitle: n == 0
                  ? 'Tap a song to save'
                  : '$n ${n == 1 ? 'song' : 'songs'}',
              colors: c,
              onTap: () => context.openDownloads(),
            );
          },
        ),
      ],
    );
  }
}
