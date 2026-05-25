// DTOs for sunoh-api responses. These mirror the backend's unified shape
// (src/types/index.ts) — keep them in sync if the API evolves.

import 'dart:convert';

import 'package:html_unescape/html_unescape.dart';

/// HTML-entity decoder applied to user-visible text fields at parse time.
/// Saavn/Gaana sometimes return entity-escaped titles ("Mama&#39;s Boy",
/// "Tonight&amp;Tomorrow"); decoding once here keeps the UI clean.
final _htmlDecoder = HtmlUnescape();
String _decode(String s) {
  if (s.isEmpty) return s;
  // Cheap pre-check: if no entity markers, no work needed.
  if (!s.contains('&')) return s;
  return _htmlDecoder.convert(s);
}

String? _decodeNullable(Object? s) {
  if (s == null) return null;
  final str = s.toString();
  return _decode(str);
}

/// Decode the `\uXXXX` Unicode escapes that show up in some backend prose
/// (notably artist bios — `â€˜` is a smart-quote triplet).
/// Also normalises `\r\n` / `\n` literal escapes that landed in the string
/// form when an upstream stringified JSON without re-decoding.
String _decodeUnicodeEscapes(String s) {
  if (s.isEmpty) return s;
  var out = s;
  if (out.contains(r'\u')) {
    out = out.replaceAllMapped(
        RegExp(r'\\u([0-9a-fA-F]{4})'),
        (m) {
          final code = int.tryParse(m.group(1)!, radix: 16);
          return code == null ? m.group(0)! : String.fromCharCode(code);
        });
  }
  if (out.contains(r'\n') || out.contains(r'\r') || out.contains(r'\t')) {
    out = out
        .replaceAll(r'\r\n', '\n')
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\r', '\n')
        .replaceAll(r'\t', '\t');
  }
  return out;
}

/// Normalise an artist bio field. Some providers (saavn) ship `bio` as a
/// JSON array of segments — `[{text, sequence, title}]` — which lands in
/// the Map as either a real List<Map> OR a string-encoded JSON list.
/// Either way, the previous behaviour was to `toString()` it, dumping the
/// raw structure into the About panel. This unwraps to plain prose:
/// segments concatenated in sequence order, paragraph breaks between, and
/// any `\uXXXX` Unicode escapes decoded.
String? _normalizeArtistBio(Object? raw) {
  if (raw == null) return null;

  // Inline list form (parsed JSON came through as List<dynamic>).
  if (raw is List) {
    return _joinBioSegments(raw);
  }

  final str = raw.toString().trim();
  if (str.isEmpty) return null;

  // String form: detect if it starts with `[` and parses as a JSON list
  // of segment maps. If parse fails, fall through to plain-string path.
  if (str.startsWith('[')) {
    try {
      final parsed = jsonDecode(str);
      if (parsed is List) {
        final joined = _joinBioSegments(parsed);
        if (joined != null && joined.isNotEmpty) return joined;
      }
    } catch (_) {
      // Not actually JSON — treat as prose below.
    }
  }

  return _decodeUnicodeEscapes(_decode(str));
}

/// Concatenate `[{text, sequence, title}]` segments into prose. Sorts by
/// `sequence` when present so paragraphs come out in author-intended
/// order. Drops empty segments and skips the segment title — it's usually
/// just "Introduction" / "Career" labels that don't read well inline.
String? _joinBioSegments(List<dynamic> segments) {
  final entries = segments
      .whereType<Map>()
      .map((m) => m.cast<String, dynamic>())
      .where((m) => (m['text'] ?? '').toString().trim().isNotEmpty)
      .toList()
    ..sort((a, b) {
      final sa = (a['sequence'] as num?)?.toInt() ?? 0;
      final sb = (b['sequence'] as num?)?.toInt() ?? 0;
      return sa.compareTo(sb);
    });
  if (entries.isEmpty) return null;
  return entries
      .map((m) => _decodeUnicodeEscapes(_decode(m['text'].toString().trim())))
      .join('\n\n');
}

/// Envelope: `{ status, message, data, error, source }`.
class ApiEnvelope<T> {
  const ApiEnvelope({
    required this.status,
    required this.message,
    required this.data,
    this.source,
    this.error,
  });

  final String status; // 'success' | 'failed'
  final String message;
  final T? data;
  final String? source;
  final Object? error;

  bool get isSuccess => status == 'success';

  static ApiEnvelope<T> from<T>(
    Map<String, dynamic> json,
    T Function(Object? data) parseData,
  ) {
    return ApiEnvelope<T>(
      status: json['status'] as String? ?? 'failed',
      message: json['message'] as String? ?? '',
      data: parseData(json['data']),
      source: json['source'] as String?,
      error: json['error'],
    );
  }
}

