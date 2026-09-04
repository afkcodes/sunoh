// The two index conventions a reorderable list has to deal with, in one
// place, because confusing them is how a drag ends up one row off.
//
// `ReorderableList` used to report the drop through `onReorder`, whose
// `newIndex` is where the item lands *before* it is taken out of the list —
// so a `List.insert` needs one subtracted from it when the item moved down.
// `onReorderItem`, which replaced it, does that subtraction itself:
//
//     newIndex > oldIndex ? newIndex - 1 : newIndex
//
// and only fires at all when the result actually differs from `oldIndex`, so
// a drag that lands where it started never reaches us.
//
// That is the right convention for a list. It is the wrong one for mpv, whose
// `playlist-move from to` takes `to` as a before-removal index — the old
// callback's convention exactly. Both are needed, so both are named here
// rather than left as a `- 1` in one file and a `+ 1` in another.

/// A copy of [list] with the item at [from] moved to [to], where [to] is
/// `onReorderItem`'s already-adjusted index.
List<T> movedItem<T>(List<T> list, int from, int to) {
  final out = [...list];
  out.insert(to, out.removeAt(from));
  return out;
}

/// The `to` that mpv's `playlist-move` wants, from `onReorderItem`'s [to].
///
/// The inverse of the adjustment the framework applied. Exact, because
/// `onReorderItem` is never called with [to] equal to [from] — which is the
/// one case where the two conventions overlap and the inverse would have to
/// guess.
int mpvMoveTarget(int from, int to) => to > from ? to + 1 : to;
