// PodcastIndex to the app's unified FeedItem shape, ported from sunoh-api
// src/podcast/mappers.ts. Keys with no value are omitted, not null, because
// the server's JSON.stringify dropped `undefined` and dto.dart may rely on
// absence.
import '../../api/art_urls.dart';

/// PodcastIndex sends 0 / "" for missing fields; treat them as absent.
Object? _opt(Object? v) => (v == null || v == '' || v == 0) ? null : v;

void _put(Map<String, Object?> m, String k, Object? v) {
  if (v != null) m[k] = v;
}

/// Two-tier image list: `image` (small) and `artwork` (large). The same URL
/// is not repeated; one known URL yields one entry.
List<Map<String, String>> buildImages(String? image, String? artwork) {
  String? nz(String? s) => (s == null || s.isEmpty) ? null : s;
  final i = nz(image), a = nz(artwork);
  final small = i ?? a;
  // Only the large tier is upscaled: Apple-hosted art arrives as 100-600px and
  // the shows header draws it full-width. The small tier stays as sent.
  final largeRaw = a ?? i;
  final large = largeRaw == null
      ? null
      : upscaleArtUrl(largeRaw, null, null).$1;
  if (small == null && large == null) return [];
  return [
    if (small != null) {'quality': '150x150', 'link': small},
    if (large != null && large != small) {'quality': '500x500', 'link': large},
  ];
}

/// `{"55":"News","59":"Daily News"}` to `["News","Daily News"]`.
List<String>? flattenCategories(Object? raw) {
  if (raw is! Map) return null;
  final names = raw.values.whereType<String>().where((s) => s.isNotEmpty);
  return names.isEmpty ? null : names.toList();
}

String? _str(Object? v) => _opt(v) is String ? v as String : null;

/// JS `feed.id ?? feed.feedId ?? ''` stringified.
String _id(Object? a, Object? b) => '${a ?? b ?? ''}';

Map<String, Object?> mapPodcastShow(Map<String, dynamic> feed) {
  final m = <String, Object?>{
    'id': _id(feed['id'], feed['feedId']),
    'title': feed['title'] ?? feed['feedTitle'] ?? '',
  };
  _put(m, 'subtitle', _opt(feed['author']));
  _put(m, 'description', _opt(feed['description']));
  m['type'] = 'podcast';
  m['image'] = buildImages(_str(feed['image']), _str(feed['artwork']));
  _put(m, 'language', _opt(feed['language']));
  _put(m, 'categories', flattenCategories(feed['categories']));
  m['source'] = 'podcastindex';
  _put(m, 'url', _opt(feed['url'] ?? feed['link']));
  _put(m, 'itunesId', _opt(feed['itunesId']));
  return m;
}

Map<String, Object?> mapPodcastEpisode(Map<String, dynamic> item) {
  final enclosure = _opt(item['enclosureUrl']);
  final m = <String, Object?>{
    'id': _id(item['id'], item['guid']),
    'title': item['title'] ?? '',
  };
  // The show title fills the "artist" slot in the player UI.
  _put(m, 'subtitle', _opt(item['feedTitle']));
  _put(m, 'description', _opt(item['description']));
  m['type'] = 'episode';
  m['image'] = buildImages(_str(item['image']), _str(item['feedImage']));
  _put(m, 'duration', _opt(item['duration']));
  m['source'] = 'podcastindex';
  _put(m, 'url', _opt(item['link']));
  if (enclosure != null) {
    m['mediaUrls'] = [
      {'quality': 'default', 'link': enclosure},
    ];
  }
  _put(m, 'feedId', _opt(item['feedId']));
  _put(m, 'feedTitle', _opt(item['feedTitle']));
  _put(m, 'feedImage', _opt(item['feedImage']));
  _put(m, 'datePublished', _opt(item['datePublished']));
  _put(m, 'episode', _opt(item['episode']));
  _put(m, 'season', _opt(item['season']));
  if (item['explicit'] == 1 || item['explicit'] == true) m['explicit'] = true;
  _put(m, 'chaptersUrl', _opt(item['chaptersUrl']));
  _put(m, 'transcriptUrl', _opt(item['transcriptUrl']));
  return m;
}

List<Map<String, Object?>> _mapAll(
  Object? list,
  Map<String, Object?> Function(Map<String, dynamic>) f,
) => list is List
    ? [for (final e in list) f((e as Map).cast<String, dynamic>())]
    : [];

List<Map<String, Object?>> mapPodcastShows(Object? feeds) =>
    _mapAll(feeds, mapPodcastShow);

List<Map<String, Object?>> mapPodcastEpisodes(Object? items) =>
    _mapAll(items, mapPodcastEpisode);
