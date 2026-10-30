// The lists the device-library tabs render: songs, collections, the empty
// state, and the search field.
//
// Split from local_library_screen.dart, which was carrying the screen's
// scaffold and all of its content in one file. The screen decides what to
// show; these know how to draw it.

part of 'local_library_screen.dart';

class _SongList extends StatelessWidget {
  const _SongList({
    required this.songs,
    required this.state,
    required this.colors,
  });
  final List<FeedItem> songs;
  final AppState state;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    final playingId = state.currentApiSong?.id;
    // Lazy: a device library runs to thousands of tracks, and an eager Column
    // would build and lay out every one of them.
    return ListView.builder(
      padding: EdgeInsets.only(top: 4, bottom: shellClearance(context)),
      itemCount: songs.length,
      itemBuilder: (context, i) => LocalTrackRow(
        song: songs[i],
        colors: colors,
        playing: songs[i].id == playingId,
        animate: state.isPlaying,
        onTap: () =>
            state.playApiQueue(songs, i, sourceLabel: 'ON THIS DEVICE'),
      ),
    );
  }
}

class _CollectionList extends StatelessWidget {
  const _CollectionList({
    required this.collections,
    required this.album,
    required this.colors,
  });
  final List<LocalCollection> collections;
  final bool album;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: EdgeInsets.only(top: 4, bottom: shellClearance(context)),
      itemCount: collections.length,
      itemBuilder: (context, i) {
        final col = collections[i];
        return Pressable(
          scale: 0.99,
          onTap: () => context.openLocalCollection(col.id, album: album),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                SunohArt(
                  id: col.id,
                  size: 48,
                  // Artists read as circles throughout the app; albums square.
                  radius: album ? SunohRadius.row : 999,
                  imageUrl: col.artwork,
                  shadow: false,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        col.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SunohType.sans(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: colors.fg,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        col.subtitle ?? '${col.songs.length} songs',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SunohType.sans(
                          fontSize: 13,
                          color: colors.fgDim,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The ways this screen can be empty, each with the action that fixes it.
/// Set as the prototype's zero state: a heading, a paragraph, and the fix as
/// an option row rather than a lone button floating in the middle.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.library, required this.colors});
  final LocalLibrary library;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final (title, body, action, onTap) = switch (library.status) {
      LocalLibraryStatus.denied => (
        'Access needed',
        'sunoh needs permission to read audio files on this device.',
        'Grant access',
        () => library.load(force: true),
      ),
      LocalLibraryStatus.permanentlyDenied => (
        'Access blocked',
        'Audio access was turned off for sunoh. Enable it in system '
            'settings to see music stored on this device.',
        'Open settings',
        library.openSettings,
      ),
      LocalLibraryStatus.scanning => (
        'Scanning…',
        'Reading music stored on this device.',
        null,
        null,
      ),
      _ => (
        'No music on this device',
        'Copy some audio files onto the phone and they will show up here.',
        'Scan again',
        () => library.load(force: true),
      ),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: SunohType.heading(fontSize: 22, color: c.fg)),
          const SizedBox(height: 8),
          Text(
            body,
            style: SunohType.sans(fontSize: 14, color: c.fgDim, height: 1.45),
          ),
          if (action != null && onTap != null) ...[
            const SizedBox(height: 16),
            Pressable(
              onTap: onTap,
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: squircleDecoration(
                  radius: SunohRadius.card,
                  color: c.surface,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        action,
                        style: SunohType.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: c.fg,
                        ),
                      ),
                    ),
                    Icon(
                      RemixIcons.arrow_right_s_line,
                      size: 16,
                      color: c.fgMute,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Search across the whole device library, replacing the tabs while open.
/// The Search tab's inverted field — ink fill, page-coloured text — so a
/// search box looks like one wherever it appears.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.colors,
    required this.onChanged,
  });

  final TextEditingController controller;
  final SunohColors colors;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Container(
      height: 46,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      padding: const EdgeInsets.only(left: 12, right: 14),
      decoration: squircleDecoration(radius: SunohRadius.card, color: c.fg),
      child: Row(
        children: [
          Icon(RemixIcons.search_line, size: 20, color: c.bg),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: true,
              onChanged: onChanged,
              cursorColor: c.bg,
              style: SunohType.sans(fontSize: 15.5, color: c.bg),
              decoration: InputDecoration(
                hintText: 'Search this device',
                hintStyle: SunohType.sans(
                  fontSize: 15.5,
                  color: c.bg.withValues(alpha: 0.55),
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
