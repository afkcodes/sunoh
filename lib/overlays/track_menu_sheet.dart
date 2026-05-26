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
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';

import '../api/dto.dart';
import '../data/models.dart';
import '../providers/app_state_provider.dart';
import '../share/share_link.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/ui.dart';

/// Open the bottom sheet for [song]. [sourceLabel] is the "PLAYING FROM"
/// label that gets passed to play-next / add-to-queue so the engine knows
/// where the user kicked the queue from. [sourceRef] is the optional
/// album/playlist/artist the song came from — surfaces a "View Album"/
/// "View Playlist"/"View Artist" navigation row when provided.
Future<void> showTrackMenuSheet(
  BuildContext context, {
  required FeedItem song,
  String? sourceLabel,
  DetailRef? sourceRef,
  bool fromPlayer = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    // Root navigator — without this the sheet is anchored to the active
    // tab's branch navigator (inside StatefulShellRoute), which is BELOW
    // the bottom nav + mini player in the widget tree, so the sheet renders
    // behind them. Using the root navigator promotes it above everything.
    useRootNavigator: true,
    builder: (_) => _TrackMenuSheet(
        song: song,
        sourceLabel: sourceLabel,
        sourceRef: sourceRef,
        fromPlayer: fromPlayer),
  );
}

class _TrackMenuSheet extends ConsumerWidget {
  const _TrackMenuSheet({
    required this.song,
    this.sourceLabel,
    this.sourceRef,
    this.fromPlayer = false,
  });
  final FeedItem song;
  final String? sourceLabel;
  final DetailRef? sourceRef;
  /// True when the sheet was opened from the expanded player. Navigation
  /// rows then also pop the player itself off the root navigator so the
  /// destination screen isn't hidden behind it.
  final bool fromPlayer;

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
            if (sourceRef != null && sourceRef!.kind != 'artist')
              _MenuRow(
                icon: sourceRef!.kind == 'album'
                    ? SolarIconsOutline.musicLibrary2
                    : SolarIconsOutline.playlistMinimalistic,
                label:
                    'Go to ${sourceRef!.kind[0].toUpperCase()}${sourceRef!.kind.substring(1)}',
                onTap: () => _navigateAfterClose(context, sourceRef!),
                colors: c,
              ),
            if (hasArtist)
              _MenuRow(
                icon: SolarIconsOutline.user,
                label: 'View ${song.artists!.first.name}',
                onTap: () {
                  final artist = song.artists!.first;
                  if (artist.id.isEmpty) {
                    Navigator.of(context).pop();
                    s.flashToast('Artist details unavailable');
                    return;
                  }
                  _navigateAfterClose(
                    context,
                    DetailRef('artist', artist.id, source: song.source),
                  );
                },
                colors: c,
              ),
            _MenuRow(
              icon: SolarIconsOutline.share,
              label: 'Share',
              onTap: () {
                Navigator.of(context).pop();
                shareSunohLink(
                  kind: 'song',
                  id: song.id,
                  title: song.title,
                  subtitle: song.displaySubtitle ?? song.subtitle,
                  source: song.source,
                );
              },
              colors: c,
            ),
          ],
        ),
      ),
    );
  }

  /// Close the sheet, optionally pop the expanded player off the root
  /// navigator (so the destination detail screen isn't hidden behind it),
  /// then navigate. Capture references up front because each pop may
  /// invalidate the sheet's context.
  void _navigateAfterClose(BuildContext context, DetailRef ref) {
    final root = Navigator.of(context, rootNavigator: true);
    // Captured BEFORE we pop the sheet (and possibly the player) so we
    // don't lose the route context.
    final goRouter = GoRouter.of(context);
    root.pop(); // sheet
    if (fromPlayer && root.canPop()) {
      root.pop(); // player
    }
    // Recompute branch prefix from current location now that modals are gone.
    final loc = goRouter.state.matchedLocation;
    final prefix = loc.startsWith('/search')
        ? '/search'
        : loc.startsWith('/library')
            ? '/library'
            : '/home';
    final src = ref.source;
    final query = (src == null || src.isEmpty)
        ? ''
        : '?source=${Uri.encodeQueryComponent(src)}';
    goRouter.push('$prefix/${ref.kind}/${ref.id}$query');
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
