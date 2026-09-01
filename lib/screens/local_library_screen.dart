// On-device music — Songs / Albums / Artists.
//
// Tabs use the app's shared `SunohTabs`, and the three lists sit in a PageView
// so they swipe as well as tap. The tab strip and the pager drive each other:
// a tap animates the page, a swipe settles the strip.
//
// The device library is the one source that can be empty for reasons the user
// has to act on, so the empty states carry most of the weight here: a refused
// permission needs a prompt, a permanently refused one needs Settings, and a
// device with no music needs neither. Showing "nothing here" for all three
// would leave the user with no way forward.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';

import '../api/dto.dart';
import '../api/local_media_channel.dart';
import '../audio/local_library.dart';
import '../providers/app_state_provider.dart';
import '../providers/local_library_provider.dart';
import '../router/router.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/top_tabs.dart';
import '../widgets/ui.dart';
import 'local_track_row.dart';

const List<String> _kTabs = ['Songs', 'Albums', 'Artists'];

class LocalLibraryScreen extends ConsumerStatefulWidget {
  const LocalLibraryScreen({super.key});
  @override
  ConsumerState<LocalLibraryScreen> createState() => _LocalLibraryScreenState();
}

class _LocalLibraryScreenState extends ConsumerState<LocalLibraryScreen> {
  final PageController _pages = PageController();
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // Re-scan on entry so files added since the last visit appear. `load`
    // reuses a completed scan, so this is free after the first time — and it
    // is the point at which asking for permission is something the user has
    // actually asked for.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(localLibraryProvider).load();
    });
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _select(int i) {
    if (i == _index) return;
    setState(() => _index = i);
    _pages.animateToPage(
      i,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final lib = ref.watch(localLibraryProvider);

    return ColoredBox(
      color: c.bg,
      child: Column(
        children: [
          _Header(library: lib, colors: c),
          if (lib.hasMusic)
            SunohTabs(
              tabs: _kTabs,
              active: _kTabs[_index],
              colors: c,
              onChange: (t) => _select(_kTabs.indexOf(t)),
            ),
          Expanded(
            child: !lib.hasMusic
                ? SingleChildScrollView(
                    child: _EmptyState(library: lib, colors: c),
                  )
                : PageView(
                    controller: _pages,
                    onPageChanged: (i) => setState(() => _index = i),
                    children: [
                      _SongList(songs: lib.songs, state: s, colors: c),
                      _CollectionList(
                        collections: lib.albums,
                        album: true,
                        colors: c,
                      ),
                      _CollectionList(
                        collections: lib.artists,
                        album: false,
                        colors: c,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.library, required this.colors});
  final LocalLibrary library;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.of(context).padding.top + 20,
        20,
        6,
      ),
      child: Row(
        children: [
          IconBtn(
            icon: SolarIconsOutline.altArrowLeft,
            color: c.fgDim,
            size: 18,
            onTap: () => context.pop(),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              'On this device',
              style: SunohType.heading(
                fontSize: 24,
                color: c.fg,
                letterSpacing: -0.4,
              ),
            ),
          ),
          if (library.isScanning)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: c.fgMute),
            )
          else
            IconBtn(
              icon: SolarIconsOutline.refresh,
              color: c.fgDim,
              size: 18,
              onTap: () => library.load(force: true),
            ),
        ],
      ),
    );
  }
}

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
