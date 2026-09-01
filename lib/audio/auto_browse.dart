// The media browse tree Android Auto (and any MediaBrowser client) sees.
//
// Android Auto never renders our Flutter UI. It connects to the exported
// MediaBrowserService, walks a tree of MediaItems, and draws its own
// driver-distraction-compliant screens from them. So everything the car can
// reach has to be expressed here, as MediaItems.
//
// ## Layout
//
//   Downloads · Liked Songs · Recently Played · Playlists   the library
//   Music · Podcasts · Audiobooks                           the home feeds
//
// Downloads leads on purpose. A car is the one place where the network
// reliably drops mid-song, and downloaded tracks are the only tier that
// survives it — `StreamResolver` answers them without a round trip.
//
// ## Media ids
//
// Ids are opaque to the car, so routing is encoded into them. The format and
// every encode/decode of it live in `auto_media_id.dart` — build and parse ids
// only through `AutoMediaId`, or encoding and decoding drift apart.
//
// ## Two rules everything here obeys
//
// **Resolve cold.** The MediaBrowserService is a foreground service Android
// restarts independently of the Flutter UI, and the car remembers where the
// user was browsing across reconnects. So any node may be requested without
// its parent having been served this process. A node that only works from a
// warm cache renders as empty in the car and nowhere else.
//
// **Fail empty, never throw.** An exception out of a browse callback surfaces
// as a hard error in the car and can wedge the browse stack.
//
// The only Flutter import here is `foundation`, for debugPrint — no widgets,
// so the tree stays testable headlessly, per docs/ENGINEERING.md section 3.3.

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import '../api/dto.dart';
import '../api/sunoh_api.dart';
import 'auto_catalog.dart';
import 'auto_collections.dart';
import 'auto_feeds.dart';
import 'auto_media_id.dart';
import 'download_manager.dart';
import 'download_store.dart';
import 'library_store.dart';

/// Library tabs, in car-priority order.
enum _Tab { downloads, liked, recent, playlists }

extension on _Tab {
  String get id => '$kAutoTabPrefix$name';
  String get title => switch (this) {
    _Tab.downloads => 'Downloads',
    _Tab.liked => 'Liked Songs',
    _Tab.recent => 'Recently Played',
    _Tab.playlists => 'Playlists',
  };
}

class AutoBrowseTree {
  AutoBrowseTree({
    required this.library,
    required this.api,
    required this.playQueue,
    this.downloads,
    String? Function()? languages,
  }) : catalog = AutoCatalog() {
    // One shared catalog: a track tapped inside a feed section has to resolve
    // against the same cache the library tabs write to.
    _feeds = AutoFeeds(api: api, catalog: catalog, languages: languages);
    _collections = AutoCollections(
      api: api,
      library: library,
      catalog: catalog,
    );
  }

  final LibraryStore library;
  final SunohApi api;
  final DownloadManager? downloads;
  final AutoCatalog catalog;
  late final AutoFeeds _feeds;
  late final AutoCollections _collections;

  /// Starts playback. Wired to `AudioRepo.playQueue` in main.dart rather than
  /// taking the repo itself, so this class stays testable with a closure.
  final Future<void> Function(
    List<FeedItem> songs,
    int index, {
    String? sourceLabel,
  })
  playQueue;

  // ── Browsing ─────────────────────────────────────────────────────────────

  Future<List<MediaItem>> getChildren(String parentMediaId) async {
    if (parentMediaId == AudioService.browsableRootId) return _root();

    // The `recent` root is what Android Auto asks for when it wants to offer
    // "resume what you were playing" without the user browsing at all.
    if (parentMediaId == AudioService.recentRootId) {
      return catalog.tracks(
        _Tab.recent.id,
        await library.loadHistory(),
        'Recently played',
      );
    }

    if (parentMediaId == _Tab.downloads.id) {
      return catalog.tracks(parentMediaId, _downloadedSongs(), 'Downloads');
    }
    if (parentMediaId == _Tab.liked.id) {
      return catalog.tracks(
        parentMediaId,
        await library.loadLikedSongs(),
        'Liked songs',
      );
    }
    if (parentMediaId == _Tab.recent.id) {
      return catalog.tracks(
        parentMediaId,
        await library.loadHistory(),
        'Recently played',
      );
    }
    if (parentMediaId == _Tab.playlists.id) return _savedCollections();

    if (AutoFeeds.isFeed(parentMediaId)) return _feeds.sections(parentMediaId);
    if (AutoFeeds.isSection(parentMediaId)) {
      return _feeds.sectionItems(parentMediaId);
    }
    if (AutoMediaId.isCollection(parentMediaId)) {
      return _collections.children(parentMediaId);
    }
    return const [];
  }

