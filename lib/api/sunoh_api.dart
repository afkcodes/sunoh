// Typed sunoh-api service. Wraps the Dio client + DTO mapping.

import 'package:dio/dio.dart';

import 'dto.dart';

class SunohApi {
  SunohApi(this._dio);
  final Dio _dio;

  /// `GET /music/home` — unified merged home feed.
  /// [languages] is an optional comma-separated list (e.g. 'hindi,english').
  Future<List<HomeSection>> fetchHome({String? languages}) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/music/home',
      queryParameters: {
        if (languages != null && languages.isNotEmpty) 'lang': languages,
      },
    );
    final env = ApiEnvelope.from<List<HomeSection>>(
      res.data ?? const {},
      (raw) => (raw is List)
          ? raw
              .whereType<Map>()
              .map((m) => HomeSection.fromJson(m.cast<String, dynamic>()))
              .toList()
          : const <HomeSection>[],
    );
    if (!env.isSuccess) {
      throw SunohApiException(env.message, env.error);
    }
    return env.data ?? const [];
  }

  /// `GET /music/album/:id` — album details + tracks.
  Future<AlbumDetail> fetchAlbum(String id, {String? provider}) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/music/album/$id',
      queryParameters: {
        if (provider != null && provider.isNotEmpty) 'provider': provider,
      },
    );
    final env = ApiEnvelope.from<AlbumDetail?>(
      res.data ?? const {},
      (raw) =>
          raw is Map ? AlbumDetail.fromJson(raw.cast<String, dynamic>()) : null,
    );
    if (!env.isSuccess || env.data == null) {
      throw SunohApiException(env.message, env.error);
    }
    return env.data!;
  }

  /// `GET /music/playlist/:id` — playlist details + tracks.
  Future<PlaylistDetail> fetchPlaylist(String id, {String? provider}) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/music/playlist/$id',
      queryParameters: {
        if (provider != null && provider.isNotEmpty) 'provider': provider,
      },
    );
    final env = ApiEnvelope.from<PlaylistDetail?>(
      res.data ?? const {},
      (raw) => raw is Map
          ? PlaylistDetail.fromJson(raw.cast<String, dynamic>())
          : null,
    );
    if (!env.isSuccess || env.data == null) {
      throw SunohApiException(env.message, env.error);
    }
    return env.data!;
  }

  /// `GET /music/search?query=` — trending search payload. Same endpoint
  /// as [fetchSearch] but called with an empty `query` param (note: NOT
  /// `q` — backend distinguishes between query-typed search (`q`) and
  /// trending browse (`query=`)). Returns sections that we render as
  /// horizontal carousels in the search screen's browse view.
  Future<List<HomeSection>> fetchTrendingSearch() async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/music/search',
      queryParameters: const {'query': ''},
    );
    final env = ApiEnvelope.from<List<HomeSection>>(
      res.data ?? const {},
      (raw) => (raw is List)
          ? raw
              .whereType<Map>()
              .map((m) => HomeSection.fromJson(m.cast<String, dynamic>()))
              .toList()
          : const <HomeSection>[],
    );
    if (!env.isSuccess) {
      throw SunohApiException(env.message, env.error);
    }
    return env.data ?? const [];
  }

  /// `GET /music/occasions/:slug?provider=gaana` — full contents of an
  /// occasion category. Returns `List<HomeSection>` (sections of playlists
  /// / songs / albums) using the same shape as `/music/home`.
  Future<List<HomeSection>> fetchOccasionDetail(
    String slug, {
    String provider = 'gaana',
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/music/occasions/$slug',
      queryParameters: {
        if (provider.isNotEmpty) 'provider': provider,
      },
    );
    final env = ApiEnvelope.from<List<HomeSection>>(
      res.data ?? const {},
      (raw) => (raw is List)
          ? raw
              .whereType<Map>()
              .map((m) => HomeSection.fromJson(m.cast<String, dynamic>()))
              .toList()
          : const <HomeSection>[],
    );
    if (!env.isSuccess) {
      throw SunohApiException(env.message, env.error);
    }
    return env.data ?? const [];
  }

  /// `GET /music/occasions?provider=gaana` — browse categories ("Workout",
  /// "Romance", etc.). Each item carries an artwork URL + slug for the
  /// occasion detail view. Re-uses [FeedItem.fromJson] — the occasion
  /// shape is a strict subset (id / title / image / url-as-slug / type).
  Future<List<FeedItem>> fetchOccasions({String provider = 'gaana'}) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/music/occasions',
      queryParameters: {
        if (provider.isNotEmpty) 'provider': provider,
      },
    );
    final env = ApiEnvelope.from<List<FeedItem>>(
      res.data ?? const {},
      (raw) {
        // Backend has shipped occasions both as a flat `data: [...]` array
        // and as a wrapped `data: { occasions: [...] }`. Handle both.
        if (raw is List) {
          return raw
              .whereType<Map>()
              .map((m) => FeedItem.fromJson(m.cast<String, dynamic>()))
              .toList();
        }
        if (raw is Map) {
          final inner = raw['occasions'];
          if (inner is List) {
            return inner
                .whereType<Map>()
                .map((m) => FeedItem.fromJson(m.cast<String, dynamic>()))
                .toList();
          }
        }
        return const <FeedItem>[];
      },
    );
    if (!env.isSuccess) {
      throw SunohApiException(env.message, env.error);
    }
    return env.data ?? const [];
  }

  /// `GET /music/radio/session?id=…&type=…&provider=…` — initialize a
  /// radio station session and return the opaque station id we then
  /// fetch songs from. `type` is the station's `stationType` field
  /// (`featured` / `artist` / `radio_station` typically) — the backend
  /// uses it to route to the right station creator on the source side.
  Future<String?> fetchRadioSession({
    required String id,
    required String type,
    required String provider,
    String? name,
    String? lang,
  }) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/music/radio/session',
        queryParameters: {
          'id': id,
          'type': type,
          'provider': provider,
          if (name != null && name.isNotEmpty) 'name': name,
          if (lang != null && lang.isNotEmpty) 'lang': lang,
        },
      );
      final body = res.data;
      if (body == null) return null;
      final data = body['data'];
      if (data is! Map) return null;
      return (data['stationId'] ?? data['sessionId'])?.toString();
    } on DioException catch (_) {
      return null;
    }
  }

  /// `GET /music/radio/:stationId?count=…` — pull the next batch of
  /// songs for a radio session. Returns a flat list of FeedItems with
  /// type='song' and full metadata (artists, duration, mediaUrls all
  /// populated).
  Future<List<FeedItem>> fetchRadioSongs(
    String stationId, {
    int count = 20,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/music/radio/$stationId',
      queryParameters: {'count': count},
    );
    final env = ApiEnvelope.from<List<FeedItem>>(
      res.data ?? const {},
      (raw) {
        // `data.list` is the shape this endpoint actually ships.
        if (raw is Map) {
          final list = raw['list'];
          if (list is List) {
            return list
                .whereType<Map>()
                .map((m) => FeedItem.fromJson(m.cast<String, dynamic>()))
                .toList();
          }
        }
        if (raw is List) {
          return raw
              .whereType<Map>()
              .map((m) => FeedItem.fromJson(m.cast<String, dynamic>()))
              .toList();
        }
        return const <FeedItem>[];
      },
    );
    if (!env.isSuccess) {
      throw SunohApiException(env.message, env.error);
    }
    return env.data ?? const [];
  }

  /// `GET /music/song/:id?provider=…` — full song detail (artists,
  /// duration, subtitle, album, mediaUrls). Used by AppState to enrich
  /// FeedItems that arrived from search (which returns them with
  /// `artists: []` and `duration: null` — see the curl spelunking in
  /// 2026-05-23) so the player can show real artist names + the
  /// scrubber gets the correct total length.
  ///
  /// Returns `null` when the lookup fails — enrichment is best-effort,
  /// the caller should keep the original FeedItem on failure.
  Future<FeedItem?> fetchSong(String id, {String? provider}) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/music/song/$id',
        queryParameters: {
          if (provider != null && provider.isNotEmpty) 'provider': provider,
        },
      );
      final body = res.data;
      if (body == null) return null;
      final raw = body['data'];
      if (raw is! Map) return null;
      // Backend ships both shapes: flat (`data` is the song) and gaana-
      // nested (`data.song`).
      final inner = (raw['song'] is Map)
          ? (raw['song'] as Map).cast<String, dynamic>()
          : raw.cast<String, dynamic>();
      return FeedItem.fromJson(inner);
    } on DioException catch (_) {
      return null;
    }
  }

  /// `GET /music/search?q=…&type=all` — unified search. Returns a list of
  /// sections (`Top Results`, `Songs`, `Albums`, `Artists`, `Playlists`)
  /// using the same shape as `/music/home` so we re-use [HomeSection.fromJson].
  ///
  /// Backend expects the query under `q` (not `query`). `type=all` returns
  /// the section list; `type=songs` returns `data.list` flat (we don't use
  /// that path here — UI wants the grouped view).
  ///
  /// Default provider is `unified` — gives both saavn (Songs section) +
  /// gaana (Top Results with populated artist/subtitle fields). Saavn-only
  /// search returns songs with empty `artists` + null `subtitle`; unified's
  /// Top Results carries the rich gaana data.
  Future<List<HomeSection>> fetchSearch(
    String query, {
    String? languages,
    String provider = 'unified',
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/music/search',
      queryParameters: {
        'q': query,
        'type': 'all',
        if (provider.isNotEmpty) 'provider': provider,
        if (languages != null && languages.isNotEmpty) 'lang': languages,
      },
    );
    final env = ApiEnvelope.from<List<HomeSection>>(
      res.data ?? const {},
      (raw) => (raw is List)
          ? raw
              .whereType<Map>()
              .map((m) => HomeSection.fromJson(m.cast<String, dynamic>()))
              .toList()
          : const <HomeSection>[],
    );
    if (!env.isSuccess) {
      throw SunohApiException(env.message, env.error);
    }
    return env.data ?? const [];
  }

  /// `GET /music/artist/:id` — artist info + top songs + discography.
  Future<ArtistDetail> fetchArtist(String id, {String? provider}) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/music/artist/$id',
      queryParameters: {
        if (provider != null && provider.isNotEmpty) 'provider': provider,
      },
    );
    final env = ApiEnvelope.from<ArtistDetail?>(
      res.data ?? const {},
      (raw) =>
          raw is Map ? ArtistDetail.fromJson(raw.cast<String, dynamic>()) : null,
    );
    if (!env.isSuccess || env.data == null) {
      throw SunohApiException(env.message, env.error);
    }
    return env.data!;
  }
}

class SunohApiException implements Exception {
  SunohApiException(this.message, [this.error]);
  final String message;
  final Object? error;
  @override
  String toString() => 'SunohApiException: $message';
}
