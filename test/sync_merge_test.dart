// Tests for the sync merge rules.
//
// This is the part of sync that can lose data, so it is tested hardest. Every
// case here is one a two-phone setup actually produces: unliking on one device,
// editing both while offline, a device that has been away for months, and a
// library that predates sync entirely.

import 'package:flutter_test/flutter_test.dart';
import 'package:sunoh/api/dto.dart';
import 'package:sunoh/sync/sync_merge.dart';

FeedItem _song(String id) =>
    FeedItem(id: id, title: 'Song $id', type: 'song', image: const []);

const _liked = 'liked';

void main() {
  group('tombstones', () {
    test('an unlike on one device is not undone by the other', () {
      // The failure the whole design exists to prevent. Phone A unlikes 'b';
      // phone B still has it. A plain union puts it back on both.
      final meta = SyncMeta()
        ..markAdded(_liked, 'a', at: 100)
        ..markAdded(_liked, 'b', at: 100)
        ..markDeleted(_liked, 'b', at: 200);

      final merged = mergeItems(
        collection: _liked,
        local: [_song('a')],
        remote: [_song('a'), _song('b')],
        meta: meta,
      );

      expect(merged.map((s) => s.id), ['a']);
    });

    test('re-liking after a delete wins, because it is newer', () {
      final meta = SyncMeta()
        ..markDeleted(_liked, 'b', at: 200)
        ..markAdded(_liked, 'b', at: 300);

      final merged = mergeItems(
        collection: _liked,
        local: const [],
        remote: [_song('b')],
        meta: meta,
      );

      expect(merged.map((s) => s.id), ['b']);
    });

    test('a delete beats an older add from the other device', () {
      final mine = SyncMeta()..markAdded(_liked, 'x', at: 100);
      final theirs = SyncMeta()..markDeleted(_liked, 'x', at: 500);
      mine.mergeFrom(theirs);

      expect(mine.isAlive(_liked, 'x'), isFalse);
    });

    test('an add beats an older delete', () {
      final mine = SyncMeta()..markDeleted(_liked, 'x', at: 100);
      final theirs = SyncMeta()..markAdded(_liked, 'x', at: 500);
      mine.mergeFrom(theirs);

      expect(mine.isAlive(_liked, 'x'), isTrue);
    });

    test('merging is order-independent on an exact tie', () {
      // Caught a real bug: the tie-break used to keep "whichever is mine", so
      // two devices merging the same pair reached opposite answers and wrote
      // both back, flipping the item's state forever.
      SyncMeta a() => SyncMeta()..markAdded(_liked, 'x', at: 300);
      SyncMeta b() => SyncMeta()..markDeleted(_liked, 'x', at: 300);

      final ab = a()..mergeFrom(b());
      final ba = b()..mergeFrom(a());

      expect(ab.isAlive(_liked, 'x'), ba.isAlive(_liked, 'x'));
      // Deletion takes the tie: resurrecting is the failure that matters.
      expect(ab.isAlive(_liked, 'x'), isFalse);
    });
  });

  group('items with no metadata', () {
    test('survive, because they predate sync', () {
      // A library that existed before this feature has no records at all.
      // Dropping it to fix a bookkeeping gap would be deleting a user's data.
      final merged = mergeItems(
        collection: _liked,
        local: [_song('old1'), _song('old2')],
        remote: const [],
        meta: SyncMeta(),
      );

      expect(merged.map((s) => s.id), ['old1', 'old2']);
    });
  });

  group('item merging', () {
    test('unions both sides and keeps local order first', () {
      final merged = mergeItems(
        collection: _liked,
        local: [_song('a'), _song('b')],
        remote: [_song('c'), _song('a')],
        meta: SyncMeta(),
      );

      expect(merged.map((s) => s.id), ['a', 'b', 'c']);
    });

    test('the local copy of a shared item is kept', () {
      // It is at least as good as the remote and may carry enrichment the
      // other device never fetched.
      const local = FeedItem(
        id: 'a',
        title: 'Full Title',
        type: 'song',
        image: [],
        subtitle: 'Artist',
      );
      const remote = FeedItem(id: 'a', title: 'a', type: 'song', image: []);

      final merged = mergeItems(
        collection: _liked,
        local: [local],
        remote: [remote],
        meta: SyncMeta(),
      );

      expect(merged.single.subtitle, 'Artist');
    });

    test('items with no id are dropped rather than colliding', () {
      final merged = mergeItems(
        collection: _liked,
        local: [const FeedItem(id: '', title: 'junk', type: 'song', image: [])],
        remote: const [],
        meta: SyncMeta(),
      );

      expect(merged, isEmpty);
    });
  });

  group('tombstone pruning', () {
    test('old tombstones are dropped, live records never are', () {
      final now = DateTime(2026, 6, 1);
      final meta = SyncMeta()
        ..markDeleted(
          _liked,
          'ancient',
          at: now.subtract(const Duration(days: 200)).millisecondsSinceEpoch,
        )
        ..markDeleted(
          _liked,
          'recent',
          at: now.subtract(const Duration(days: 10)).millisecondsSinceEpoch,
        )
        ..markAdded(
          _liked,
          'alive',
          at: now.subtract(const Duration(days: 900)).millisecondsSinceEpoch,
        );

      final pruned = meta.pruneTombstones(now: now);

      expect(pruned, 1);
      expect(meta.record(_liked, 'ancient'), isNull);
      expect(meta.record(_liked, 'recent'), isNotNull);
      expect(
        meta.record(_liked, 'alive'),
        isNotNull,
        reason: 'live records are the collection, however old',
      );
    });
  });

  group('serialisation', () {
    test('round-trips through JSON', () {
      final meta = SyncMeta()
        ..markAdded(_liked, 'a', at: 111)
        ..markDeleted(_liked, 'b', at: 222);

      final back = SyncMeta.fromJson(meta.toJson());

      expect(back.record(_liked, 'a')!.at, 111);
      expect(back.record(_liked, 'a')!.deleted, isFalse);
      expect(back.record(_liked, 'b')!.at, 222);
      expect(back.record(_liked, 'b')!.deleted, isTrue);
    });

    test('malformed metadata degrades to empty rather than throwing', () {
      // The file comes from a folder the user controls, so it can be anything.
      expect(SyncMeta.fromJson(null).length, 0);
      expect(SyncMeta.fromJson('nonsense').length, 0);
      expect(SyncMeta.fromJson({'k': 'not a record'}).length, 0);
      expect(
        SyncMeta.fromJson({
          'k': {'no': 'at'},
        }).length,
        0,
      );
    });
  });

  group('episode progress', () {
    test('the furthest position wins, not the newest write', () {
      // Resuming earlier than you actually reached is the annoying failure.
      final merged = mergeProgress(
        local: {'ep1': 600, 'ep2': 30},
        remote: {'ep1': 120, 'ep3': 45},
      );

      expect(merged['ep1'], 600);
      expect(merged['ep2'], 30);
      expect(merged['ep3'], 45);
    });
  });
}
