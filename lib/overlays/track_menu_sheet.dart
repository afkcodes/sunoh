// Track context-menu bottom sheet. The ⋯ button on every track row (album,
// playlist, search, library, etc.) routes here.
//
// Header is the song's artwork + title + artist (SheetSubject). Below it: a
// vertical list of actions — like, play next, add to queue, add to playlist,
// download, go to source, view artist, share — as the shared SheetRow.
//
// Reusable: callers pass the song (+ optional source label for play-next /
// add-to-queue) and we wire everything off `AppState`. Each action closes
// the sheet via `Navigator.of(ctx).pop()` before performing its side-effect
// so the user sees the sheet dismiss instantly rather than waiting on Hive
// or the audio engine.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:remixicon/remixicon.dart';

import '../api/dto.dart';
import '../data/models.dart';
import '../providers/app_state_provider.dart';
import '../providers/ytmusic_provider.dart';
import '../share/share_link.dart';
import 'add_to_playlist_sheet.dart';
import 'sheet.dart';
import 'sheet_row.dart';
import 'track_download_row.dart';

/// Open the bottom sheet for [song]. [sourceLabel] is the "PLAYING FROM"
/// label that gets passed to play-next / add-to-queue so the engine knows
/// where the user kicked the queue from. [sourceRef] is the optional
/// album/playlist/artist the song came from — surfaces a "View Album"/
/// "View Playlist"/"View Artist" navigation row when provided.
///
/// Through [showSunohSheet], which puts it on the root navigator — anchored
/// to the active tab's branch navigator instead, the sheet rendered behind
/// the bottom nav and mini player.
Future<void> showTrackMenuSheet(
  BuildContext context, {
  required FeedItem song,
  String? sourceLabel,
  DetailRef? sourceRef,
  bool fromPlayer = false,
  String? removeFromUserPlaylistId,
}) {
  return showSunohSheet<void>(
    context,
    builder: (_) => _TrackMenuSheet(
      song: song,
      sourceLabel: sourceLabel,
      sourceRef: sourceRef,
      fromPlayer: fromPlayer,
      removeFromUserPlaylistId: removeFromUserPlaylistId,
    ),
  );
}

/// The tab a detail route should be pushed under, read from where the router
/// is now. Read after the sheet (and maybe the player) has popped, so it
/// reflects the page underneath rather than the modal.
String _branchPrefix(GoRouter router) {
  final loc = router.state.matchedLocation;
  if (loc.startsWith('/search')) return '/search';
  if (loc.startsWith('/library')) return '/library';
  return '/home';
}

/// Find a YouTube artist page by name and open it.
///
/// The byline on a song row usually links the artist channel directly, but
/// auto-generated "- Topic" uploads sometimes carry a plain text artist,
/// and queue entries persisted before ids were captured have none either.
/// Searching by name is a reliable fallback and keeps "View artist" from
/// dead-ending.
///
/// The router and branch prefix are captured BEFORE the sheet is popped
/// and before the `await` — a context is not safe to use across either.
Future<void> _openYtArtistByName(
  BuildContext context,
  WidgetRef ref,
  String name, {
  required bool fromPlayer,
}) async {
  final state = ref.read(appStateProvider);
  if (name.trim().isEmpty) {
    Navigator.of(context, rootNavigator: true).pop();
    state.flashToast('Artist details unavailable');
    return;
  }

  final root = Navigator.of(context, rootNavigator: true);
  final goRouter = GoRouter.of(context);
  final api = ref.read(ytMusicApiProvider);
  root.pop(); // sheet
  if (fromPlayer && root.canPop()) {
    root.pop(); // player
  }
  final prefix = _branchPrefix(goRouter);

  state.flashToast('Finding $name…');
  final results = await api.searchArtists(name);
  if (results.isEmpty) {
    state.flashToast('Couldn’t find $name');
    return;
  }
  goRouter.push(
    '$prefix/yt-artist/${Uri.encodeComponent(results.first.id)}',
    extra: results.first.title,
  );
}

class _TrackMenuSheet extends ConsumerWidget {
  const _TrackMenuSheet({
    required this.song,
    this.sourceLabel,
    this.sourceRef,
    this.fromPlayer = false,
    this.removeFromUserPlaylistId,
  });
  final FeedItem song;
  final String? sourceLabel;
  final DetailRef? sourceRef;

  /// True when the sheet was opened from the expanded player. Navigation
  /// rows then also pop the player itself off the root navigator so the
  /// destination screen isn't hidden behind it.
  final bool fromPlayer;

  /// When set, the sheet shows a "Remove from this playlist" row that
  /// removes [song] from the user-created playlist with the given id.
  /// Only used by UserPlaylistScreen.
  final String? removeFromUserPlaylistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final liked = s.isLikedId(song.id);
    final artistsLabel = (song.artists ?? const <ApiArtistRef>[])
        .map((a) => a.name.trim())
        .where((sa) => sa.isNotEmpty)
        .take(2)
        .join(', ');
    final hasArtist = (song.artists ?? const []).isNotEmpty;
    final src = sourceRef;

