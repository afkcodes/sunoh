// The document a device writes into the sync folder.
//
// One file per device, named `sunoh-<deviceId>.sync`, holding that device's
// whole syncable library plus its metadata. Devices never write each other's
// files, which is what removes the need for locking: a merge reads every file
// in the folder and writes only its own.
//
// Encrypted before it touches the folder — see `SyncBridge` on the native
// side. The folder is a cloud folder in practice, so the plaintext should
// never reach it.

import 'dart:convert';

import '../api/dto.dart';
import '../data/user_playlist.dart';
import 'sync_merge.dart';

/// Bumped only for a change old readers cannot cope with. A device running an
/// older build must be able to skip a file it does not understand rather than
/// import half of it.
const int kSyncFormatVersion = 1;

/// Everything one device contributes to the merge.
class SyncPayload {
  const SyncPayload({
    required this.deviceId,
    required this.writtenAt,
    required this.meta,
    this.liked = const [],
    this.savedAlbums = const [],
    this.savedPlaylists = const [],
    this.savedArtists = const [],
    this.userPlaylists = const [],
    this.podcasts = const [],
    this.episodeProgress = const {},
    this.settings = const {},
    this.settingsAt = 0,
  });

  final String deviceId;
  final int writtenAt;
  final SyncMeta meta;

  final List<FeedItem> liked;
  final List<FeedItem> savedAlbums;
  final List<FeedItem> savedPlaylists;
  final List<FeedItem> savedArtists;
  final List<UserPlaylist> userPlaylists;
  final List<FeedItem> podcasts;
  final Map<String, int> episodeProgress;

  /// Settings sync as one blob with a single timestamp rather than per key.
  ///
  /// Per-key merging needs a timestamp per key and a migration to add them,
  /// for a conflict that barely arises: two devices rarely change different
  /// settings between syncs, and when they do, losing one is a shrug. Whole
  /// set, last writer wins.
  final Map<String, dynamic> settings;
  final int settingsAt;

  /// Deliberately excluded, and worth stating so it is a decision rather than
  /// an oversight:
  ///
  /// - **Downloads.** The entries hold absolute file paths that mean nothing
  ///   on another device, and the audio itself is far too large to sync. A
  ///   future version could sync the *intent* to have something offline and
  ///   let each device fetch its own copy.
  /// - **Playback queue and position.** Per-device state. Syncing it makes two
  ///   phones fight over what is playing.
  /// - **History.** Merges as a plain union elsewhere; it needs no tombstones
  ///   because nothing is ever explicitly removed from it.
  static const excluded = ['downloads', 'playback queue', 'history'];

  Map<String, dynamic> toJson() => {
    'v': kSyncFormatVersion,
    'device': deviceId,
    'at': writtenAt,
    'meta': meta.toJson(),
    'liked': [for (final s in liked) s.toJson()],
    'albums': [for (final s in savedAlbums) s.toJson()],
    'playlists': [for (final s in savedPlaylists) s.toJson()],
    'artists': [for (final s in savedArtists) s.toJson()],
    'uplaylists': [for (final p in userPlaylists) p.toJson()],
    'podcasts': [for (final s in podcasts) s.toJson()],
    'progress': episodeProgress,
    'settings': settings,
    'settingsAt': settingsAt,
  };

  List<int> encode() => utf8.encode(jsonEncode(toJson()));

