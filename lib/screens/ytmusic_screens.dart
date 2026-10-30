// YouTube Music detail surfaces: a playlist/album track list and an artist
// page. Browsing moods and genres is yt_moods_screens.dart.
//
// These exist because YouTube browse ids can't go through the normal detail
// screens — those resolve against sunoh-api, which knows nothing about a
// `VLRDCLAK5uy_…` id.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dto.dart';
import '../api/ytmusic_api.dart';
import '../data/models.dart';
import '../providers/app_state_provider.dart';
import '../providers/downloads_provider.dart';
import '../providers/ytmusic_provider.dart';
import '../widgets/cover_hero.dart';
import 'album_body.dart';
import 'artist_page.dart';
import 'detail_loading.dart';
import 'detail_screens.dart' show paletteSettled;
import 'yt_scaffold.dart';

// ── Playlist / album ───────────────────────────────────────────────────────

class YtPlaylistScreen extends ConsumerWidget {
  const YtPlaylistScreen({
    super.key,
    required this.browseId,
    this.name,
    this.hero,
  });
  final String browseId;
  final String? name;
  final CoverHeroRef? hero;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final async = ref.watch(ytMusicPlaylistProvider(browseId));

    return async.when(
      // DetailLoading, not the title-only scaffold this used to show. The
      // data state below is AlbumLikeBody — a cover hero — so a
      // heading-and-spinner loader meant the screen visibly changed shape
      // once the response landed. saavn and gaana never did that because
      // they use this skeleton, which is the shape of what is coming.
      loading: () => DetailLoading(colors: c, hero: hero),
      error: (e, _) => YtScaffold(
        title: name ?? 'Playlist',
        colors: c,
        children: [ytError(c, 'Couldn\u2019t load this playlist.')],
      ),
      data: (detail) {
        if (detail == null) {
          return YtScaffold(
            title: name ?? 'Playlist',
            colors: c,
            children: [ytError(c, 'This playlist isn\u2019t available.')],
          );
        }
        // Same wait the saavn/gaana screens do — see paletteSettled.
        if (!paletteSettled(ref, detail.artwork)) {
          return DetailLoading(colors: c, hero: hero);
        }
        // Reuse the album/playlist body the rest of the app uses, rather
        // than a bespoke layout — that's what gives YouTube playlists the
        // same hero, pinned bar, actions row, track rows and menus as a
        // saavn or gaana playlist.
        return AlbumLikeBody(
          colors: c,
          id: detail.id,
          title: detail.title,
          imageUrl: detail.artwork,
          kindLabel: 'Playlist',
          byline: detail.subtitle,
          description: detail.description,
          songs: detail.tracks,
          sections: const [],
          // Tracks come from many different albums, so rows show their own
          // art beside the number.
          showAlbumArtInRow: true,
          sourceRef: DetailRef('playlist', detail.id, source: 'youtube'),
          hero: hero,
        );
      },
    );
  }
}

// ── Artist ─────────────────────────────────────────────────────────────────

class YtArtistScreen extends ConsumerWidget {
  const YtArtistScreen({super.key, required this.browseId, this.name});
  final String browseId;
  final String? name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final async = ref.watch(ytMusicArtistProvider(browseId));

    return async.when(
      // The artist page's own shape, as the saavn/gaana artist loads.
      loading: () => DetailLoading(colors: c, round: true),
      error: (e, _) => YtScaffold(
        title: name ?? 'Artist',
        colors: c,
        children: [ytError(c, 'Couldn\u2019t load this artist.')],
      ),
      data: (artist) {
        if (artist == null) {
          return YtScaffold(
            title: name ?? 'Artist',
            colors: c,
            children: [ytError(c, 'This artist isn\u2019t available.')],
          );
        }
        if (!paletteSettled(ref, artist.artwork)) {
          return DetailLoading(colors: c, round: true);
        }
        final art = artist.artwork ?? '';
        final songs = artist.topSongs;
        // The same page as a saavn/gaana artist: the top songs become
        // "Popular" and the discography carousels the shelves below.
        return ArtistPage(
          colors: c,
          artist: FeedItem(
            id: artist.id,
            title: artist.name,
            type: 'artist',
            image: art.isEmpty
                ? const []
                : [ApiImage(quality: 'hero', link: art)],
            subtitle: artist.subtitle,
            source: 'youtube',
          ),
          imageUrl: artist.artwork,
          topSongs: songs,
          sections: artist.sections,
          stats: artist.subtitle,
          bio: artist.description,
          onRadio: artist.hasRadio
              ? () => _startArtistRadio(ref, artist)
              : null,
          onDownloadAll: () {
            ref.read(downloadManagerProvider).enqueueAll(songs);
            s.flashToast('Queued ${songs.length} tracks');
          },
          onAddToQueue: () => s.addApiSongsToQueue(songs),
        );
      },
    );
  }

  /// Materialise the artist's endless station and hand it to the player.
  /// Radio playlists are server-generated, so the queue comes from /next
  /// rather than a browse.
  Future<void> _startArtistRadio(WidgetRef ref, YtArtistDetail artist) async {
    final s = ref.read(appStateProvider);
    s.flashToast('Starting ${artist.name} radio\u2026');
    try {
      final tracks = await ref
          .read(ytMusicApiProvider)
          .radioQueue(
            videoId: artist.radioVideoId!,
            playlistId: artist.radioPlaylistId!,
          );
      if (tracks.isEmpty) {
        s.flashToast('No station available for ${artist.name}');
        return;
      }
      await s.playApiQueue(
        tracks,
        0,
        sourceLabel: 'RADIO \u00b7 ${artist.name}',
      );
    } catch (e) {
      s.flashToast('Couldn\u2019t start that station');
    }
  }
}
