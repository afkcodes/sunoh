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

  /// `GET /music/recommend?q=…&songId=…&lang=…` — aggregated song
  /// recommendations from Saavn (reco.getreco + sections + similar
  /// songs + a derived radio station, all merged and deduped by the
  /// backend). Either [songId] (a known Saavn id) or [query] (a search
  /// string) is sufficient; both can be passed. The response already
  /// filters the seed and dedupes against itself, so callers can append
  /// the returned list straight to the queue.
  ///
  /// Used by the endless-autoplay primer in AppState; this single
  /// endpoint replaces the older `radio/session` + `radio/<id>` two-
  /// step which sometimes returned `data: []` for Gaana seeds and
  /// required a client-side Saavn pivot.
  Future<List<FeedItem>> fetchRecommendations({
    String? songId,
    String? query,
    String? lang,
  }) async {
    final params = <String, dynamic>{
      if (songId != null && songId.isNotEmpty) 'songId': songId,
      if (query != null && query.isNotEmpty) 'q': query,
      if (lang != null && lang.isNotEmpty) 'lang': lang,
    };
    final res = await _dio.get<Map<String, dynamic>>(
      '/music/recommend',
      queryParameters: params,
      options: Options(validateStatus: (_) => true),
    );
    // ignore: avoid_print
    print('[recommend] HTTP ${res.statusCode} '
        'q="${query ?? ''}" songId="${songId ?? ''}"');
    final env = ApiEnvelope.from<List<FeedItem>>(
      res.data ?? const {},
      (raw) {
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

  /// `GET /music/radio/:stationId?count=…` — pull the next batch of
  /// songs for a radio session. Returns a flat list of FeedItems with
  /// type='song' and full metadata (artists, duration, mediaUrls all
  /// populated).
  Future<List<FeedItem>> fetchRadioSongs(
    String stationId, {
    int count = 20,
  }) async {
    // URL-encode the station id — saavn returns ids like
    // `saavn_~^~artist_radio~^~459320` for artist stations. `^` is
    // outside the RFC 3986 URI character set; `~` is unreserved but
    // encoding it doesn't hurt.
    //
    // Also: don't throw on non-2xx so we can surface the error body in
    // logs. Saavn upstream sometimes returns 400 with a useful message
    // (e.g. "stationid is malformed") that we'd otherwise discard.
    // `next=1` matches RN's call shape — the upstream endpoint expects
    // it for pagination even on the first page.
    final res = await _dio.get<Map<String, dynamic>>(
      '/music/radio/${Uri.encodeComponent(stationId)}',
      queryParameters: {'count': count, 'next': 1},
      options: Options(validateStatus: (_) => true),
    );
    // ignore: avoid_print
    print('[radio] songs HTTP ${res.statusCode} body=${res.data}');
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

  /// `GET /music/languages` — the user-selectable music languages list.
  /// Returns rows like `{name: 'Hindi', value: 'hindi'}`. Used to populate
  /// the Settings → Music Languages picker; the `value` is what the
  /// backend expects in the `lang=` query for `/music/home`,
  /// `/music/radio/*`, etc.
  Future<List<ApiLanguage>> fetchLanguages() async {
    final res = await _dio.get<Map<String, dynamic>>('/music/languages');
    final env = ApiEnvelope.from<List<ApiLanguage>>(
      res.data ?? const {},
      (raw) {
        if (raw is! List) return const <ApiLanguage>[];
        return raw
            .whereType<Map>()
            .map((m) => ApiLanguage.fromJson(m.cast<String, dynamic>()))
            .toList();
      },
    );
    if (!env.isSuccess) {
      throw SunohApiException(env.message, env.error);
    }
    return env.data ?? const [];
  }

  // ── Podcasts ──────────────────────────────────────────────────────────
  //
  // The backend wraps PodcastIndex behind /podcasts/* and maps every
  // shape into FeedItem (with `type: 'podcast'` for shows, `'episode'`
  // for episodes). All these helpers parse the standard envelope and
  // return FeedItem-typed data — no provider-specific branching needed
  // on the call sites.

  /// `GET /podcasts/home?country=XX` — aggregated multi-section feed
  /// for the Podcasts tab. Returns the unified HomeSection list shape;
  /// `country` is forwarded verbatim, the backend falls back to its
  /// own detection (IP-geo + CF header + Accept-Language) when omitted.
  Future<List<HomeSection>> fetchPodcastHome({String? country}) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/podcasts/home',
      queryParameters: {
        if (country != null && country.isNotEmpty) 'country': country,
      },
    );
    final env = ApiEnvelope.from<List<HomeSection>>(
      res.data ?? const {},
      (raw) => raw is List
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

  /// `GET /podcasts/:id?max=N` — show metadata + first page of episodes
  /// in one round trip.
  Future<PodcastShowDetail> fetchPodcastShow(String id, {int max = 30}) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/podcasts/${Uri.encodeComponent(id)}',
      queryParameters: {'max': max},
    );
    final env = ApiEnvelope.from<PodcastShowDetail?>(
      res.data ?? const {},
      (raw) => raw is Map
          ? PodcastShowDetail.fromJson(raw.cast<String, dynamic>())
          : null,
    );
    if (!env.isSuccess || env.data == null) {
      throw SunohApiException(env.message, env.error);
    }
    return env.data!;
  }

  /// `GET /podcasts/:id/episodes?max=&since=` — paginated episode list.
  /// Pass `since` (unix-seconds) for incremental loads — `null` = newest.
  Future<List<FeedItem>> fetchPodcastEpisodes(
    String showId, {
    int max = 50,
    int? since,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/podcasts/${Uri.encodeComponent(showId)}/episodes',
      queryParameters: {
        'max': max,
        'since': ?since,
      },
    );
    final env = ApiEnvelope.from<List<FeedItem>>(
      res.data ?? const {},
      (raw) {
        if (raw is Map) {
          final list = raw['list'];
          if (list is List) {
            return list
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

  /// `GET /podcasts/episode/:guid` — single-episode lookup. The
  /// backend also accepts `?id=` for numeric ids (used as a fallback
  /// when the guid lookup misses).
  Future<FeedItem?> fetchPodcastEpisode(String guidOrId) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/podcasts/episode/${Uri.encodeComponent(guidOrId)}',
    );
    final env = ApiEnvelope.from<FeedItem?>(
      res.data ?? const {},
      (raw) => raw is Map ? FeedItem.fromJson(raw.cast<String, dynamic>()) : null,
    );
    if (!env.isSuccess) {
      throw SunohApiException(env.message, env.error);
    }
    return env.data;
  }

  /// `GET /podcasts/search?q=…&max=N` — full-text podcast search.
  /// Returns shows only (episodes don't ship via this endpoint).
  Future<List<FeedItem>> fetchPodcastSearch(
    String query, {
    int max = 30,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/podcasts/search',
      queryParameters: {'q': query, 'max': max},
    );
    final env = ApiEnvelope.from<List<FeedItem>>(
      res.data ?? const {},
      (raw) {
        if (raw is Map) {
          final list = raw['list'];
          if (list is List) {
            return list
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

  /// `GET /podcasts/categories` — the full PodcastIndex taxonomy
  /// (~112 entries). Stable; the categories provider caches for 24h.
  Future<List<PodcastCategory>> fetchPodcastCategories() async {
    final res = await _dio.get<Map<String, dynamic>>('/podcasts/categories');
    final env = ApiEnvelope.from<List<PodcastCategory>>(
      res.data ?? const {},
      (raw) {
        if (raw is Map) {
          final list = raw['list'];
          if (list is List) {
            return list
                .whereType<Map>()
                .map(
                  (m) => PodcastCategory.fromJson(m.cast<String, dynamic>()),
                )
                .toList();
          }
        }
        return const <PodcastCategory>[];
      },
    );
    if (!env.isSuccess) {
      throw SunohApiException(env.message, env.error);
    }
    return env.data ?? const [];
  }

  /// `GET /podcasts/by-category/:slug?max=N&lang=…` — shows in a
  /// category. The `slug` param accepts either the category name
  /// ("News") or its numeric id ("55"); the categories provider
  /// surfaces both so callers can pick.
  Future<List<FeedItem>> fetchPodcastsByCategory(
    String slug, {
    int max = 30,
    String? lang,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/podcasts/by-category/${Uri.encodeComponent(slug)}',
      queryParameters: {
        'max': max,
        if (lang != null && lang.isNotEmpty) 'lang': lang,
      },
    );
    final env = ApiEnvelope.from<List<FeedItem>>(
      res.data ?? const {},
      (raw) {
        if (raw is Map) {
          final list = raw['list'];
          if (list is List) {
            return list
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

  /// `GET /spotify/import?url=…` — paste a Spotify playlist URL, get
  /// the mapped result back. The backend scrapes Spotify (~80 s for a
  /// 300-track playlist), matches each track against Saavn, and
  /// returns the merged envelope.
  ///
  /// We override the receive timeout to 180 s because the default
  /// (20 s) is far below this endpoint's worst case. The Cloudflare
  /// edge times out at ~100 s, so very-large playlists will still cut
  /// out at the network layer regardless of what we set here — but for
  /// the common <500-track case 180 s gives plenty of headroom.
  Future<SpotifyImportResult> importSpotifyPlaylist(String spotifyUrl) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/spotify/import',
      queryParameters: {'url': spotifyUrl},
      options: Options(receiveTimeout: const Duration(seconds: 180)),
    );
    final env = ApiEnvelope.from<SpotifyImportResult?>(
      res.data ?? const {},
      (raw) => raw is Map
          ? SpotifyImportResult.fromJson(raw.cast<String, dynamic>())
          : null,
    );
    if (!env.isSuccess || env.data == null) {
      throw SunohApiException(env.message, env.error);
    }
    return env.data!;
  }

  /// `GET /radios/search?q=…&country=…&limit=…` — full-text search over
  /// the sunoh-radio catalog. Returns FeedItems with type=`radio_station`,
  /// `stationType=live`, and `mediaUrls[0].link` = stream URL ready for
  /// the resolver's tier-1 inline pickup.
  Future<List<FeedItem>> fetchRadioSearch(
    String query, {
    int limit = 30,
    String? country,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/radios/search',
      queryParameters: {
        'q': query,
        'limit': limit,
        if (country != null && country.isNotEmpty) 'country': country,
      },
    );
    final env = ApiEnvelope.from<List<FeedItem>>(
      res.data ?? const {},
      (raw) {
        if (raw is Map) {
          final list = raw['list'];
          if (list is List) {
            return list
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
}

class SunohApiException implements Exception {
  SunohApiException(this.message, [this.error]);
  final String message;
  final Object? error;
  @override
  String toString() => 'SunohApiException: $message';
}