  /// Parse a file from the folder.
  ///
  /// Returns null for anything unreadable rather than throwing: these bytes
  /// came out of a directory the user controls and a cloud client writes to,
  /// so truncated files, partial uploads and unrelated documents are normal
  /// rather than exceptional. One bad file must not fail the whole sync.
  static SyncPayload? decode(List<int> bytes) {
    try {
      final raw = jsonDecode(utf8.decode(bytes));
      if (raw is! Map) return null;
      final version = (raw['v'] as num?)?.toInt() ?? 0;
      // A newer device wrote something this build cannot read. Skipping is
      // right: importing half of an unknown shape is worse than ignoring it.
      if (version > kSyncFormatVersion) return null;
      final device = raw['device']?.toString();
      if (device == null || device.isEmpty) return null;

      return SyncPayload(
        deviceId: device,
        writtenAt: (raw['at'] as num?)?.toInt() ?? 0,
        meta: SyncMeta.fromJson(raw['meta']),
        liked: _items(raw['liked']),
        savedAlbums: _items(raw['albums']),
        savedPlaylists: _items(raw['playlists']),
        savedArtists: _items(raw['artists']),
        userPlaylists: _playlists(raw['uplaylists']),
        podcasts: _items(raw['podcasts']),
        episodeProgress: _progress(raw['progress']),
        settings: raw['settings'] is Map
            ? (raw['settings'] as Map).cast<String, dynamic>()
            : const {},
        settingsAt: (raw['settingsAt'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  static List<FeedItem> _items(Object? raw) {
    if (raw is! List) return const [];
    final out = <FeedItem>[];
    for (final e in raw) {
      if (e is! Map) continue;
      try {
        out.add(FeedItem.fromJson(e.cast<String, dynamic>()));
      } catch (_) {
        // One malformed entry should not cost the whole collection.
      }
    }
    return out;
  }

  static List<UserPlaylist> _playlists(Object? raw) {
    if (raw is! List) return const [];
    final out = <UserPlaylist>[];
    for (final e in raw) {
      if (e is! Map) continue;
      try {
        out.add(UserPlaylist.fromJson(e.cast<String, dynamic>()));
      } catch (_) {
        // Same.
      }
    }
    return out;
  }

  static Map<String, int> _progress(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, int>{};
    raw.forEach((k, v) {
      final secs = (v as num?)?.toInt();
      if (k is String && secs != null && secs > 0) out[k] = secs;
    });
    return out;
  }
}

/// The result of folding every file in the folder together.
class MergedLibrary {
  const MergedLibrary({
    required this.meta,
    required this.liked,
    required this.savedAlbums,
    required this.savedPlaylists,
    required this.savedArtists,
    required this.userPlaylists,
    required this.podcasts,
    required this.episodeProgress,
    required this.settings,
    required this.settingsAt,
  });

  final SyncMeta meta;
  final List<FeedItem> liked;
  final List<FeedItem> savedAlbums;
  final List<FeedItem> savedPlaylists;
  final List<FeedItem> savedArtists;
  final List<UserPlaylist> userPlaylists;
  final List<FeedItem> podcasts;
  final Map<String, int> episodeProgress;
  final Map<String, dynamic> settings;
  final int settingsAt;
}

/// Fold this device's payload together with every other device's.
///
/// Metadata merges first and completely, because the item merge reads it to
/// decide what survives. Doing it per collection as you go would let a
/// tombstone from a file read later fail to suppress an item already kept.
MergedLibrary mergeAll({
  required SyncPayload local,
  required List<SyncPayload> remotes,
}) {
  final meta = SyncMeta(local.meta.records);
  for (final r in remotes) {
    meta.mergeFrom(r.meta);
  }

  List<FeedItem> fold(
    String collection,
    List<FeedItem> Function(SyncPayload) pick,
  ) {
    var acc = pick(local);
    for (final r in remotes) {
      acc = mergeItems(
        collection: collection,
        local: acc,
        remote: pick(r),
        meta: meta,
      );
    }
    // A single-device folder still needs the tombstone filter applied.
    return mergeItems(
      collection: collection,
      local: acc,
      remote: const [],
      meta: meta,
    );
  }

  var progress = local.episodeProgress;
  for (final r in remotes) {
    progress = mergeProgress(local: progress, remote: r.episodeProgress);
  }

  // Settings: newest write for the whole set.
  var settings = local.settings;
  var settingsAt = local.settingsAt;
  for (final r in remotes) {
    if (r.settingsAt > settingsAt) {
      settings = r.settings;
      settingsAt = r.settingsAt;
    }
  }

  return MergedLibrary(
    meta: meta,
    liked: fold('liked', (p) => p.liked),
    savedAlbums: fold('album', (p) => p.savedAlbums),
    savedPlaylists: fold('playlist', (p) => p.savedPlaylists),
    savedArtists: fold('artist', (p) => p.savedArtists),
    userPlaylists: _mergePlaylists(local, remotes, meta),
    podcasts: fold('podcast', (p) => p.podcasts),
    episodeProgress: progress,
    settings: settings,
    settingsAt: settingsAt,
  );
}

/// User playlists merge per playlist on `updatedAt`, not per song.
///
/// Per-song merging inside a playlist would need a record per song per
/// playlist, and would still not know what to do about order. Editing the same
/// playlist on two devices between syncs is rare; losing the older of the two
/// edits is understandable, where a silently interleaved track order is not.
List<UserPlaylist> _mergePlaylists(
  SyncPayload local,
  List<SyncPayload> remotes,
  SyncMeta meta,
) {
  final byId = <String, UserPlaylist>{};
  final order = <String>[];

  void take(List<UserPlaylist> playlists) {
    for (final p in playlists) {
      if (p.id.isEmpty) continue;
      if (!byId.containsKey(p.id)) order.add(p.id);
      final mine = byId[p.id];
      if (mine == null || p.updatedAt.isAfter(mine.updatedAt)) {
        byId[p.id] = p;
      }
    }
  }

  take(local.userPlaylists);
  for (final r in remotes) {
    take(r.userPlaylists);
  }

  return [
    for (final id in order)
      if (meta.isAlive('uplaylist', id)) byId[id]!,
  ];
}
