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
