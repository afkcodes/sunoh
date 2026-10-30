// User-created playlist detail screen.
//
// Laid out as an album page (hero, actions, numbered tracks), like Liked
// Songs. Differences:
//   - the actions row's menu offers Rename / Delete
//   - rows reorder by their drag handle, and their menu surfaces "Remove
//     from this playlist"
//   - cover is the first song's artwork when available, else a made accent
//     square with a playlist glyph

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:remixicon/remixicon.dart';

import '../data/user_playlist.dart';
import '../overlays/confirm_sheet.dart';
import '../overlays/playlist_name_sheet.dart';
import '../overlays/sheet.dart';
import '../overlays/sheet_row.dart';
import '../providers/app_state_provider.dart';
import '../theme/tokens.dart';
import '../widgets/motion.dart';
import '../widgets/ui.dart';
import 'detail_chrome.dart';
import 'detail_hero.dart';
import 'detail_track_row.dart';

class UserPlaylistScreen extends ConsumerStatefulWidget {
  const UserPlaylistScreen({super.key, required this.id});
  final String id;
  @override
  ConsumerState<UserPlaylistScreen> createState() => _UserPlaylistScreenState();
}

class _UserPlaylistScreenState extends ConsumerState<UserPlaylistScreen> {
  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final accent = c.accent;
    final playlist = s.userPlaylistById(widget.id);

    if (playlist == null) {
      // Likely the user deleted this playlist from elsewhere and came
      // back here through a stale router stack. Pop back so they don't
      // see an empty shell.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && context.mounted) context.pop();
      });
      return ColoredBox(color: c.bg, child: const SizedBox.expand());
    }

    final songs = playlist.songs;
    final labels = TrackLabels.of(songs);
    final sourceLabel = 'PLAYLIST · ${playlist.name}';
    final coverUrl = _firstArtwork(playlist);
    // The queue is this playlist when it was started from here: no detail
    // ref, and this screen's label.
    final here = s.apiSourceRef == null && s.apiSourceLabel == sourceLabel;

    return DetailPage(
      colors: c,
      colour: accent,
      title: playlist.name,
      builder: (scroll) => [
        SliverToBoxAdapter(
          child: DetailHero(
            colors: c,
            colour: accent,
            scroll: scroll,
            cover: DetailCover(
              id: playlist.id,
              imageUrl: coverUrl,
              child: coverUrl == null ? _GlyphCover(colors: c) : null,
            ),
            title: playlist.name,
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
                IconBtn(
                  icon: RemixIcons.more_fill,
                  color: c.fg,
                  onTap: () => _showOverflowMenu(context, ref, playlist),
                ),
              ],
              onShuffle: songs.isEmpty
                  ? null
                  : () => s.playShuffled(songs, sourceLabel: sourceLabel),
              onPlay: songs.isEmpty
                  ? null
                  : () => here ? s.playPause() : s.playUserPlaylist(playlist),
            ),
          ),
        ),
        if (songs.isEmpty)
          SliverToBoxAdapter(child: _EmptyPlaylist(colors: c))
        else
          SliverPadding(
            padding: const EdgeInsets.only(top: 8),
            // Reorders in place, lazily, inside the page's own scroll. The
            // drag is bound to the handle at the row's start (not a long
            // press on the whole row) so a tap still plays cleanly; the new
            // order is persisted by `moveSongInUserPlaylist`.
            sliver: SliverReorderableList(
              itemCount: songs.length,
              onReorderItem: (from, to) =>
                  s.moveSongInUserPlaylist(playlist.id, from, to),
              proxyDecorator: (child, _, _) =>
                  _LiftedRow(colors: c, child: child),
              itemBuilder: (context, i) => DetailTrackRow(
                key: ValueKey('${songs[i].id}:$i'),
                n: i + 1,
                song: songs[i],
                subtitle: labels.subtitles[i],
                duration: labels.durations[i],
                colors: c,
                accent: accent,
                showArt: true,
                showLike: false,
                sourceLabel: sourceLabel,
                removeFromUserPlaylistId: playlist.id,
                handle: ReorderableDragStartListener(
                  index: i,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Icon(
                      RemixIcons.draggable,
                      size: 16,
                      color: c.fgMute,
                    ),
                  ),
                ),
                onTap: () => s.playApiQueue(songs, i, sourceLabel: sourceLabel),
              ),
            ),
          ),
      ],
    );
  }

  static String? _firstArtwork(UserPlaylist p) {
    for (final s in p.songs) {
      final a = s.artwork;
      if (a != null && a.isNotEmpty) return a;
    }
    return null;
  }

  Future<void> _showOverflowMenu(
    BuildContext context,
    WidgetRef ref,
    UserPlaylist p,
  ) async {
    final action = await showSunohSheet<String>(
      context,
      builder: (_) => _OverflowSheet(name: p.name),
    );
    if (action == 'rename') {
      if (!context.mounted) return;
      final next = await promptForPlaylistName(context, initial: p.name);
      if (next != null && next.isNotEmpty) {
        await ref.read(appStateProvider).renameUserPlaylist(p.id, next);
      }
    } else if (action == 'delete') {
      if (!context.mounted) return;
      final confirmed = await showConfirmSheet(
        context,
        title: 'Delete “${p.name}”?',
        message:
            'The playlist is removed from your library. Songs stay where '
            'they are.',
        confirmLabel: 'Delete',
      );
      if (confirmed && context.mounted) {
        await ref.read(appStateProvider).deleteUserPlaylist(p.id);
        if (context.mounted) context.pop();
      }
    }
  }
}

