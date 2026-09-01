// Encoding and decoding of the media ids Android Auto hands back to us.
//
// A MediaBrowser client treats ids as opaque strings and gives us nothing else
// to work with: `playFromMediaId` arrives with an id and no context, possibly
// in a fresh process. So the id has to carry everything needed to rebuild what
// the user tapped. This file is the single definition of that format, kept
// apart from the tree itself because it is pure string work and the piece most
// worth testing directly.
//
//   sunoh:t:<tab>                  a root container
//   sunoh:c:<kind>:<id>:<source>   a collection (user playlist, saved album…)
//   sunoh:s:<container>#<index>    a track, addressed by position
//
// Tracks are positional rather than carrying a song id because tapping the
// fourth row of a playlist has to start that playlist at row four. An id
// identifying only the song would lose the queue around it.

const String kAutoTabPrefix = 'sunoh:t:';
const String kAutoCollectionPrefix = 'sunoh:c:';
const String kAutoTrackPrefix = 'sunoh:s:';

/// A radio station row. Distinct from a track because a station is not an
/// entry in a queue — playing one means asking the backend to build a queue
/// from the seed, so it resolves against the container's SEEDS, not its songs.
const String kAutoStationPrefix = 'sunoh:x:';

/// A decoded collection id.
typedef AutoCollectionRef = ({String kind, String id, String source});

/// A decoded track id: which container, and where in it.
typedef AutoTrackRef = ({String containerId, int index});

abstract final class AutoMediaId {
  /// `sunoh:c:<kind>:<id>:<source>`. [source] may be empty (local content).
  static String collection({
    required String kind,
    required String id,
    String source = '',
  }) => '$kAutoCollectionPrefix$kind:$id:$source';

  /// `sunoh:s:<container>#<index>`.
  static String track(String containerId, int index) =>
      '$kAutoTrackPrefix$containerId#$index';

  /// `sunoh:x:<container>#<index>`.
  static String station(String containerId, int index) =>
      '$kAutoStationPrefix$containerId#$index';

  static bool isCollection(String id) => id.startsWith(kAutoCollectionPrefix);
  static bool isTrack(String id) => id.startsWith(kAutoTrackPrefix);
  static bool isStation(String id) => id.startsWith(kAutoStationPrefix);
  static bool isContainer(String id) =>
      id.startsWith(kAutoTabPrefix) || isCollection(id);

  /// Decode a collection id, or null if it isn't one.
  ///
  /// Splits on the FIRST and LAST colon rather than by position. Collection
  /// ids come from upstream catalogues and some carry colons of their own
  /// (YouTube browse ids especially); a positional `split(':')` would shift
  /// every field and resolve a different collection than the user tapped.
  static AutoCollectionRef? parseCollection(String id) {
    if (!isCollection(id)) return null;
    final body = id.substring(kAutoCollectionPrefix.length);
    final first = body.indexOf(':');
    final last = body.lastIndexOf(':');
    if (first < 0 || last < first) return null;
    return (
      kind: body.substring(0, first),
      id: body.substring(first + 1, last),
      source: body.substring(last + 1),
    );
  }

  /// Decode a track id, or null if it isn't one.
  ///
  /// Uses the LAST `#` so a container id containing one can't truncate the
  /// index.
  static AutoTrackRef? parseTrack(String id) =>
      _parseIndexed(id, kAutoTrackPrefix);

  /// Decode a station id, or null if it isn't one.
  static AutoTrackRef? parseStation(String id) =>
      _parseIndexed(id, kAutoStationPrefix);

  static AutoTrackRef? _parseIndexed(String id, String prefix) {
    if (!id.startsWith(prefix)) return null;
    final body = id.substring(prefix.length);
    final hash = body.lastIndexOf('#');
    if (hash < 0) return null;
    final index = int.tryParse(body.substring(hash + 1));
    if (index == null || index < 0) return null;
    return (containerId: body.substring(0, hash), index: index);
  }
}