/// `{ quality, link }` — one image variant.
class ApiImage {
  const ApiImage({required this.quality, required this.link});
  final String quality;
  final String link;

  factory ApiImage.fromJson(Map<String, dynamic> j) => ApiImage(
        quality: j['quality'] as String? ?? '',
        link: j['link'] as String? ?? '',
      );

  static List<ApiImage> listFrom(Object? raw) {
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((m) => ApiImage.fromJson(m.cast<String, dynamic>()))
          .toList();
    }
    if (raw is String && raw.isNotEmpty) {
      return [ApiImage(quality: 'default', link: raw)];
    }
    return const [];
  }
}

/// Minimal artist reference (as embedded inside song/album items).
class ApiArtistRef {
  const ApiArtistRef({required this.id, required this.name, this.image});
  final String id;
  final String name;
  final List<ApiImage>? image;

  factory ApiArtistRef.fromJson(Map<String, dynamic> j) => ApiArtistRef(
        id: (j['id'] ?? '').toString(),
        name: _decode((j['name'] ?? '').toString()),
        image: j['image'] == null ? null : ApiImage.listFrom(j['image']),
      );

  static List<ApiArtistRef> listFrom(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => ApiArtistRef.fromJson(m.cast<String, dynamic>()))
        .toList();
  }
}

/// A single item inside a `HomeSection.data` (or search-result section).
/// Loosely typed: the backend can emit song / album / playlist / artist /
/// channel / radio_station / occasion in the same array. UI routes on [type].
class FeedItem {
  const FeedItem({
    required this.id,
    required this.title,
    required this.type,
    required this.image,
    this.subtitle,
    this.source,
    this.language,
    this.url,
    this.duration,
    this.songCount,
    this.playCount,
    this.releaseDate,
    this.artists,
    this.token,
    this.stationType,
    this.mediaUrls = const [],
  });

  final String id;
  final String title;
  final String? subtitle;
  // 'song' | 'album' | 'playlist' | 'artist' | 'channel' | 'radio_station' |
  // 'occasion' | 'radio' (anything unknown is rendered as a generic card).
  final String type;
  final List<ApiImage> image;
  final String? source; // 'saavn' | 'gaana'
  final String? language;
  final String? url;
  final String? duration; // seconds, sometimes string
  final String? songCount;
  final String? playCount;
  final String? releaseDate;
  final List<ApiArtistRef>? artists;
  final String? token;
  /// For `type == 'radio_station'` / `'radio'`: the upstream station kind
  /// (`featured` / `artist` / `radio_station`). Required as the `type`
  /// param when initializing a radio session — the backend routes to a
  /// different station creator per kind on the source side.
  final String? stationType;
  /// Stream URLs shipped inline on song entities. Saavn labels: `12kbps` /
  /// `48kbps` / `96kbps` / `160kbps` / `320kbps`. Gaana labels: `low` /
  /// `medium` / `high` (and the URLs are signed HLS playlists that expire).
  /// Used by the StreamResolver to pick a playable URL without a round trip
  /// when the embedded list is present.
  final List<ApiImage> mediaUrls;

  /// Subtitle to show under the title on a card. Falls through:
  /// explicit subtitle → joined artist names → type-specific metadata
  /// (track count, language, release year) → a sentence-cased type label.
  /// Returns null only if literally nothing meaningful is available.
  String? get displaySubtitle {
    final fromApi = (subtitle ?? '').trim();
    if (fromApi.isNotEmpty) return fromApi;

    final names = (artists ?? const <ApiArtistRef>[])
        .map((a) => a.name.trim())
        .where((n) => n.isNotEmpty)
        .take(2)
        .toList();
    if (names.isNotEmpty) return names.join(', ');

    switch (type) {
      case 'song':
        final yr = (releaseDate ?? '').trim();
        return yr.isEmpty ? (language ?? 'Song') : yr;
      case 'album':
        final yr = (releaseDate ?? '').trim();
        return yr.isEmpty ? (language ?? 'Album') : yr;
      case 'playlist':
        final n = (songCount ?? '').trim();
        return n.isEmpty ? 'Playlist' : '$n tracks';
      case 'channel':
      case 'radio_station':
      case 'radio':
        final lang = (language ?? '').trim();
        return lang.isEmpty ? 'Radio' : lang;
      case 'artist':
        return null; // artists render as circles without a subtitle
      case 'occasion':
        return 'Mood';
      default:
        // Fallback: humanize the type ('radio_station' → 'Radio station').
        if (type.isEmpty) return null;
        final cleaned = type.replaceAll('_', ' ');
        return cleaned[0].toUpperCase() + cleaned.substring(1);
    }
  }

