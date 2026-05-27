// User-created playlist detail screen.
//
// Modelled on `LikedSongsScreen` so it inherits the same hero + sticky
// header rhythm + play/shuffle action bar. Differences:
//   - title is editable via a rename dialog
//   - overflow menu offers Rename / Delete
//   - per-row menu surfaces "Remove from this playlist"
//   - cover is the first song's artwork when available, else a synthetic
//     accent gradient with a playlist glyph

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:solar_icons/solar_icons.dart';

import '../api/dto.dart';
import '../data/user_playlist.dart';
import '../overlays/track_menu_sheet.dart';
import '../providers/app_state_provider.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';

class UserPlaylistScreen extends ConsumerStatefulWidget {
  const UserPlaylistScreen({super.key, required this.id});
  final String id;
  @override
  ConsumerState<UserPlaylistScreen> createState() =>
      _UserPlaylistScreenState();
}

class _UserPlaylistScreenState extends ConsumerState<UserPlaylistScreen> {
  final _scroll = ScrollController();
  final ValueNotifier<double> _offset = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() => _offset.value = _scroll.offset);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _offset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final accent = s.resolvedAccent;
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
    final sourceLabel = 'PLAYLIST · ${playlist.name}';

    return ColoredBox(
      color: c.bg,
      child: SizedBox.expand(
        child: Stack(
          children: [
            Positioned.fill(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.only(bottom: 140),
                children: [
                  _PlaylistHero(
                    colors: c,
                    accent: accent,
                    playlist: playlist,
                    scrollOffset: _offset,
                  ),
                  _PlaylistActions(
                    colors: c,
                    accent: accent,
                    playlist: playlist,
                  ),
                  if (songs.isEmpty)
                    _EmptyPlaylist(colors: c)
                  else
                    // ReorderableListView embedded in the parent ListView:
                    // shrinkWrap so it sizes to its children, never-
                    // scrollable physics so the parent owns scrolling.
                    // Drag is bound to a hamburger handle inside each row
                    // (not a long-press on the whole row) so taps still
                    // play the song cleanly. Reorder is persisted via
                    // `moveSongInUserPlaylist`.
                    ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      buildDefaultDragHandles: false,
                      itemCount: songs.length,
                      onReorder: (from, to) =>
                          s.moveSongInUserPlaylist(playlist.id, from, to),
                      itemBuilder: (context, i) => _PlaylistTrackRow(
                        key: ValueKey('${songs[i].id}:$i'),
                        n: i + 1,
                        index: i,
                        song: songs[i],
                        colors: c,
                        accent: accent,
                        playlistId: playlist.id,
                        sourceLabel: sourceLabel,
                        onTap: () => s.playApiQueue(
                          songs,
                          i,
                          sourceLabel: sourceLabel,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _StickyHeader(
                colors: c,
                scrollOffset: _offset,
                title: playlist.name,
                onBack: () => context.pop(),
                onMenu: () => _showOverflowMenu(context, ref, playlist),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showOverflowMenu(
      BuildContext context, WidgetRef ref, UserPlaylist p) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useRootNavigator: true,
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
      final confirmed = await _confirmDelete(context, p.name);
      if (confirmed == true && context.mounted) {
        await ref.read(appStateProvider).deleteUserPlaylist(p.id);
        if (context.mounted) context.pop();
      }
    }
  }

  Future<bool?> _confirmDelete(BuildContext context, String name) {
    final c = ref.read(appStateProvider).colors;
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF15151A),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text('Delete “$name”?',
            style: SunohType.heading(fontSize: 17, color: c.fg)),
        content: Text(
            'The playlist is removed from your library. Songs stay where they are.',
            style: SunohType.sans(fontSize: 13, color: c.fgMute)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel',
                style: SunohType.sans(fontSize: 13.5, color: c.fgDim)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Delete',
                style: SunohType.sans(
                    fontSize: 13.5,
                    color: const Color(0xFFE05656),
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
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
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 6, 22, 10),
              child: Text(name,
                  style: SunohType.heading(
                      fontSize: 16, color: c.fg, letterSpacing: -0.2)),
            ),
            Container(
                height: 0.5,
                color: c.line,
                margin: const EdgeInsets.symmetric(horizontal: 12)),
            _SheetRow(
              icon: SolarIconsOutline.pen,
              label: 'Rename',
              colors: c,
              onTap: () => Navigator.of(context).pop('rename'),
            ),
            _SheetRow(
              icon: SolarIconsOutline.trashBinTrash,
              label: 'Delete',
              colors: c,
              destructive: true,
              onTap: () => Navigator.of(context).pop('delete'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetRow extends StatelessWidget {
  const _SheetRow({
    required this.icon,
    required this.label,
    required this.colors,
    required this.onTap,
    this.destructive = false,
  });
  final IconData icon;
  final String label;
  final SunohColors colors;
  final VoidCallback onTap;
  final bool destructive;
  @override
  Widget build(BuildContext context) {
    final c = colors;
    final tint =
        destructive ? const Color(0xFFE05656) : c.fg;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 18, color: tint),
            const SizedBox(width: 14),
            Text(label,
                style: SunohType.sans(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: tint)),
          ],
        ),
      ),
    );
  }
}

/// Hero with a synthetic accent gradient OR the first song's artwork
/// when present. Mirrors the LikedSongs hero scroll-fade.
class _PlaylistHero extends StatelessWidget {
  const _PlaylistHero({
    required this.colors,
    required this.accent,
    required this.playlist,
    required this.scrollOffset,
  });
  final SunohColors colors;
  final Color accent;
  final UserPlaylist playlist;
  final ValueListenable<double> scrollOffset;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final topInset = MediaQuery.of(context).padding.top;
    final coverUrl = _firstArtwork(playlist);
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  accent.withValues(alpha: 0.55),
                  accent.withValues(alpha: 0.18),
                  c.bg,
                ],
                stops: const [0, 0.55, 1],
              ),
            ),
          ),
        ),
        Column(
          children: [
            SizedBox(height: topInset + 52),
            ValueListenableBuilder<double>(
              valueListenable: scrollOffset,
              builder: (_, offset, child) {
                final progress = (offset / 320).clamp(0.0, 1.0);
                final scale = 1.0 - progress * 0.3;
                final opacity = (1.0 - progress).clamp(0.0, 1.0);
                return Opacity(
                  opacity: opacity,
                  child: Transform.scale(scale: scale, child: child),
                );
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
                child: Column(
                  children: [
                    Container(
                      width: 220,
                      height: 220,
                      decoration: squircleDecoration(
                        radius: 16,
                        gradient: coverUrl == null
                            ? LinearGradient(
                                colors: [
                                  accent,
                                  accent.withValues(alpha: 0.55),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: coverUrl == null
                          ? Icon(
                              SolarIconsBold.musicLibrary2,
                              size: 88,
                              color: Colors.white.withValues(alpha: 0.92),
                            )
                          : Image.network(
                              coverUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Icon(
                                  SolarIconsBold.musicLibrary2,
                                  size: 88,
                                  color: Colors.white
                                      .withValues(alpha: 0.92)),
                            ),
                    ),
                    const SizedBox(height: 20),
                    eyebrow('YOUR PLAYLIST', c.fgMute),
                    const SizedBox(height: 6),
                    Text(playlist.name,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: SunohType.heading(
                            fontSize: 26,
                            color: c.fg,
                            height: 1.1,
                            letterSpacing: -0.4)),
                    const SizedBox(height: 6),
                    Text(
                        '${playlist.songs.length} '
                        '${playlist.songs.length == 1 ? 'song' : 'songs'}',
                        style:
                            SunohType.sans(fontSize: 13, color: c.fgDim)),
                  ],
                ),
              ),
            ),
          ],
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
}

class _PlaylistActions extends ConsumerWidget {
  const _PlaylistActions({
    required this.colors,
    required this.accent,
    required this.playlist,
  });
  final SunohColors colors;
  final Color accent;
  final UserPlaylist playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    final s = ref.watch(appStateProvider);
    final songs = playlist.songs;
    final isEmpty = songs.isEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('${songs.length} ${songs.length == 1 ? 'song' : 'songs'}',
              style: SunohType.sans(fontSize: 12, color: c.fgMute)),
          Row(
            children: [
              GestureDetector(
                onTap: isEmpty
                    ? null
                    : () => s.playShuffled(playlist.songs,
                        sourceLabel: 'PLAYLIST · ${playlist.name}'),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: c.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.line, width: 0.5),
                  ),
                  child: Icon(PhosphorIconsBold.shuffle,
                      size: 18, color: isEmpty ? c.fgMute : c.fgDim),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: isEmpty ? null : () => s.playUserPlaylist(playlist),
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: isEmpty ? c.surface : accent,
                    shape: BoxShape.circle,
                    boxShadow: isEmpty
                        ? null
                        : [
                            BoxShadow(
                                color: accent.withValues(alpha: 0.33),
                                blurRadius: 22,
                                offset: const Offset(0, 6)),
                          ],
                  ),
                  child: Icon(PhosphorIconsFill.play,
                      size: 24,
                      color: isEmpty
                          ? c.fgMute
                          : (accent.computeLuminance() > 0.55
                              ? const Color(0xFF0B0B0D)
                              : const Color(0xFFFAFAFA))),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlaylistTrackRow extends ConsumerWidget {
  const _PlaylistTrackRow({
    super.key,
    required this.n,
    required this.index,
    required this.song,
    required this.colors,
    required this.accent,
    required this.playlistId,
    required this.sourceLabel,
    required this.onTap,
  });
  final int n;
  /// 0-based position in the playlist, used by the `ReorderableDragStart-
  /// Listener` wrapping the hamburger handle so drag-to-reorder operates
  /// on the correct slot.
  final int index;
  final FeedItem song;
  final SunohColors colors;
  final Color accent;
  final String playlistId;
  final String sourceLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    final s = ref.watch(appStateProvider);
    final artistsLabel = (song.artists ?? const <ApiArtistRef>[])
        .map((a) => a.name.trim())
        .where((sa) => sa.isNotEmpty)
        .take(2)
        .join(', ');
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        // Solid bg so the dragging chip the framework lifts shows
        // the row crisply (the default would be transparent and the
        // hero gradient behind would bleed through during the drag).
        color: c.bg,
        padding: EdgeInsets.symmetric(
            horizontal: 20, vertical: 10 * s.density.scale),
        child: Row(
          children: [
            // Drag-only hamburger — long-press to grab. Keeps the rest
            // of the row tappable for play.
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(SolarIconsOutline.hamburgerMenu,
                    size: 14, color: c.fgMute.withValues(alpha: 0.6)),
              ),
            ),
            SizedBox(
              width: 18,
              child: Center(
                child: Text(n.toString().padLeft(2, '0'),
                    style: SunohType.mono(fontSize: 11, color: c.fgMute)),
              ),
            ),
            const SizedBox(width: 10),
            squircleClip(
              radius: 6,
              child: SizedBox(
                width: 42,
                height: 42,
                child: ColoredBox(
                  color: const Color(0xFF1A1A1F),
                  child: song.artwork == null || song.artwork!.isEmpty
                      ? const Icon(SolarIconsBold.musicNotes,
                          size: 18, color: Colors.white24)
                      : Image.network(
                          song.artwork!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const Icon(
                              SolarIconsBold.musicNotes,
                              size: 18,
                              color: Colors.white24),
                        ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SunohType.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: c.fg)),
                  if (artistsLabel.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(artistsLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            SunohType.sans(fontSize: 11.5, color: c.fgMute)),
                  ],
                ],
              ),
            ),
            IconBtn(
                icon: SolarIconsBold.menuDots,
                color: colors.fgMute,
                size: 16,
                width: 32,
                height: 32,
                onTap: () => showTrackMenuSheet(
                    context,
                    song: song,
                    sourceLabel: sourceLabel,
                    removeFromUserPlaylistId: playlistId)),
          ],
        ),
      ),
    );
  }
}

