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
