// Shared plumbing for the Android Auto browse tree: turning FeedItems into
// MediaItems, and remembering what each container held.
//
// Split out of `auto_browse.dart` because both the library tabs and the home
// feeds need it, and because it is the piece with the subtle contract:
// `playFromMediaId` arrives as a separate call with nothing but an id, so
// whatever a `getChildren` returned has to still be reachable when the tap
// comes back.

import 'package:audio_service/audio_service.dart';

import '../api/dto.dart';
import 'auto_media_id.dart';

/// Content-style keys Android Auto reads to decide grid vs list. Values are
/// the framework's own constants: 1 = list, 2 = grid.
const String kStyleSupported = 'android.media.browse.CONTENT_STYLE_SUPPORTED';
const String kStyleBrowsable =
    'android.media.browse.CONTENT_STYLE_BROWSABLE_HINT';
const String kStylePlayable =
    'android.media.browse.CONTENT_STYLE_PLAYABLE_HINT';
const int kStyleList = 1;
const int kStyleGrid = 2;

/// Tells Android Auto to offer a search affordance. Without it the car never
/// surfaces a search button, and `search` / `playFromSearch` are unreachable
/// however correctly they are implemented.
const String kSearchSupported = 'android.media.browse.SEARCH_SUPPORTED';

/// Child layout for a node whose children are all one kind, with artwork
/// worth showing large.
const Map<String, dynamic> kChildrenGrid = {
  kStyleBrowsable: kStyleGrid,
  kStylePlayable: kStyleList,
};

/// Child layout for a node whose children are MIXED — some browsable, some
/// playable.
///
/// This has to be list for both. Home-feed sections interleave collections and
/// songs, and with browsable hinted as a grid the car renders the collections
/// as full-width artwork tiles and the songs as compact rows in the same
/// scroll: the list visibly stutters between two row heights and is hard to
/// scan at a glance, which is the opposite of what a driver needs.
const Map<String, dynamic> kChildrenList = {
  kStyleBrowsable: kStyleList,
  kStylePlayable: kStyleList,
};

/// Extras returned from `onGetRoot`. List is the default for both kinds: it is
/// the layout that stays uniform whatever a node happens to contain, and
/// uniformity is what makes a list readable at a glance while driving.
/// Individual nodes opt into [kChildrenGrid] where their children are
/// homogeneous.
const Map<String, dynamic> kAutoRootExtras = {
  kStyleSupported: true,
  kStyleBrowsable: kStyleList,
  kStylePlayable: kStyleList,
  kSearchSupported: true,
};

/// Remembers the song list behind every container we have served, and maps
/// between FeedItems and MediaItems.
class AutoCatalog {
  /// Container id → the songs it held when last browsed.
  final Map<String, List<FeedItem>> _contents = {};

  /// Container id → the "playing from" label for its queue.
  final Map<String, String> _labels = {};

  List<FeedItem>? songsFor(String containerId) => _contents[containerId];
  String? labelFor(String containerId) => _labels[containerId];

  void remember(String containerId, List<FeedItem> songs, [String? label]) {
    _contents[containerId] = songs;
    if (label != null) _labels[containerId] = label;
  }

  void label(String containerId, String label) => _labels[containerId] = label;

  /// Turn a song list into playable MediaItems, remembering it so a later
  /// `playFromMediaId` on any row can rebuild the whole queue.
  List<MediaItem> tracks(
    String containerId,
    List<FeedItem> songs, [
    String? label,
  ]) {
    remember(containerId, songs, label);
    return [
      for (var i = 0; i < songs.length; i++)
        mediaItem(songs[i], id: AutoMediaId.track(containerId, i)),
    ];
  }

  /// A playable row.
  MediaItem mediaItem(FeedItem song, {required String id}) => MediaItem(
    id: id,
    title: song.title,
    artist: song.displaySubtitle,
    artUri: artOf(song),
    playable: true,
    duration: parseDuration(song.duration),
    extras: {'songId': song.id, 'source': song.source ?? ''},
  );

  /// A browsable row — a collection the user drills into.
  MediaItem browsable(
    FeedItem item, {
    required String id,
    String? subtitle,
    Map<String, dynamic> childStyle = kChildrenList,
  }) => MediaItem(
    id: id,
    title: item.title,
    artist: subtitle ?? item.displaySubtitle,
    artUri: artOf(item),
    playable: false,
    extras: childStyle,
  );

  static Uri? artOf(FeedItem? item) {
    final url = item?.artwork ?? '';
    return url.isEmpty ? null : Uri.tryParse(url);
  }

  static Duration? parseDuration(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final secs = int.tryParse(raw);
    return secs == null ? null : Duration(seconds: secs);
  }

  /// Map a feed entry to the collection id it should open, or null when the
  /// entry is not something the car can drill into.
  ///
  /// Types mirror what the phone UI routes on. Anything unrecognised is
  /// dropped rather than rendered as a dead row — a tile that does nothing
  /// when tapped is worse in a car than one that isn't there.
  /// True when a feed row can be rendered at all — playable, or something the
  /// car can drill into. Used to drop rows, and whole sections, that would
  /// otherwise render as dead space.
  static bool isRenderable(FeedItem item) =>
      item.type == 'song' || collectionIdFor(item) != null;

  static String? collectionIdFor(FeedItem item) {
    final source = item.source ?? '';
    return switch (item.type) {
      'album' => AutoMediaId.collection(
        kind: 'album',
        id: item.id,
        source: source,
      ),
      'playlist' => AutoMediaId.collection(
        kind: 'playlist',
        id: item.id,
        source: source,
      ),
      'artist' => AutoMediaId.collection(
        kind: 'artist',
        id: item.id,
        source: source,
      ),
      'podcast' || 'show' => AutoMediaId.collection(
        kind: 'show',
        id: item.id,
        source: source,
      ),
      'audiobook' || 'book' => AutoMediaId.collection(
        kind: 'book',
        id: item.id,
        source: source,
      ),
      // A genre shelf, not a book. Its children are more collections rather
      // than tracks, which `AutoBrowseTree` handles separately.
      'audiobook_category' => AutoMediaId.collection(
        kind: 'cat',
        id: item.id,
        source: source,
      ),
      _ => null,
    };
  }
}