  /// Best-effort artwork URL — pick the highest-quality image, else the first.
  String? get artwork {
    if (image.isEmpty) return null;
    // Pick the largest dimension if quality strings are like '500x500'.
    int score(String q) {
      final m = RegExp(r'(\d+)').firstMatch(q);
      return m == null ? 0 : int.tryParse(m.group(1)!) ?? 0;
    }

    final sorted = [...image]..sort((a, b) => score(b.quality).compareTo(score(a.quality)));
    return sorted.first.link;
  }

  factory FeedItem.fromJson(Map<String, dynamic> j) => FeedItem(
        id: (j['id'] ?? '').toString(),
        title: _decode((j['title'] ?? j['name'] ?? '').toString()),
        subtitle: _decodeNullable(j['subtitle']),
        type: (j['type'] ?? 'unknown').toString(),
        image: ApiImage.listFrom(j['image']),
        // Some endpoints emit `provider` instead of `source`; treat them as
        // equivalents (RN mirrors this).
        source: (j['source'] ?? j['provider'])?.toString(),
        language: _decodeNullable(j['language']),
        url: j['url']?.toString(),
        duration: j['duration']?.toString(),
        songCount: j['songCount']?.toString(),
        playCount: j['playCount']?.toString(),
        releaseDate: j['releaseDate']?.toString(),
        artists: j['artists'] == null ? null : ApiArtistRef.listFrom(j['artists']),
        token: j['token']?.toString(),
        stationType: j['stationType']?.toString(),
        mediaUrls: ApiImage.listFrom(j['mediaUrls']),
      );

  /// Serialize for local persistence. Used by `PlaybackStateStore` to save
  /// the last queue + current track across sessions.
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        if (subtitle != null) 'subtitle': subtitle,
        'type': type,
        'image': image.map((i) => {'quality': i.quality, 'link': i.link}).toList(),
        if (source != null) 'source': source,
        if (language != null) 'language': language,
        if (url != null) 'url': url,
        if (duration != null) 'duration': duration,
        if (songCount != null) 'songCount': songCount,
        if (playCount != null) 'playCount': playCount,
        if (releaseDate != null) 'releaseDate': releaseDate,
        if (artists != null)
          'artists': artists!.map((a) => {
                'id': a.id,
                'name': a.name,
                if (a.image != null)
                  'image': a.image!
                      .map((i) => {'quality': i.quality, 'link': i.link})
                      .toList(),
              }).toList(),
        if (token != null) 'token': token,
        if (stationType != null) 'stationType': stationType,
        // Note: we deliberately DON'T persist `mediaUrls` — for gaana those
        // are signed and expire, and saavn ones may be stale too. The
        // StreamResolver will re-resolve on play.
      };
}

/// One section in the home feed.
class HomeSection {
  const HomeSection({
    required this.heading,
    required this.items,
    this.source,
  });

  final String heading;
  final List<FeedItem> items;
  final String? source;

  factory HomeSection.fromJson(Map<String, dynamic> j) => HomeSection(
        heading: _decode((j['heading'] ?? '').toString()),
        source: j['source']?.toString(),
        items: (j['data'] is List)
            ? (j['data'] as List)
                .whereType<Map>()
                .map((m) => FeedItem.fromJson(m.cast<String, dynamic>()))
                .toList()
            : const [],
      );
}

// ── Detail DTOs ─────────────────────────────────────────────────────────────

/// A single song result (track row in album/playlist/artist top-tracks). We
/// reuse [FeedItem] for these since the API ships songs in the same shape —
/// keeping one model avoids duplicate parsing.
typedef ApiSong = FeedItem;

class AlbumDetail {
  const AlbumDetail({
    required this.id,
    required this.title,
    required this.image,
    required this.artists,
    required this.songs,
    required this.sections,
    this.subtitle,
    this.year,
    this.songCount,
    this.releaseDate,
    this.language,
    this.description,
    this.source,
  });

  final String id;
  final String title;
  final String? subtitle;
  final String? year;
  final String? songCount;
  final String? releaseDate;
  final String? language;
  final String? description;
  final String? source;
  final List<ApiImage> image;
  final List<ApiArtistRef> artists;
  final List<ApiSong> songs;
  /// Related/recommended sections the API ships alongside an album (other
  /// albums by the same artist, "Listeners also enjoyed", etc.).
  final List<HomeSection> sections;

