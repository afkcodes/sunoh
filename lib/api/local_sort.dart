// How the on-device library is ordered.
//
// The scan returns MediaStore's own order, newest file first, and that used to
// be the only order there was. It is a reasonable default and a poor only
// option: a library you have had for years is mostly not sorted by when the
// files happened to land on the phone.
//
// Lives in api/ rather than audio/ because it is pure ordering over the DTOs
// defined here, and api/ must not depend upward on audio/.
//
// Track number is deliberately not in this list. It is not a way to sort a
// library — it is the correct order *within an album*, applied there
// regardless of what the library is sorted by, because track 7 before track 2
// is simply wrong.

import 'dto.dart';
import 'local_media_channel.dart';

enum LocalSort { dateAdded, title, artist, album, duration, year }

extension LocalSortLabel on LocalSort {
  String get label => switch (this) {
    LocalSort.dateAdded => 'Date added',
    LocalSort.title => 'Title',
    LocalSort.artist => 'Artist',
    LocalSort.album => 'Album',
    LocalSort.duration => 'Duration',
    LocalSort.year => 'Year',
  };

  /// What ascending means for this field, in words. "A to Z" and "Oldest
  /// first" are the same direction and reading either as "ascending" is a
  /// small tax on everyone who uses the menu.
  String get ascendingLabel => switch (this) {
    LocalSort.dateAdded => 'Oldest first',
    LocalSort.duration => 'Shortest first',
    LocalSort.year => 'Oldest first',
    _ => 'A to Z',
  };

  String get descendingLabel => switch (this) {
    LocalSort.dateAdded => 'Newest first',
    LocalSort.duration => 'Longest first',
    LocalSort.year => 'Newest first',
    _ => 'Z to A',
  };

  /// Stored in Hive, so the name rather than the index — reordering the enum
  /// should not silently change someone's saved preference.
  String get key => name;

  static LocalSort fromKey(String? key) => LocalSort.values.firstWhere(
    (s) => s.name == key,
    orElse: () => LocalSort.dateAdded,
  );
}

/// Sort [songs] in place-safe fashion, returning a new list.
///
/// Ties fall back to title so the order is stable: without it, two songs from
/// the same album in an album sort swap places between rebuilds, which reads
/// as the list flickering.
List<FeedItem> sortLocalSongs(
  List<FeedItem> songs,
  Map<String, LocalTrackMeta> meta, {
  required LocalSort by,
  required bool ascending,
}) {
  int compare(FeedItem a, FeedItem b) {
    final result = switch (by) {
      LocalSort.title => _text(a.title, b.title),
      LocalSort.artist => _text(_artistOf(a), _artistOf(b)),
      LocalSort.album => _text(_albumOf(a), _albumOf(b)),
      LocalSort.duration => _int(a.duration, b.duration),
      LocalSort.year => _int(a.releaseDate, b.releaseDate),
      LocalSort.dateAdded => (meta[a.id]?.dateAdded ?? 0).compareTo(
        meta[b.id]?.dateAdded ?? 0,
      ),
    };
    if (result != 0) return result;
    return _text(a.title, b.title);
  }

  final out = [...songs]..sort(compare);
  return ascending ? out : out.reversed.toList();
}

/// Album order: disc, then track, then title for anything untagged.
///
/// Applied inside an album whatever the library sort is. MediaStore returns
/// rows newest-file-first and that order was flowing straight through, so an
/// album opened from the device library listed its songs in the order they
/// were copied onto the phone.
List<FeedItem> sortAlbumTracks(
  List<FeedItem> songs,
  Map<String, LocalTrackMeta> meta,
) {
  final out = [...songs];
  out.sort((a, b) {
    final ma = meta[a.id];
    final mb = meta[b.id];
    final disc = (ma?.disc ?? 1).compareTo(mb?.disc ?? 1);
    if (disc != 0) return disc;
    // Untagged tracks sort after numbered ones rather than jumping to the top
    // as track zero.
    final ta = (ma?.track ?? 0) == 0 ? 1 << 20 : ma!.track;
    final tb = (mb?.track ?? 0) == 0 ? 1 << 20 : mb!.track;
    if (ta != tb) return ta.compareTo(tb);
    return _text(a.title, b.title);
  });
  return out;
}

/// Case- and accent-insensitive enough for a music library, without pulling in
/// a collation package: lowercase, and leading articles ignored so "The Wall"
/// files under W.
int _text(String a, String b) => _sortKey(a).compareTo(_sortKey(b));

String _sortKey(String raw) {
  var s = raw.trim().toLowerCase();
  for (final article in const ['the ', 'a ', 'an ']) {
    if (s.startsWith(article)) {
      s = s.substring(article.length);
      break;
    }
  }
  return s;
}

int _int(String? a, String? b) =>
    (int.tryParse(a ?? '') ?? 0).compareTo(int.tryParse(b ?? '') ?? 0);

String _artistOf(FeedItem s) {
  final artists = s.artists;
  if (artists != null && artists.isNotEmpty) return artists.first.name;
  return s.subtitle ?? '';
}

String _albumOf(FeedItem s) {
  // The local mapper packs "artist · album" into the subtitle, so the album is
  // whatever follows the separator when there is one.
  final sub = s.subtitle ?? '';
  final i = sub.indexOf(' · ');
  return i >= 0 ? sub.substring(i + 3) : sub;
}
