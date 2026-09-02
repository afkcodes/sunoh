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
    // Lazy: a device library runs to thousands of tracks, and an eager Column
    // would build and lay out every one of them.
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 140),
      itemCount: songs.length,
      itemBuilder: (context, i) => LocalTrackRow(
        song: songs[i],
        colors: colors,
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
      padding: const EdgeInsets.only(top: 8, bottom: 140),
      itemCount: collections.length,
      itemBuilder: (context, i) {
        final col = collections[i];
        return GestureDetector(
          onTap: () => context.openLocalCollection(col.id, album: album),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
            child: Row(
              children: [
                SunohArt(
                  id: col.id,
                  size: 48,
                  // Artists read as circles throughout the app; albums square.
                  radius: album ? 8 : 999,
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
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: colors.fg,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        col.subtitle ?? '${col.songs.length} songs',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SunohType.sans(
                          fontSize: 12,
                          color: colors.fgMute,
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
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.library, required this.colors});
  final LocalLibrary library;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
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
      padding: const EdgeInsets.fromLTRB(32, 80, 32, 40),
      child: Column(
        children: [
          Icon(SolarIconsOutline.smartphone, size: 34, color: colors.fgMute),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: SunohType.heading(fontSize: 18, color: colors.fg),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: SunohType.sans(
              fontSize: 13,
              color: colors.fgMute,
              height: 1.5,
            ),
          ),
          if (action != null && onTap != null) ...[
            const SizedBox(height: 20),
            GestureDetector(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                decoration: squircleDecoration(
                  radius: 999,
                  color: colors.accent,
                ),
                child: Text(
                  action,
                  style: SunohType.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.onAccent,
                  ),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        decoration: squircleDecoration(
          radius: 999,
          color: c.surface,
          borderColor: c.line,
        ),
        child: Row(
          children: [
            Icon(SolarIconsOutline.magnifier, size: 16, color: c.fgMute),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                autofocus: true,
                onChanged: onChanged,
                style: SunohType.sans(fontSize: 14, color: c.fg),
                decoration: InputDecoration(
                  hintText: 'Search this device',
                  hintStyle: SunohType.sans(fontSize: 14, color: c.fgMute),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
