// Matching for the Library's own search. The Library is local data, so this
// is a plain in-memory filter: online search belongs to the Search tab.
//
// Each item's searchable text (title, subtitle, artist names) is folded once
// and remembered against the item itself, so a keystroke costs one
// `contains` per item instead of re-lowercasing and de-accenting every row.
// An Expando is used rather than a map because it lets the key be collected
// with the item when the library list is replaced.

import '../api/dto.dart';
import '../data/user_playlist.dart';

/// Latin letters that carry marks, folded to their base letter. Only what
/// music metadata really contains (Hindi titles arrive transliterated), not
/// a full Unicode table, which would need a package for no gain here.
const Map<String, String> _kBases = {
  'a': 'àáâãäåāăą',
  'c': 'çćč',
  'd': 'ď',
  'e': 'èéêëēėęě',
  'i': 'ìíîïīį',
  'l': 'ł',
  'n': 'ñńň',
  'o': 'òóôõöøōő',
  'r': 'ŕř',
  's': 'śšş',
  't': 'ť',
  'u': 'ùúûüūůűų',
  'y': 'ýÿ',
  'z': 'źżž',
};

final Map<int, String> _fold = {
  for (final e in _kBases.entries)
    for (final u in e.value.runes) u: e.key,
};

/// Lowercases [s] and strips the accents above, so "Beyoncé" matches
/// "beyonce" and the other way round.
String foldForSearch(String s) {
  final lower = s.toLowerCase();
  final out = StringBuffer();
  for (final u in lower.codeUnits) {
    out.write(_fold[u] ?? String.fromCharCode(u));
  }
  return out.toString();
}

final Expando<String> _itemKeys = Expando<String>('libraryItemKey');
final Expando<String> _playlistKeys = Expando<String>('libraryPlaylistKey');

String _keyOf(FeedItem it) => _itemKeys[it] ??= foldForSearch(
  [
    it.title,
    it.subtitle ?? '',
    for (final a in it.artists ?? const <ApiArtistRef>[]) a.name,
  ].join(' '),
);

/// The items whose title, subtitle or artists contain [foldedQuery] (already
/// through [foldForSearch]). Order is preserved; an empty query keeps all.
List<FeedItem> filterLibraryItems(List<FeedItem> items, String foldedQuery) {
  if (foldedQuery.isEmpty) return items;
  return [
    for (final it in items)
      if (_keyOf(it).contains(foldedQuery)) it,
  ];
}

/// The user's own playlists whose name contains [foldedQuery].
List<UserPlaylist> filterLibraryPlaylists(
  List<UserPlaylist> playlists,
  String foldedQuery,
) {
  if (foldedQuery.isEmpty) return playlists;
  return [
    for (final p in playlists)
      if ((_playlistKeys[p] ??= foldForSearch(p.name)).contains(foldedQuery)) p,
  ];
}

/// Remembers the last list built from the same inputs, so `build()` hands
/// back the identical list until the library, chip, sort or query changes
/// (which also keeps the saved list's hero tags and children stable).
class LibraryListMemo<T> {
  List<Object?>? _inputs;
  List<T> _out = const [];

  List<T> get(List<Object?> inputs, List<T> Function() compute) {
    final prev = _inputs;
    if (prev != null && prev.length == inputs.length) {
      var same = true;
      for (var i = 0; i < inputs.length; i++) {
        if (!identical(prev[i], inputs[i]) && prev[i] != inputs[i]) {
          same = false;
          break;
        }
      }
      if (same) return _out;
    }
    _inputs = inputs;
    return _out = compute();
  }
}
