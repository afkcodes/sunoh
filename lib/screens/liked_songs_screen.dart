// Liked Songs — the first row of the Library opens this. Laid out as an album
// page (hero, actions, numbered tracks) with a made cover in place of
// artwork: the liked list isn't backed by an API image, so it gets the same
// heart-on-accent square the Library row shows, at hero size.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remixicon/remixicon.dart';

import '../providers/app_state_provider.dart';
import '../theme/tokens.dart';
import '../widgets/motion.dart';
import '../widgets/ui.dart';
import 'detail_chrome.dart';
import 'detail_hero.dart';
import 'detail_track_row.dart';

const String _kLabel = 'LIKED · Songs';

class LikedSongsScreen extends ConsumerWidget {
  const LikedSongsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final accent = c.accent;
    final songs = s.likedSongs;
    final labels = TrackLabels.of(songs);
    // This list is the queue when it was started from here: no detail ref,
    // and the label this screen hands the player.
    final here = s.apiSourceRef == null && s.apiSourceLabel == _kLabel;

    return DetailPage(
      colors: c,
      colour: accent,
      title: 'Liked Songs',
      builder: (scroll) => [
        SliverToBoxAdapter(
          child: DetailHero(
            colors: c,
            colour: accent,
            scroll: scroll,
            cover: DetailCover(
              id: 'liked',
              child: _LikedCover(colors: c),
            ),
            title: 'Liked Songs',
            meta: joinMeta(['Playlist', labels.countLine('song')]),
          ),
        ),
        SliverToBoxAdapter(
          child: FadeSlideIn(
            index: 3,
            child: DetailActions(
              colors: c,
              colour: accent,
              playing: here && s.isPlaying,
              leading: [
                // Liked-songs-level menu (share, clear all, download all) is
                // still to come; the button holds its place.
                IconBtn(
                  icon: RemixIcons.more_fill,
                  color: c.fg,
                  onTap: () => s.flashToast('More options coming soon'),
                ),
              ],
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
        ),
        if (songs.isEmpty)
          SliverToBoxAdapter(child: _EmptyState(colors: c))
        else
          SliverPadding(
            padding: const EdgeInsets.only(top: 8),
            sliver: SliverList.builder(
              itemCount: songs.length,
              itemBuilder: (context, i) {
                final row = DetailTrackRow(
                  n: i + 1,
                  song: songs[i],
                  subtitle: labels.subtitles[i],
                  duration: labels.durations[i],
                  colors: c,
                  accent: accent,
                  // Liked songs come from everywhere, so each row shows its
                  // own cover beside the number.
                  showArt: true,
                  sourceLabel: _kLabel,
                  onTap: () => s.playApiQueue(songs, i, sourceLabel: _kLabel),
                );
                return i < 6 ? Entrance(index: 4 + i, child: row) : row;
              },
            ),
          ),
      ],
    );
  }
}

/// Heart on a 135° accent gradient — the Library row's cover, at hero size.
class _LikedCover extends StatelessWidget {
  const _LikedCover({required this.colors});
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    final a = colors.accent;
    return Container(
      width: DetailCover.size,
      height: DetailCover.size,
      decoration: squircleDecoration(
        radius: SunohRadius.cover,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(a, SunohMedia.ink, 0.25)!, a],
        ),
      ),
      child: Icon(RemixIcons.heart_3_fill, size: 96, color: colors.onAccent),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.colors});
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 40, 16, 40),
      child: Column(
        children: [
          Text(
            'No liked songs yet.',
            style: SunohType.heading(fontSize: 18, color: c.fgDim),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap the heart on any song to add it here.',
            textAlign: TextAlign.center,
            style: SunohType.sans(fontSize: 13, color: c.fgMute),
          ),
        ],
      ),
    );
  }
}