  String? get artwork {
    if (image.isEmpty) return null;
    final sorted = [...image];
    int score(String q) {
      final m = RegExp(r'(\d+)').firstMatch(q);
      return m == null ? 0 : int.tryParse(m.group(1)!) ?? 0;
    }
    sorted.sort((a, b) => score(b.quality).compareTo(score(a.quality)));
    return sorted.first.link;
  }

  /// "Aerial Trust · 2024 · 8 tracks" — best-effort metadata line.
  String get metaLine {
    final parts = <String>[];
    if (artists.isNotEmpty) {
      parts.add(artists.take(2).map((a) => a.name).where((n) => n.isNotEmpty).join(', '));
    }
    if ((year ?? '').isNotEmpty) {
      parts.add(year!);
    } else if ((releaseDate ?? '').isNotEmpty) {
      parts.add(releaseDate!);
    }
    if ((songCount ?? '').isNotEmpty) parts.add('$songCount tracks');
    return parts.join(' · ');
  }

  factory AlbumDetail.fromJson(Map<String, dynamic> j) {
    // Provider response-shape normalization. Saavn ships flat at `data`,
    // gaana wraps the entity one level deeper as `data.album` with sections
    // alongside it at the outer level. Mirror RN's
    // `data?.album || data?.playlist || data` precedence.
    final inner = (j['album'] is Map)
        ? (j['album'] as Map).cast<String, dynamic>()
        : (j['playlist'] is Map)
            ? (j['playlist'] as Map).cast<String, dynamic>()
            : j;
    // Sections can live either alongside the wrapper (gaana albums) or
    // inside the inner object (saavn).
    final sectionsRaw = j['sections'] ?? inner['sections'];
    return AlbumDetail(
      id: (inner['id'] ?? '').toString(),
      title: _decode((inner['title'] ?? inner['name'] ?? '').toString()),
      subtitle: _decodeNullable(inner['subtitle']),
      year: inner['year']?.toString(),
      songCount: inner['songCount']?.toString(),
      releaseDate: inner['releaseDate']?.toString(),
      language: _decodeNullable(inner['language']),
      description: _decodeNullable(inner['description'] ?? inner['headerDesc']),
      source: inner['source']?.toString(),
      image: ApiImage.listFrom(inner['image']),
      artists: ApiArtistRef.listFrom(inner['artists']),
      songs: _feedItemList(inner['songs']),
      sections: _sectionList(sectionsRaw),
    );
  }
}

List<FeedItem> _feedItemList(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((m) => FeedItem.fromJson(m.cast<String, dynamic>()))
      .toList();
}

List<HomeSection> _sectionList(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((m) => HomeSection.fromJson(m.cast<String, dynamic>()))
      .where((s) => s.items.isNotEmpty)
      .toList();
}

class PlaylistDetail {
  const PlaylistDetail({
    required this.id,
    required this.title,
    required this.image,
    required this.songs,
    required this.sections,
    this.subtitle,
    this.songCount,
    this.followers,
    this.description,
    this.source,
  });

  final String id;
  final String title;
  final String? subtitle;
  final String? songCount;
  final String? followers;
  final String? description;
  final String? source;
  final List<ApiImage> image;
  final List<ApiSong> songs;
  /// Related/recommended sections shipped alongside a playlist.
  final List<HomeSection> sections;

  String? get artwork {
    if (image.isEmpty) return null;
    final sorted = [...image];
    int score(String q) {
      final m = RegExp(r'(\d+)').firstMatch(q);
      return m == null ? 0 : int.tryParse(m.group(1)!) ?? 0;
    }
    sorted.sort((a, b) => score(b.quality).compareTo(score(a.quality)));
    return sorted.first.link;
  }

  String get metaLine {
    final parts = <String>[];
    if ((subtitle ?? '').isNotEmpty) parts.add(subtitle!);
    if ((songCount ?? '').isNotEmpty) parts.add('$songCount tracks');
    if ((followers ?? '').isNotEmpty) parts.add('$followers followers');
    return parts.join(' · ');
  }

  factory PlaylistDetail.fromJson(Map<String, dynamic> j) {
    // Gaana wraps playlists as `data.playlist`; saavn ships flat.
    final inner = (j['playlist'] is Map)
        ? (j['playlist'] as Map).cast<String, dynamic>()
        : (j['album'] is Map)
            ? (j['album'] as Map).cast<String, dynamic>()
            : j;
    final sectionsRaw = j['sections'] ?? inner['sections'];
    return PlaylistDetail(
      id: (inner['id'] ?? '').toString(),
      title: _decode((inner['title'] ?? inner['name'] ?? '').toString()),
      subtitle: _decodeNullable(inner['subtitle']),
      songCount: inner['songCount']?.toString(),
      followers: inner['followers']?.toString(),
      description: _decodeNullable(inner['description']),
      source: inner['source']?.toString(),
      image: ApiImage.listFrom(inner['image']),
      songs: _feedItemList(inner['songs']),
      sections: _sectionList(sectionsRaw),
    );
  }
}

