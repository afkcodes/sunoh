// Track context-menu bottom sheet. The ⋯ button on every track row (album,
// playlist, search, library, etc.) routes here.
//
// Header is the song's artwork + title + artist. Below it: a vertical list
// of actions — play next, add to queue, like / unlike, view artist, share.
//
// Reusable: callers pass the song (+ optional source label for play-next /
// add-to-queue) and we wire everything off `AppState`. Each action closes
// the sheet via `Navigator.of(ctx).pop()` before performing its side-effect
// so the user sees the sheet dismiss instantly rather than waiting on Hive
// or the audio engine.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../api/dto.dart';
import '../data/models.dart';
import '../providers/app_state_provider.dart';
import '../router/router.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/ui.dart';

/// Open the bottom sheet for [song]. [sourceLabel] is the "PLAYING FROM"
/// label that gets passed to play-next / add-to-queue so the engine knows
/// where the user kicked the queue from.
Future<void> showTrackMenuSheet(
  BuildContext context, {
  required FeedItem song,
  String? sourceLabel,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _TrackMenuSheet(song: song, sourceLabel: sourceLabel),
  );
}

class _TrackMenuSheet extends ConsumerWidget {
  const _TrackMenuSheet({required this.song, this.sourceLabel});
  final FeedItem song;
  final String? sourceLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final liked = s.isLikedId(song.id);
    final accent = s.resolvedAccent;
    final artistsLabel = (song.artists ?? const <ApiArtistRef>[])
        .map((a) => a.name.trim())
        .where((sa) => sa.isNotEmpty)
        .take(2)
        .join(', ');
    final hasArtist = (song.artists ?? const []).isNotEmpty;
    final topInset = MediaQuery.of(context).padding.bottom;

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
            // Drag handle.
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Track header.
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
              child: Row(
                children: [
                  SunohArt(
                      id: song.id,
                      imageUrl: song.artwork,
                      size: 52,
                      radius: 8),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(song.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: SunohType.sans(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w500,
                                color: c.fg,
                                height: 1.2)),
                        if (artistsLabel.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(artistsLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: SunohType.sans(
                                  fontSize: 12, color: c.fgMute)),
                        ],
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
            // Actions.
            _MenuRow(
              icon: liked ? SolarIconsBold.heart : SolarIconsOutline.heart,
              iconColor: liked ? accent : c.fg,
              label: liked ? 'Remove from Liked' : 'Add to Liked',
              onTap: () {
                Navigator.of(context).pop();
                s.toggleLikedSong(song);
              },
            ),
            _MenuRow(
              icon: SolarIconsOutline.playlistMinimalistic,
              label: 'Play next',
              onTap: () {
                Navigator.of(context).pop();
                s.playApiSongNext(song);
              },
              colors: c,
            ),
            _MenuRow(
              icon: SolarIconsOutline.addCircle,
              label: 'Add to queue',
              onTap: () {
                Navigator.of(context).pop();
                s.addApiSongToQueue(song);
              },
              colors: c,
            ),
            if (hasArtist)
              _MenuRow(
                icon: SolarIconsOutline.user,
                label: 'View ${song.artists!.first.name}',
                onTap: () {
                  Navigator.of(context).pop();
                  final artist = song.artists!.first;
                  if (artist.id.isEmpty) {
                    s.flashToast('Artist details unavailable');
                    return;
                  }
                  context.openRef(DetailRef('artist', artist.id,
                      source: song.source));
                },
                colors: c,
              ),
            _MenuRow(
              icon: SolarIconsOutline.share,
              label: 'Share',
              onTap: () {
                Navigator.of(context).pop();
                s.flashToast('Share coming soon');
              },
              colors: c,
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
    this.colors,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;
  final SunohColors? colors;

  @override
  Widget build(BuildContext context) {
    // Late-binding the color tokens lets _MenuRow take only an iconColor
    // (for the like-state highlight) without callers having to repeat the
    // whole tokens object for every row.
    final c = colors ??
        const SunohColors(
          bg: Color(0xFF15151A),
          bgSoft: Color(0xFF15151A),
          surface: Color(0x00000000),
          surface2: Color(0x00000000),
          line: Color(0xFF2A2A30),
          fg: Color(0xFFFAFAFA),
          fgDim: Color(0xB3FAFAFA),
          fgMute: Color(0x73FAFAFA),
          accent: Color(0xFFD97757),
        );
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: iconColor ?? c.fg),
            const SizedBox(width: 16),
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SunohType.sans(fontSize: 14, color: c.fg)),
            ),
          ],
        ),
      ),
    );
  }
}