  /// Library tabs first, then the three home feeds. The library is what a
  /// driver reaches for by reflex; the feeds are for browsing.
  List<MediaItem> _root() => [
    for (final t in _Tab.values)
      MediaItem(
        id: t.id,
        title: t.title,
        playable: false,
        // Tabs are labels, not artwork — list style so the car doesn't render
        // a row of empty grid squares.
        extras: kChildrenList,
      ),
    ..._feeds.feedTabs(),
  ];

  /// Downloaded songs, newest first. Only `done` entries: a partial file would
  /// fail to open and strand the car on a silent track.
  List<FeedItem> _downloadedSongs() {
    final mgr = downloads;
    if (mgr == null) return const [];
    final done =
        mgr.snapshot().where((e) => e.state == DownloadState.done).toList()
          ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return [for (final e in done) e.song];
  }

  /// User-created playlists first, then saved playlists, then saved albums.
  /// Own-made content ranks above saved content because it is what a driver
  /// reaches for by name.
  Future<List<MediaItem>> _savedCollections() async {
    final items = <MediaItem>[];

    for (final p in await library.loadUserPlaylists()) {
      final id = AutoMediaId.collection(kind: 'user', id: p.id);
      catalog.remember(id, p.songs, 'PLAYLIST · ${p.name}');
      items.add(
        MediaItem(
          id: id,
          title: p.name,
          artist: '${p.songs.length} songs',
          playable: false,
          extras: kChildrenList,
          artUri: AutoCatalog.artOf(p.songs.isEmpty ? null : p.songs.first),
        ),
      );
    }

    for (final kind in const ['playlist', 'album']) {
      for (final c in await library.loadSaved(kind)) {
        final id = AutoMediaId.collection(
          kind: kind,
          id: c.id,
          source: c.source ?? '',
        );
        catalog.label(id, '${kind.toUpperCase()} · ${c.title}');
        items.add(catalog.browsable(c, id: id));
      }
    }
    return items;
  }

  // ── Playback ─────────────────────────────────────────────────────────────

  /// The car tapped a row. Rebuild that row's container and start there.
  Future<void> playFromMediaId(String mediaId) async {
    final station = AutoMediaId.parseStation(mediaId);
    if (station != null) return _playStation(station);

    final track = AutoMediaId.parseTrack(mediaId);
    if (track != null) {
      var songs = catalog.songsFor(track.containerId);
      if (songs == null || songs.isEmpty) {
        // Cold path: the car restored a browse position across a service
        // restart. Rebuilding the container costs one read but is the
        // difference between playing and doing nothing.
        await getChildren(track.containerId);
        songs = catalog.songsFor(track.containerId);
      }
      if (songs == null || songs.isEmpty) return;
      await playQueue(
        songs,
        track.index.clamp(0, songs.length - 1),
        sourceLabel: catalog.labelFor(track.containerId),
      );
      return;
    }

    // A container handed to us directly ("play my Liked Songs") — from the top.
    if (AutoMediaId.isContainer(mediaId) ||
        AutoFeeds.isSection(mediaId) ||
        AutoFeeds.isFeed(mediaId)) {
      await getChildren(mediaId);
      final songs = catalog.songsFor(mediaId);
      if (songs == null || songs.isEmpty) return;
      await playQueue(songs, 0, sourceLabel: catalog.labelFor(mediaId));
    }
  }

