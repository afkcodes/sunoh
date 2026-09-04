// The reorder index conventions, which are the only part of a drag that can
// be wrong without looking wrong — the row lands one place off and nobody
// notices until a queue plays in the order they didn't ask for.
//
// The tests drive both helpers through the framework's own adjustment, so
// they are checking the pair against the rule `ReorderableList` actually
// applies rather than against a restatement of it.

import 'package:flutter_test/flutter_test.dart';
import 'package:sunoh/state/reorder.dart';

/// What `ReorderableList` does to `newIndex` before calling `onReorderItem`,
/// copied from `_ReorderableListState._handleReorderItem`.
int adjusted(int oldIndex, int newIndex) =>
    newIndex > oldIndex ? newIndex - 1 : newIndex;

/// The move as the old `onReorder` callback's users had to write it. The
/// reference the new path has to agree with.
List<T> legacyMove<T>(List<T> list, int oldIndex, int newIndex) {
  final out = [...list];
  if (newIndex > oldIndex) newIndex -= 1;
  out.insert(newIndex, out.removeAt(oldIndex));
  return out;
}

void main() {
  const list = ['a', 'b', 'c', 'd', 'e'];

  group('movedItem', () {
    test('agrees with the old callback for every drag on a 5-item list', () {
      for (var from = 0; from < list.length; from++) {
        // `newIndex` from the framework runs 0..length inclusive: dropping
        // past the last row is a real position.
        for (var raw = 0; raw <= list.length; raw++) {
          final to = adjusted(from, raw);
          // The framework filters out a drag that changes nothing, so this
          // pair never reaches the app.
          if (to == from) continue;
          expect(
            movedItem(list, from, to),
            legacyMove(list, from, raw),
            reason: 'from=$from raw=$raw adjusted=$to',
          );
        }
      }
    });

    test('moving down puts the item after its new neighbour', () {
      // Dropping "a" into the slot after "c" is raw 3, which the framework
      // hands over as 2 — the gap after an item is numbered one higher than
      // the item, and that offset is the whole reason these two conventions
      // exist.
      expect(movedItem(list, 0, adjusted(0, 3)), ['b', 'c', 'a', 'd', 'e']);
    });

    test('moving up puts the item before its new neighbour', () {
      expect(movedItem(list, 3, adjusted(3, 1)), ['a', 'd', 'b', 'c', 'e']);
    });

    test('dragging to the very end keeps every item', () {
      final out = movedItem(list, 0, adjusted(0, list.length));
      expect(out, ['b', 'c', 'd', 'e', 'a']);
      expect(out, hasLength(list.length));
    });

    test('the source list is not touched', () {
      final source = [...list];
      movedItem(source, 0, 3);
      expect(source, list);
    });
  });

  group('mpvMoveTarget', () {
    test('recovers the before-removal index the framework adjusted away', () {
      for (var from = 0; from < list.length; from++) {
        for (var raw = 0; raw <= list.length; raw++) {
          final to = adjusted(from, raw);
          if (to == from) continue;
          expect(
            mpvMoveTarget(from, to),
            raw,
            reason: 'from=$from raw=$raw adjusted=$to',
          );
        }
      }
    });

    test('a move down is one higher than the list index', () {
      // Dragging row 0 to sit after row 2: the list wants 2, mpv wants 3.
      expect(mpvMoveTarget(0, 2), 3);
    });

    test('a move up is the same index in both conventions', () {
      expect(mpvMoveTarget(3, 1), 1);
    });
  });
}
