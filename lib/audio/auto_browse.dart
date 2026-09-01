// The media browse tree Android Auto (and any MediaBrowser client) sees.
//
// Android Auto never renders our Flutter UI. It connects to the exported
// MediaBrowserService, walks a tree of MediaItems, and draws its own
// driver-distraction-compliant screens from them. So everything the car can
// reach has to be expressed here, as MediaItems.
//
// ## Media id scheme
//
// Ids are opaque strings to the car, so routing is encoded into them. The
// format and every encode/decode of it live in `auto_media_id.dart` — build
// and parse ids only through `AutoMediaId`, never by hand, or encoding and
// decoding drift apart.
//
// ## Offline first
//
// Downloads is the first tab on purpose. A car is the one place where the
// network reliably drops mid-song, and downloaded tracks are the only tier
// that survives it — `StreamResolver` answers them without a round trip.
//
// This class holds no Flutter dependency so it can be tested without a widget
// tree, per docs/ENGINEERING.md section 3.3.

import 'package:audio_service/audio_service.dart';

import '../api/dto.dart';
import '../api/sunoh_api.dart';
import 'auto_media_id.dart';
import 'download_manager.dart';
import 'download_store.dart';
import 'library_store.dart';

/// Content-style keys Android Auto reads to decide grid vs list. The values
/// are the framework's own constants: 1 = list, 2 = grid.
const _kStyleSupported = 'android.media.browse.CONTENT_STYLE_SUPPORTED';
const _kStyleBrowsable = 'android.media.browse.CONTENT_STYLE_BROWSABLE_HINT';
const _kStylePlayable = 'android.media.browse.CONTENT_STYLE_PLAYABLE_HINT';
const _kStyleList = 1;
const _kStyleGrid = 2;

/// Extras handed back from `onGetRoot`. Declaring list style for playable
/// items keeps long track lists readable at a glance; collections render as
/// a grid so artwork does the identifying work.
const Map<String, dynamic> kAutoRootExtras = {
  _kStyleSupported: true,
  _kStyleBrowsable: _kStyleGrid,
  _kStylePlayable: _kStyleList,
};

