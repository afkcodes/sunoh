// Merging one device's library with another's.
//
// The whole feature turns on this file, and on one rule: a collection is a set
// of records keyed by id, each carrying the time it was last touched and
// whether that touch was an addition or a removal. Merging takes, per id, the
// record with the newest timestamp.
//
// The naive alternative — union the two lists — is what makes cloud-synced
// libraries resurrect deleted things. Unliking a song on one phone removes it
// there; a union with the other phone, which still has it, puts it back, and
// it comes back on both. Deletions have to be represented, not just absent,
// which is what the tombstone is for.
//
// No Flutter import here: this is the part worth testing hardest, and it
// should be testable without a widget tree.

import '../api/dto.dart';

/// When a record's state was last set, and whether it still exists.
class SyncRecord {
  const SyncRecord({required this.at, required this.deleted});

  /// Milliseconds since epoch. Device clocks disagree, and that is tolerable:
  /// the failure mode of a skewed clock is that one device's edit loses to an
  /// older one, not corruption. Anything stronger (vector clocks, a Lamport
  /// counter per device) buys correctness the user would never notice at this
  /// scale and costs a schema nobody can debug.
  final int at;

  /// A tombstone. The item is gone, and this record says *when* it went, so a
  /// later addition on another device still wins.
  final bool deleted;

  SyncRecord.alive(this.at) : deleted = false;
  SyncRecord.tombstone(this.at) : deleted = true;

  Map<String, dynamic> toJson() => {'at': at, if (deleted) 'del': true};

  static SyncRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final at = (raw['at'] as num?)?.toInt();
    if (at == null) return null;
    return SyncRecord(at: at, deleted: raw['del'] == true);
  }

  /// The winning record for an id.
  ///
  /// Newest wins. On an exact tie a deletion wins, and that rule is load
  /// bearing: preferring "whichever is mine" makes the merge depend on which
  /// device runs it, so two phones merging the same pair reach opposite
  /// answers and then write both back — the library flips state forever.
  ///
  /// Deletion is the right side of a tie because resurrecting a removed item
  /// is the failure this whole file exists to prevent, and a tie means two
  /// devices acted within the same millisecond, which is coincidence rather
  /// than intent.
  static SyncRecord newer(SyncRecord a, SyncRecord b) {
    if (b.at != a.at) return b.at > a.at ? b : a;
    return a.deleted ? a : b;
  }
}

/// Timestamps and tombstones for everything syncable, keyed `collection:id`.
///
/// Kept beside the collections rather than inside them so the existing stored
/// shapes are untouched: the library boxes still hold exactly the JSON they
/// always did, and a build without sync reads them unchanged. It also means a
/// missing entry is meaningful — it marks data that predates sync, which is
/// treated as older than anything explicit.
class SyncMeta {
  SyncMeta([Map<String, SyncRecord>? records]) : _records = {...?records};

  final Map<String, SyncRecord> _records;

  static String key(String collection, String id) => '$collection:$id';

  Map<String, SyncRecord> get records => Map.unmodifiable(_records);
  int get length => _records.length;

  SyncRecord? record(String collection, String id) =>
      _records[key(collection, id)];

  void markAdded(String collection, String id, {int? at}) {
    _records[key(collection, id)] = SyncRecord.alive(
      at ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  void markDeleted(String collection, String id, {int? at}) {
    _records[key(collection, id)] = SyncRecord.tombstone(
      at ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// True when this id should be present after merging.
  bool isAlive(String collection, String id) =>
      !(record(collection, id)?.deleted ?? false);

  /// Merge another device's metadata in, newest-per-id winning.
  void mergeFrom(SyncMeta other) {
    for (final entry in other._records.entries) {
      final mine = _records[entry.key];
      _records[entry.key] = mine == null
          ? entry.value
          : SyncRecord.newer(mine, entry.value);
    }
  }

  /// Drop tombstones older than [maxAge].
  ///
  /// They cannot be kept forever, and they cannot be dropped eagerly either:
  /// a device that has been offline longer than the window still holds the
  /// item, sees no tombstone, and re-adds it. The window is the honest
  /// statement of how long a device may be away and still have its deletions
  /// respected. Live records are never pruned — they are the collection.
  int pruneTombstones({
    Duration maxAge = const Duration(days: 90),
    DateTime? now,
  }) {
    final cutoff =
        (now ?? DateTime.now()).millisecondsSinceEpoch - maxAge.inMilliseconds;
    final doomed = [
      for (final e in _records.entries)
        if (e.value.deleted && e.value.at < cutoff) e.key,
    ];
    for (final k in doomed) {
      _records.remove(k);
    }
    return doomed.length;
  }

  Map<String, dynamic> toJson() => {
    for (final e in _records.entries) e.key: e.value.toJson(),
  };

  static SyncMeta fromJson(Object? raw) {
    if (raw is! Map) return SyncMeta();
    final out = <String, SyncRecord>{};
    raw.forEach((k, v) {
      final rec = SyncRecord.fromJson(v);
      if (k is String && rec != null) out[k] = rec;
    });
    return SyncMeta(out);
  }
}

/// Merge one collection of items across devices.
///
/// [local] and [remote] are the item lists as each device holds them; [meta]
/// is the already-merged metadata. An item survives when its merged record is
/// not a tombstone, and items with no record at all survive too — that is data
/// from before sync existed, and dropping it would delete a library to fix a
/// bookkeeping gap.
///
/// Order follows [local] first, so a device's own ordering is preserved and
/// merging does not reshuffle a list the user is looking at.
List<FeedItem> mergeItems({
  required String collection,
  required List<FeedItem> local,
  required List<FeedItem> remote,
  required SyncMeta meta,
}) {
  final byId = <String, FeedItem>{};
  final order = <String>[];

  void take(List<FeedItem> items) {
    for (final item in items) {
      if (item.id.isEmpty) continue;
      if (!byId.containsKey(item.id)) order.add(item.id);
      // Later writers do not clobber earlier ones: the local copy is at least
      // as good as the remote and may carry enrichment the other device never
      // fetched.
      byId.putIfAbsent(item.id, () => item);
    }
  }

  take(local);
  take(remote);

  return [
    for (final id in order)
      if (meta.isAlive(collection, id)) byId[id]!,
  ];
}

/// Merge a map keyed by id, newest-per-key winning.
///
/// Used for episode progress, where the value is a position rather than an
/// item, and "newest" genuinely means the furthest-along listen.
Map<String, int> mergeProgress({
  required Map<String, int> local,
  required Map<String, int> remote,
}) {
  final out = <String, int>{...local};
  for (final e in remote.entries) {
    final mine = out[e.key];
    // Furthest position wins rather than newest write. Resuming an episode
    // earlier than you actually reached is the annoying failure; hearing a
    // few seconds twice is not.
    if (mine == null || e.value > mine) out[e.key] = e.value;
  }
  return out;
}