class _StickyHeader extends StatelessWidget {
  const _StickyHeader({
    required this.colors,
    required this.scrollOffset,
    required this.title,
    required this.onBack,
    required this.onMenu,
  });
  final SunohColors colors;
  final ValueListenable<double> scrollOffset;
  final String title;
  final VoidCallback onBack;
  final VoidCallback onMenu;
  @override
  Widget build(BuildContext context) {
    final c = colors;
    final topInset = MediaQuery.of(context).padding.top;
    return SizedBox(
      height: topInset + 52,
      child: ValueListenableBuilder<double>(
        valueListenable: scrollOffset,
        builder: (_, offset, _) {
          final bgT = ((offset - 240) / 80).clamp(0.0, 1.0);
          final titleT = ((offset - 270) / 50).clamp(0.0, 1.0);
          return Stack(
            children: [
              IgnorePointer(
                child: Stack(
                  children: [
                    if (bgT > 0.02)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: c.bg.withValues(alpha: bgT),
                            border: bgT > 0.9
                                ? Border(
                                    bottom: BorderSide(
                                        color: c.line, width: 0.5))
                                : null,
                          ),
                        ),
                      ),
                    if (titleT > 0.01)
                      Positioned(
                        top: topInset,
                        left: 64,
                        right: 64,
                        bottom: 0,
                        child: Opacity(
                          opacity: titleT,
                          child: Center(
                            child: Text(title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: SunohType.heading(
                                    fontSize: 15,
                                    color: c.fg,
                                    letterSpacing: -0.2)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Positioned(
                top: topInset + 6,
                left: 16,
                right: 16,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconBtn(
                        icon: SolarIconsOutline.altArrowLeft,
                        color: c.fg,
                        size: 22,
                        background: Colors.black.withValues(alpha: 0.35),
                        onTap: onBack),
                    IconBtn(
                        icon: SolarIconsBold.menuDots,
                        color: c.fg,
                        size: 18,
                        background: Colors.black.withValues(alpha: 0.35),
                        onTap: onMenu),
                  ],
                ),
              ),
            ],
          );
        },
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
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 40),
      child: Center(
        child: Column(
          children: [
            Text('No songs yet',
                style: SunohType.heading(fontSize: 18, color: c.fgDim)),
            const SizedBox(height: 8),
            Text(
                'Open any song\'s menu and pick "Add to playlist" to drop it here.',
                textAlign: TextAlign.center,
                style: SunohType.sans(fontSize: 12.5, color: c.fgMute)),
          ],
        ),
      ),
    );
  }
}

/// Shared "Name the playlist" prompt — used by Create + Rename flows.
/// Returns the trimmed input or null when the user cancels.
Future<String?> promptForPlaylistName(BuildContext context,
    {String? initial}) {
  final controller = TextEditingController(text: initial ?? '');
  final c = ProviderScope.containerOf(context).read(appStateProvider).colors;
  final accent =
      ProviderScope.containerOf(context).read(appStateProvider).resolvedAccent;
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF15151A),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(initial == null ? 'New playlist' : 'Rename playlist',
          style: SunohType.heading(fontSize: 17, color: c.fg)),
      content: TextField(
        controller: controller,
        autofocus: true,
        cursorColor: accent,
        style: SunohType.sans(fontSize: 15, color: c.fg),
        decoration: InputDecoration(
          hintText: 'Playlist name',
          hintStyle: SunohType.sans(fontSize: 14, color: c.fgMute),
          enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: c.line, width: 0.5)),
          focusedBorder:
              UnderlineInputBorder(borderSide: BorderSide(color: accent)),
        ),
        textInputAction: TextInputAction.done,
        onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(null),
          child: Text('Cancel',
              style: SunohType.sans(fontSize: 13.5, color: c.fgDim)),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(ctx).pop(controller.text.trim()),
          child: Text(initial == null ? 'Create' : 'Save',
              style: SunohType.sans(
                  fontSize: 13.5,
                  color: accent,
                  fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
}