/// Root-level tabs, in car-priority order.
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
  });

  final LibraryStore library;
  final SunohApi api;
  final DownloadManager? downloads;

  /// Starts playback. Wired to `AudioRepo.playQueue` in main.dart rather than
  /// taking the repo itself, so this class stays testable with a closure.
  final Future<void> Function(
    List<FeedItem> songs,
    int index, {
    String? sourceLabel,
  })
  playQueue;

  /// Last-resolved contents per container id.
  ///
  /// `playFromMediaId` arrives as a *separate* call from the `getChildren`
  /// that produced the row the user tapped, with nothing but an id. Without
  /// this the play path would have to re-read Hive or re-hit the network
  /// before the first note — the exact latency a car user feels most.
  final Map<String, List<FeedItem>> _contents = {};

  /// Human label per container, for the player's "playing from" line.
  final Map<String, String> _labels = {};

  // ── Browsing ─────────────────────────────────────────────────────────────

  Future<List<MediaItem>> getChildren(String parentMediaId) async {
    if (parentMediaId == AudioService.browsableRootId) return _rootTabs();

    // The `recent` root is what Android Auto asks for when it wants to offer
    // "resume what you were playing" without the user browsing at all.
    if (parentMediaId == AudioService.recentRootId) {
      return _tracksOf(
        _Tab.recent.id,
        await _historySongs(),
        'Recently played',
      );
    }

    if (parentMediaId == _Tab.downloads.id) {
      return _tracksOf(parentMediaId, _downloadedSongs(), 'Downloads');
    }
    if (parentMediaId == _Tab.liked.id) {
      return _tracksOf(
        parentMediaId,
        await library.loadLikedSongs(),
        'Liked songs',
      );
    }
    if (parentMediaId == _Tab.recent.id) {
      return _tracksOf(parentMediaId, await _historySongs(), 'Recently played');
    }
    if (parentMediaId == _Tab.playlists.id) return _collections();

    if (AutoMediaId.isCollection(parentMediaId)) {
      return _collectionTracks(parentMediaId);
    }
    return const [];
  }

  List<MediaItem> _rootTabs() => [
    for (final t in _Tab.values)
      MediaItem(
        id: t.id,
        title: t.title,
        playable: false,
        // Tabs are labels, not artwork — force list style so the car doesn't
        // render four empty grid squares.
        extras: const {_kStyleBrowsable: _kStyleList},
      ),
  ];

  /// Downloaded songs, newest first. Only `done` entries: a partial file
  /// would fail to open and strand the car on a silent track.
  List<FeedItem> _downloadedSongs() {
    final mgr = downloads;
    if (mgr == null) return const [];
    final done =
        mgr.snapshot().where((e) => e.state == DownloadState.done).toList()
          ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return [for (final e in done) e.song];
  }

  Future<List<FeedItem>> _historySongs() async => library.loadHistory();

  /// User-created playlists first, then saved playlists, then saved albums.
  /// Own-made content ranks above saved content because it is what a driver
  /// reaches for by name.
  Future<List<MediaItem>> _collections() async {
    final items = <MediaItem>[];

    for (final p in await library.loadUserPlaylists()) {
      final id = AutoMediaId.collection(kind: 'user', id: p.id);
      _contents[id] = p.songs;
      _labels[id] = 'PLAYLIST · ${p.name}';
      items.add(
        MediaItem(
          id: id,
          title: p.name,
          artist: '${p.songs.length} songs',
          playable: false,
          artUri: _artOf(p.songs.isEmpty ? null : p.songs.first),
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
        _labels[id] = '${kind.toUpperCase()} · ${c.title}';
        items.add(
          MediaItem(
            id: id,
            title: c.title,
            artist: c.displaySubtitle,
            playable: false,
            artUri: _artOf(c),
          ),
        );
      }
    }
    return items;
  }

  /// Tracks of one collection, resolved from the id alone.
  ///
  /// This must work with a COLD cache. The MediaBrowserService is a
  /// foreground service Android restarts independently of the Flutter UI, and
  /// Android Auto remembers where the user was browsing across reconnects —
  /// so the car routinely asks for a collection whose `getChildren` we never
  /// served this process. Relying on `_contents` being warm here silently
  /// renders the user's own playlists as empty.
  Future<List<MediaItem>> _collectionTracks(String id) async {
    final cached = _contents[id];
    if (cached != null) return _tracksOf(id, cached, _labels[id]);

    final ref = AutoMediaId.parseCollection(id);
    if (ref == null) return const [];
    final kind = ref.kind;
    final collectionId = ref.id;
    final provider = ref.source.isEmpty ? null : ref.source;

    // Local, and the only kind needing no network — read it back rather than
    // trusting the cache. Resolving it here (not in the switch below) also
    // recovers the playlist's real name for the "playing from" label.
    if (kind == 'user') {
      for (final p in await library.loadUserPlaylists()) {
        if (p.id == collectionId) {
          return _tracksOf(id, p.songs, 'PLAYLIST · ${p.name}');
        }
      }
      return const [];
    }

    try {
      final songs = switch (kind) {
        'album' => (await api.fetchAlbum(
          collectionId,
          provider: provider,
        )).songs,
        'playlist' => (await api.fetchPlaylist(
          collectionId,
          provider: provider,
        )).songs,
        _ => const <FeedItem>[],
      };
      return _tracksOf(id, songs, _labels[id] ?? _labelFor(kind, collectionId));
    } catch (_) {
      // A dead collection must not take the car UI down with it — an empty
      // list renders as "nothing here", which is recoverable by backing out.
      return const [];
    }
  }

  /// Fallback "playing from" label when the collection was reached cold and
  /// we never rendered its parent row.
  static String _labelFor(String kind, String collectionId) =>
      kind == 'user' ? 'PLAYLIST' : '${kind.toUpperCase()} · $collectionId';

  /// Turn a song list into playable MediaItems and remember it, so a later
  /// `playFromMediaId` on any of them can rebuild the queue instantly.
  List<MediaItem> _tracksOf(
    String containerId,
    List<FeedItem> songs, [
    String? label,
  ]) {
    _contents[containerId] = songs;
    if (label != null) _labels[containerId] = label;
    return [
      for (var i = 0; i < songs.length; i++)
        _mediaItem(songs[i], id: AutoMediaId.track(containerId, i)),
    ];
  }

  // ── Playback ─────────────────────────────────────────────────────────────

  /// The car tapped a row. Rebuild that row's container and start there.
  Future<void> playFromMediaId(String mediaId) async {
    final track = AutoMediaId.parseTrack(mediaId);
    if (track != null) {
      final containerId = track.containerId;
      final index = track.index;

      var songs = _contents[containerId];
      if (songs == null || songs.isEmpty) {
        // Cold path: the car restored a browse position across a service
        // restart, so our cache is empty. Rebuilding the container costs one
        // read but is the difference between playing and doing nothing.
        await getChildren(containerId);
        songs = _contents[containerId];
      }
      if (songs == null || songs.isEmpty) return;
      await playQueue(
        songs,
        index.clamp(0, songs.length - 1),
        sourceLabel: _labels[containerId],
      );
      return;
    }

    // A container was handed to us directly ("play my Liked Songs") — start
    // it from the top.
    if (AutoMediaId.isContainer(mediaId)) {
      await getChildren(mediaId);
      final songs = _contents[mediaId];
      if (songs == null || songs.isEmpty) return;
      await playQueue(songs, 0, sourceLabel: _labels[mediaId]);
    }
  }

  /// Voice search — "Hey Google, play `<something>` on sunoh".
  ///
  /// An empty query is the assistant's way of saying "just play something",
  /// which Android Auto's certification explicitly exercises. Answering it
  /// with silence is a fail, so we fall back through the offline-first order.
  Future<void> playFromSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      for (final songs in [
        _downloadedSongs(),
        await library.loadLikedSongs(),
        await _historySongs(),
      ]) {
        if (songs.isNotEmpty) {
          _contents['${kAutoTabPrefix}auto'] = songs;
          await playQueue(songs, 0, sourceLabel: 'sunoh.');
          return;
        }
      }
      return;
    }

    final results = await _searchSongs(q);
    if (results.isEmpty) return;
    const id = '${kAutoTabPrefix}search';
    _contents[id] = results;
    _labels[id] = 'SEARCH · $q';
    await playQueue(results, 0, sourceLabel: _labels[id]);
  }

  /// Browsable search results, for head units that show a search screen.
  Future<List<MediaItem>> search(String query) async {
    final results = await _searchSongs(query.trim());
    const id = '${kAutoTabPrefix}search';
    _labels[id] = 'SEARCH · $query';
    return _tracksOf(id, results, _labels[id]);
  }

  /// Songs across every section the search endpoint returns. Failure yields
  /// an empty list — the car shows "no results" rather than an error state.
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
    final songs = _contents[track.containerId];
    if (songs == null || track.index >= songs.length) return null;
    return _mediaItem(songs[track.index], id: mediaId);
  }

  // ── Mapping ──────────────────────────────────────────────────────────────

  static Uri? _artOf(FeedItem? song) {
    final url = song?.artwork ?? '';
    return url.isEmpty ? null : Uri.tryParse(url);
  }

  MediaItem _mediaItem(FeedItem song, {required String id}) => MediaItem(
    id: id,
    title: song.title,
    artist: song.displaySubtitle,
    artUri: _artOf(song),
    playable: true,
    duration: _duration(song.duration),
    extras: {'songId': song.id, 'source': song.source ?? ''},
  );

  static Duration? _duration(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final secs = int.tryParse(raw);
    return secs == null ? null : Duration(seconds: secs);
  }
}