    // Close first, then act — see the file header.
    VoidCallback closeThen(VoidCallback action) => () {
      Navigator.of(context).pop();
      action();
    };

    return SunohSheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SheetSubject(
            id: song.id,
            imageUrl: song.artwork,
            title: song.title,
            subtitle: artistsLabel,
            colors: c,
          ),
          SheetRow(
            icon: liked ? RemixIcons.heart_3_fill : RemixIcons.heart_3_line,
            iconColor: liked ? c.accent : null,
            label: liked ? 'Remove from Liked' : 'Add to Liked',
            onTap: closeThen(() => s.toggleLikedSong(song)),
            colors: c,
          ),
          SheetRow(
            icon: RemixIcons.play_list_add_line,
            label: 'Play next',
            onTap: closeThen(() => s.playApiSongNext(song)),
            colors: c,
          ),
          SheetRow(
            icon: RemixIcons.add_circle_line,
            label: 'Add to queue',
            onTap: closeThen(() => s.addApiSongToQueue(song)),
            colors: c,
          ),
          SheetRow(
            icon: RemixIcons.play_list_2_line,
            label: 'Add to playlist',
            onTap: () async {
              Navigator.of(context).pop();
              await showAddToPlaylistSheet(context, song: song);
            },
            colors: c,
          ),
          if (removeFromUserPlaylistId != null)
            SheetRow(
              icon: RemixIcons.indeterminate_circle_line,
              label: 'Remove from this playlist',
              onTap: closeThen(
                () => s.removeSongFromUserPlaylist(
                  removeFromUserPlaylistId!,
                  song.id,
                ),
              ),
              colors: c,
            ),
          // Download / Downloaded / Remove download.
          //
          // Gaana used to be excluded here because it ships HLS playlists
          // rather than a file. It is downloadable now — the segments are
          // concatenated into one MPEG-TS, see audio/hls_download.dart.
          TrackDownloadRow(song: song, colors: c),
          if (src != null && src.kind != 'artist')
            SheetRow(
              icon: src.kind == 'album'
                  ? RemixIcons.album_line
                  : RemixIcons.play_list_add_line,
              label:
                  'Go to ${src.kind[0].toUpperCase()}${src.kind.substring(1)}',
              onTap: () => _navigateAfterClose(context, src),
              colors: c,
            ),
          if (hasArtist)
            SheetRow(
              icon: RemixIcons.user_3_line,
              label: 'View ${song.artists!.first.name}',
              onTap: () => _viewArtist(context, ref),
              colors: c,
            ),
          SheetRow(
            icon: RemixIcons.share_forward_line,
            label: 'Share',
            onTap: closeThen(
              () => shareSunohLink(
                kind: 'song',
                id: song.id,
                title: song.title,
                subtitle: song.displaySubtitle ?? song.subtitle,
                source: song.source,
              ),
            ),
            colors: c,
          ),
        ],
      ),
    );
  }

  void _viewArtist(BuildContext context, WidgetRef ref) {
    final artist = song.artists!.first;
    debugPrint(
      '[artist-nav] source=${song.source} '
      'name="${artist.name}" id="${artist.id}"',
    );
    // YouTube artist ids are channel browse ids, which sunoh-api's artist
    // endpoint can't resolve — they need the YouTube artist screen.
    if (song.source == 'youtube') {
      if (artist.id.isNotEmpty) {
        _navigateToYtArtistAfterClose(context, artist.id, artist.name);
      } else {
        // No linked channel on this row. Happens for auto-generated art
        // tracks whose byline isn't navigable, and for queue entries
        // persisted before artist ids were captured. Resolve by name instead
        // of dead-ending on a toast.
        _openYtArtistByName(context, ref, artist.name, fromPlayer: fromPlayer);
      }
      return;
    }
    if (artist.id.isEmpty) {
      Navigator.of(context).pop();
      ref.read(appStateProvider).flashToast('Artist details unavailable');
      return;
    }
    _navigateAfterClose(
      context,
      DetailRef('artist', artist.id, source: song.source),
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
    final prefix = _branchPrefix(goRouter);
    final src = ref.source;
    final query = (src == null || src.isEmpty)
        ? ''
        : '?source=${Uri.encodeQueryComponent(src)}';
    goRouter.push('$prefix/${ref.kind}/${ref.id}$query');
  }

  /// Same close-then-navigate dance as [_navigateAfterClose], but for the
  /// YouTube artist route.
  ///
  /// The context must NOT be used after the pop — that's why the router is
  /// captured first. Popping the sheet and then calling a `context.push`
  /// extension navigates from a dead route and silently does nothing,
  /// which is exactly how this row appeared to "close and stay put".
  void _navigateToYtArtistAfterClose(
    BuildContext context,
    String browseId,
    String name,
  ) {
    final root = Navigator.of(context, rootNavigator: true);
    final goRouter = GoRouter.of(context);
    root.pop(); // sheet
    if (fromPlayer && root.canPop()) {
      root.pop(); // player
    }
    final prefix = _branchPrefix(goRouter);
    goRouter.push(
      '$prefix/yt-artist/${Uri.encodeComponent(browseId)}',
      extra: name,
    );
  }
}