class ArtistDetail {
  const ArtistDetail({
    required this.id,
    required this.name,
    required this.image,
    required this.topSongs,
    required this.albums,
    required this.sections,
    this.subtitle,
    this.role,
    this.followers,
    this.bio,
    this.songCount,
    this.albumCount,
    this.source,
  });

  final String id;
  final String name;
  final String? subtitle;
  final String? role;
  final String? followers;
  final String? bio;
  final String? songCount;
  final String? albumCount;
  final String? source;
  final List<ApiImage> image;
  final List<ApiSong> topSongs;
  final List<FeedItem> albums; // discography entries
  /// All other sections (related artists, featured-in playlists, etc.) the
  /// API ships under the artist endpoint. topSongs/albums are extracted from
  /// these for the dedicated UI slots — the rest renders as `_RelatedSection`.
  final List<HomeSection> sections;

  String? get artwork {
    if (image.isEmpty) return null;
    final sorted = [...image];
    int score(String q) {
      final m = RegExp(r'(\d+)').firstMatch(q);
      return m == null ? 0 : int.tryParse(m.group(1)!) ?? 0;
    }
    sorted.sort((a, b) => score(b.quality).compareTo(score(a.quality)));
    return sorted.first.link;
  }

  factory ArtistDetail.fromJson(Map<String, dynamic> j) {
    // Some providers can wrap the entity (saavn-flat vs gaana-nested).
    final inner = (j['artist'] is Map)
        ? (j['artist'] as Map).cast<String, dynamic>()
        : j;

    List<FeedItem> listFrom(Object? raw) {
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((m) => FeedItem.fromJson(m.cast<String, dynamic>()))
          .toList();
    }

    // Parse all sections (live API ships top songs / discography / related
    // here, not as top-level fields).
    final allSections = _sectionList(inner['sections']);

    // Extract topSongs + discography from named sections. Match liberally
    // by heading so naming differences across providers don't break us.
    bool matchesHeading(String h, List<String> needles) {
      final low = h.toLowerCase();
      return needles.any((n) => low.contains(n));
    }

    HomeSection? findFirst(bool Function(HomeSection) test) {
      for (final s in allSections) {
        if (test(s)) return s;
      }
      return null;
    }

    final songsSection = findFirst((s) =>
        matchesHeading(s.heading, ['top song', 'popular', 'hit song']) &&
        s.items.any((it) => it.type == 'song'));
    final albumsSection = findFirst((s) =>
        matchesHeading(s.heading, ['album', 'discography']) &&
        s.items.any((it) => it.type == 'album'));

    // Anything left over (related artists, featured-in, etc.) renders as
    // related rows below the artist's content.
    final leftover = allSections.where((s) {
      if (songsSection != null && identical(s, songsSection)) return false;
      if (albumsSection != null && identical(s, albumsSection)) return false;
      return s.items.isNotEmpty;
    }).toList();

    // Top-level fallbacks for providers that still emit topSongs/topAlbums
    // directly (legacy / non-unified paths).
    final topRaw =
        inner['topSongs'] ?? inner['top_songs'] ?? inner['songs'];
    final albumsRaw =
        inner['topAlbums'] ?? inner['top_albums'] ?? inner['albums'];

    final topSongs = songsSection != null
        ? songsSection.items.where((it) => it.type == 'song').toList()
        : listFrom(topRaw);
    final albums = albumsSection != null
        ? albumsSection.items.where((it) => it.type == 'album').toList()
        : listFrom(albumsRaw);

    return ArtistDetail(
      id: (inner['id'] ?? '').toString(),
      name: _decode((inner['name'] ?? inner['title'] ?? '').toString()),
      subtitle: _decodeNullable(inner['subtitle']),
      role: _decodeNullable(inner['role']),
      followers: inner['followers']?.toString(),
      bio: _normalizeArtistBio(inner['bio']),
      songCount: inner['songCount']?.toString(),
      albumCount: inner['albumCount']?.toString(),
      source: inner['source']?.toString(),
      image: ApiImage.listFrom(inner['image']),
      topSongs: topSongs,
      albums: albums,
      sections: leftover,
    );
  }
}
