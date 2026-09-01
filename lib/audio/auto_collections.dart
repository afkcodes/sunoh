// Resolving a collection id to its children, for the Android Auto tree.
//
// A "collection" is anything the car can drill into that is not a tab or a
// feed section: a user playlist, a saved album, an artist, a podcast show, an
// audiobook, an audiobook genre shelf, or a curated channel page. They share
// one id form (`sunoh:c:<kind>:<id>:<source>`) and differ only in where their
// children come from.
//
// Every path here must work from the id alone. The MediaBrowserService is a
// foreground service Android restarts independently of the Flutter UI, and the
// car remembers where the user was browsing across reconnects — so a
// collection is routinely asked for without its parent having been served this
// process. A path that only works from a warm cache renders as empty in the
// car and nowhere else.

import 'package:audio_service/audio_service.dart';

import '../api/dto.dart';
import '../api/sunoh_api.dart';
import 'auto_catalog.dart';
import 'auto_media_id.dart';
import 'library_store.dart';

class AutoCollections {
  AutoCollections({
    required this.api,
    required this.library,
    required this.catalog,
  });

  final SunohApi api;
  final LibraryStore library;
  final AutoCatalog catalog;

  /// Children of the collection [id], whatever kind it is.
  Future<List<MediaItem>> children(String id) async {
    final cached = catalog.songsFor(id);
    if (cached != null && cached.isNotEmpty) {
      return catalog.tracks(id, cached, catalog.labelFor(id));
    }

    final ref = AutoMediaId.parseCollection(id);
    if (ref == null) return const [];

    // Local, and the only kind needing no network — read it back rather than
    // trusting the cache. Resolving it here also recovers the playlist's real
    // name for the "playing from" label.
    if (ref.kind == 'user') return _userPlaylist(id, ref.id);

    // These two return rows rather than a queue, so they bypass the track
    // switch below: a genre shelf holds books, and a channel page holds a
    // mixed list — neither is something to play from top to bottom.
    if (ref.kind == 'cat') return _categoryBooks(ref.id);
    if (ref.kind == 'occ') return _channel(id, ref);

    return _tracks(id, ref);
  }

  Future<List<MediaItem>> _userPlaylist(String id, String playlistId) async {
    for (final p in await library.loadUserPlaylists()) {
      if (p.id == playlistId) {
        return catalog.tracks(id, p.songs, 'PLAYLIST · ${p.name}');
      }
    }
    return const [];
  }

  /// Kinds whose children are a queue.
  Future<List<MediaItem>> _tracks(String id, AutoCollectionRef ref) async {
    final provider = ref.source.isEmpty ? null : ref.source;
    try {
      final songs = switch (ref.kind) {
        'album' => (await api.fetchAlbum(ref.id, provider: provider)).songs,
        'playlist' => (await api.fetchPlaylist(
          ref.id,
          provider: provider,
        )).songs,
        'artist' => (await api.fetchArtist(
          ref.id,
          provider: provider,
        )).topSongs,
        'show' => (await api.fetchPodcastShow(ref.id)).episodes,
        'book' =>
          (await api.fetchAudiobookDetail(ref.id))?.chapters ??
              const <FeedItem>[],
        _ => const <FeedItem>[],
      };
      return catalog.tracks(
        id,
        songs,
        catalog.labelFor(id) ?? ref.kind.toUpperCase(),
      );
    } catch (_) {
      // A dead collection must not take the car UI down with it — an empty
      // list renders as "nothing here", which is recoverable by backing out.
      return const [];
    }
  }

  /// Books in one audiobook genre, as browsable rows.
  Future<List<MediaItem>> _categoryBooks(String categoryId) async {
    final id = int.tryParse(categoryId);
    if (id == null) return const [];
    try {
      final books = await api.fetchAudiobooksByCategory(categoryId: id);
      final rows = <MediaItem>[];
      for (final b in books) {
        final bookId = AutoCatalog.collectionIdFor(b);
        if (bookId == null) continue;
        catalog.label(bookId, 'AUDIOBOOK · ${b.title}');
        rows.add(catalog.browsable(b, id: bookId));
      }
      return rows;
    } catch (_) {
      return const [];
    }
  }

  /// A channel / occasion page, flattened to one list of rows.
  ///
  /// The endpoint returns its own sections, but a second level of nesting for
  /// what is usually one or two shelves costs the driver an extra tap for
  /// nothing, so they are flattened into the same mixed-row shape a home-feed
  /// section uses.
  Future<List<MediaItem>> _channel(String id, AutoCollectionRef ref) async {
    try {
      final sections = await api.fetchOccasionDetail(
        ref.id,
        provider: ref.source.isEmpty ? 'saavn' : ref.source,
      );
      final items = [for (final s in sections) ...s.items];
      return catalog.rows(id, items, catalog.labelFor(id) ?? 'CHANNEL');
    } catch (_) {
      return const [];
    }
  }
}