  /// Start a radio station.
  ///
  /// A station is a seed, not a queue: the backend builds the queue from it.
  /// Saavn's quick-stations ship an empty `id` and are keyed off the name, so
  /// the whole seed FeedItem has to survive to this point — which is why
  /// stations are indexed against the container's seeds rather than carrying
  /// their identity in the media id.
  Future<void> _playStation(AutoTrackRef ref) async {
    var seed = catalog.seedAt(ref.containerId, ref.index);
    if (seed == null) {
      // Cold path — rebuild the container that offered it.
      await getChildren(ref.containerId);
      seed = catalog.seedAt(ref.containerId, ref.index);
    }
    if (seed == null) {
      debugPrint(
        '[auto] station seed missing: ${ref.containerId} #${ref.index}',
      );
      return;
    }
    // Every failure below is a dead-end the driver just sees as "tapped,
    // nothing happened" — none of it surfaces in the car — so each one logs
    // which of them it was.
    debugPrint(
      '[auto] station "${seed.title}" id=${seed.id} '
      'type=${seed.stationType} provider=${seed.source}',
    );
    final songs = await _stationSongs(seed);
    if (songs.isEmpty) {
      debugPrint('[auto] station "${seed.title}": no songs from either tier');
      return;
    }
    await playQueue(songs, 0, sourceLabel: 'RADIO · ${seed.title}');
  }

  /// Songs for a station seed, over two tiers.
  ///
  /// The radio two-step (session, then songs) is the richer answer but is
  /// unreliable per station kind: Saavn's *artist* stations currently 400 on
  /// the songs call — that is the whole "Recommended Artist Stations" shelf —
  /// while featured and Gaana stations work. `/music/recommend` answers the
  /// same question from a title, and is what the app's endless-autoplay
  /// already switched to for the same reason, so it backstops the car rather
  /// than leaving a tapped tile silent.
  Future<List<FeedItem>> _stationSongs(FeedItem seed) async {
    try {
      final sessionId = await api.fetchRadioSession(
        id: seed.id,
        type: seed.stationType ?? 'featured',
        provider: seed.source ?? 'saavn',
        name: seed.title,
        lang: seed.language,
      );
      if (sessionId != null && sessionId.isNotEmpty) {
        final songs = await api.fetchRadioSongs(sessionId);
        if (songs.isNotEmpty) {
          debugPrint('[auto] station "${seed.title}" → ${songs.length} songs');
          return songs;
        }
      }
      debugPrint('[auto] station "${seed.title}": radio tier empty');
    } catch (e) {
      debugPrint('[auto] station "${seed.title}": radio tier failed — $e');
    }

    try {
      final songs = await api.fetchRecommendations(
        query: seed.title,
        lang: seed.language,
      );
      debugPrint(
        '[auto] station "${seed.title}" → ${songs.length} via recommend',
      );
      return songs;
    } catch (e) {
      debugPrint('[auto] station "${seed.title}": recommend failed — $e');
      return const [];
    }
  }

  /// Voice search — "Hey Google, play `<something>` on sunoh".
  ///
  /// An empty query is the assistant's way of saying "just play something",
  /// which Android Auto's certification explicitly exercises. Answering it
  /// with silence is a fail, so we fall through the offline-first order.
  Future<void> playFromSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      for (final songs in [
        _downloadedSongs(),
        await library.loadLikedSongs(),
        await library.loadHistory(),
      ]) {
        if (songs.isNotEmpty) {
          await playQueue(songs, 0, sourceLabel: 'sunoh.');
          return;
        }
      }
      return;
    }

    final results = await _searchSongs(q);
    if (results.isEmpty) return;
    const id = '${kAutoTabPrefix}search';
    catalog.remember(id, results, 'SEARCH · $q');
    await playQueue(results, 0, sourceLabel: 'SEARCH · $q');
  }

  /// Browsable search results, for the car's own search screen.
  Future<List<MediaItem>> search(String query) async {
    const id = '${kAutoTabPrefix}search';
    return catalog.tracks(
      id,
      await _searchSongs(query.trim()),
      'SEARCH · $query',
    );
  }

  /// Songs across every section the search endpoint returns. Failure yields an
  /// empty list — the car shows "no results" rather than an error state.
  Future<List<FeedItem>> _searchSongs(String query) async {
    if (query.isEmpty) return const [];
    try {
      final sections = await api.fetchSearch(query);
      return [
        for (final s in sections)
          for (final item in s.items)
            if (item.type == 'song') item,
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Resolve a single id back to its MediaItem, for clients that ask.
  Future<MediaItem?> getMediaItem(String mediaId) async {
    final track = AutoMediaId.parseTrack(mediaId);
    if (track == null) return null;
    final songs = catalog.songsFor(track.containerId);
    if (songs == null || track.index >= songs.length) return null;
    return catalog.mediaItem(songs[track.index], id: mediaId);
  }
}