/// Bottom sheet with two rows: Rename + Delete. Pops with `'rename'` /
/// `'delete'` / null.
class _OverflowSheet extends ConsumerWidget {
  const _OverflowSheet({required this.name});
  final String name;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(appStateProvider).colors;
    // The shared sheet shell rather than a hand-built one: this used to paint
    // a hardcoded dark fill that stayed dark on the light palette.
    return SunohSheet(
      title: name,
      child: Column(
        children: [
          SheetRow(
            icon: RemixIcons.pencil_line,
            label: 'Rename',
            colors: c,
            onTap: () => Navigator.of(context).pop('rename'),
          ),
          SheetRow(
            icon: RemixIcons.delete_bin_line,
            iconColor: c.danger,
            label: 'Delete',
            colors: c,
            onTap: () => Navigator.of(context).pop('delete'),
          ),
        ],
      ),
    );
  }
}

/// The cover for a playlist none of whose songs has art: the playlist glyph
/// on the same accent gradient as Liked Songs.
class _GlyphCover extends StatelessWidget {
  const _GlyphCover({required this.colors});
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
      child: Icon(RemixIcons.album_fill, size: 88, color: colors.onAccent),
    );
  }
}

/// The row being dragged, lifted onto a card so it reads crisply over the
/// rows it passes. Inside its own transparent Material because the drag
/// proxy lives in the overlay, outside the page's text and ink ancestors.
class _LiftedRow extends StatelessWidget {
  const _LiftedRow({required this.colors, required this.child});
  final SunohColors colors;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: DecoratedBox(
        decoration: squircleDecoration(
          radius: SunohRadius.card,
          color: colors.bgSoft,
        ),
        child: child,
      ),
    );
  }
}

class _EmptyPlaylist extends StatelessWidget {
  const _EmptyPlaylist({required this.colors});
  final SunohColors colors;
  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 40, 16, 40),
      child: Column(
        children: [
          Text(
            'No songs yet',
            style: SunohType.heading(fontSize: 18, color: c.fgDim),
          ),
          const SizedBox(height: 8),
          Text(
            'Open any song\'s menu and pick "Add to playlist" to drop it here.',
            textAlign: TextAlign.center,
            style: SunohType.sans(fontSize: 13, color: c.fgMute),
          ),
        ],
      ),
    );
  }
}
