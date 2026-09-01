// On-device music — Songs / Albums / Artists.
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
import '../widgets/ui.dart';
import 'local_track_row.dart';

enum _Tab { songs, albums, artists }

class LocalLibraryScreen extends ConsumerStatefulWidget {
  const LocalLibraryScreen({super.key});
  @override
  ConsumerState<LocalLibraryScreen> createState() => _LocalLibraryScreenState();
}

class _LocalLibraryScreenState extends ConsumerState<LocalLibraryScreen> {
  _Tab _tab = _Tab.songs;

  @override
  void initState() {
    super.initState();
    // Re-scan on entry so files added since the last visit appear. `load`
    // reuses a completed scan, so this is free after the first time.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(localLibraryProvider).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final lib = ref.watch(localLibraryProvider);

    return ColoredBox(
      color: c.bg,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                MediaQuery.of(context).padding.top + 20,
                20,
                16,
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
                  if (lib.isScanning)
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: c.fgMute,
                      ),
                    )
                  else
                    IconBtn(
                      icon: SolarIconsOutline.refresh,
                      color: c.fgDim,
                      size: 18,
                      onTap: () => lib.load(force: true),
                    ),
                ],
              ),
            ),
          ),
          if (lib.hasMusic)
            SliverToBoxAdapter(
              child: _Tabs(
                tab: _tab,
                colors: c,
                counts: {
                  _Tab.songs: lib.songs.length,
                  _Tab.albums: lib.albums.length,
                  _Tab.artists: lib.artists.length,
                },
                onChange: (t) => setState(() => _tab = t),
              ),
            ),
          if (!lib.hasMusic)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(library: lib, colors: c),
            )
          else if (_tab == _Tab.songs)
            _SongList(songs: lib.songs, state: s, colors: c)
          else
            _CollectionList(
              collections: _tab == _Tab.albums ? lib.albums : lib.artists,
              album: _tab == _Tab.albums,
              colors: c,
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 140)),
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
    // Lazy: a device library runs to thousands of tracks, and an eager
    // Column would build and lay out every one of them.
    return SliverList.builder(
      itemCount: songs.length,
      itemBuilder: (context, i) => LocalTrackRow(
        song: songs[i],
        colors: colors,
        onTap: () => state.playApiQueue(
          songs,
          i,
          sourceLabel: 'ON THIS DEVICE',
        ),
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
    return SliverList.builder(
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

class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.tab,
    required this.counts,
    required this.colors,
    required this.onChange,
  });
  final _Tab tab;
  final Map<_Tab, int> counts;
  final SunohColors colors;
  final ValueChanged<_Tab> onChange;

  static const _labels = {
    _Tab.songs: 'Songs',
    _Tab.albums: 'Albums',
    _Tab.artists: 'Artists',
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Row(
        children: [
          for (final t in _Tab.values) ...[
            GestureDetector(
              onTap: () => onChange(t),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(right: 18, top: 4, bottom: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_labels[t]}  ${counts[t] ?? 0}',
                      style: SunohType.sans(
                        fontSize: 13,
                        fontWeight: t == tab
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: t == tab ? colors.fg : colors.fgMute,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 2,
                      width: 18,
                      color: t == tab ? colors.accent : Colors.transparent,
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

/// The three ways this screen can be empty, each with the action that fixes it.
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
      padding: const EdgeInsets.fromLTRB(32, 60, 32, 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
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
                    color: Colors.black,
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
