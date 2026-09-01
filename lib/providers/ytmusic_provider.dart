// Riverpod wiring for the YouTube Music tier.
//
// Search/browse go straight to InnerTube over HTTP (see ytmusic_api.dart);
// only stream resolution crosses the platform channel.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dto.dart';
import '../api/yt_locale.dart';
import '../api/ytmusic_api.dart';
import 'app_state_provider.dart';
import 'yt_auth_provider.dart';

/// A Dio dedicated to music.youtube.com.
///
/// Deliberately NOT the shared sunoh-api client: that one carries our base
/// URL and API-specific headers, and none of those belong on a request to
/// Google. Timeouts are generous — InnerTube browse responses run to several
/// hundred KB.
final _ytDioProvider = Provider<Dio>((ref) {
  return Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      responseType: ResponseType.json,
    ),
  );
});

final ytLocaleResolverProvider = Provider<YtLocaleResolver>(
  (ref) => YtLocaleResolver(ref.watch(_ytDioProvider)),
);

/// The region/language every YouTube request is made for.
///
/// Watches AppState so flipping the override in Settings rebuilds the API
/// client, and the autoDispose feed providers below re-fetch against the
/// new region rather than serving a stale country's charts.
final ytLocaleProvider = Provider<YtLocale>((ref) {
  final s = ref.watch(appStateProvider);
  return ref
      .watch(ytLocaleResolverProvider)
      .resolve(
        countryOverride: s.ytCountryOverride,
        languageOverride: s.ytLanguageOverride,
      );
});

final ytMusicApiProvider = Provider<YtMusicApi>(
  (ref) => YtMusicApi(
    ref.watch(_ytDioProvider),
    locale: ref.watch(ytLocaleProvider),
  ),
);

/// Song results, merged into the Search screen. Failure degrades to an
/// absent section rather than an error state.
final ytMusicSearchProvider = FutureProvider.autoDispose
    .family<List<FeedItem>, String>((ref, query) {
      if (query.trim().isEmpty) return Future.value(const <FeedItem>[]);
      return ref.watch(ytMusicApiProvider).searchSongs(query);
    });

/// Artist results, merged into Search so an artist page is reachable by
/// searching for the artist — the obvious entry point.
final ytMusicArtistSearchProvider = FutureProvider.autoDispose
    .family<List<FeedItem>, String>((ref, query) {
      if (query.trim().isEmpty) return Future.value(const <FeedItem>[]);
      return ref.watch(ytMusicApiProvider).searchArtists(query);
    });

/// Album results.
final ytMusicAlbumSearchProvider = FutureProvider.autoDispose
    .family<List<FeedItem>, String>((ref, query) {
      if (query.trim().isEmpty) return Future.value(const <FeedItem>[]);
      return ref.watch(ytMusicApiProvider).searchAlbums(query);
    });

/// The YouTube Music home feed, interleaved into the Music tab. Not
/// autoDispose: it's a large response and the feed doesn't change minute to
/// minute, so re-fetching on every tab switch would be wasteful.
/// Your own YouTube library — liked songs, playlists, albums, artists.
///
/// Empty when signed out, rather than an error: the Library screen renders
/// whatever sections it gets, and "no account" is simply no sections.
final ytMusicLibraryProvider = FutureProvider<List<HomeSection>>((ref) {
  if (!ref.watch(ytAuthProvider).isSignedIn) {
    return Future.value(const <HomeSection>[]);
  }
  return ref.watch(ytMusicApiProvider).library();
});

final ytMusicHomeProvider = FutureProvider<List<HomeSection>>((ref) {
  return ref.watch(ytMusicApiProvider).home();
});

/// Mood and genre chips. Static enough to hold for the session.
final ytMusicMoodsProvider = FutureProvider<List<YtCategoryGroup>>((ref) {
  return ref.watch(ytMusicApiProvider).moodsAndGenres();
});

/// Key for a mood/genre category browse — both halves are opaque and must
/// travel together.
typedef YtCategoryKey = ({String browseId, String params});

final ytMusicCategoryProvider = FutureProvider.autoDispose
    .family<List<HomeSection>, YtCategoryKey>((ref, key) {
      return ref.watch(ytMusicApiProvider).category(key.browseId, key.params);
    });

final ytMusicArtistProvider = FutureProvider.autoDispose
    .family<YtArtistDetail?, String>((ref, browseId) {
      final link = ref.keepAlive();
      Future<void>.delayed(
        const Duration(minutes: 10),
      ).then((_) => link.close());
      return ref.watch(ytMusicApiProvider).artist(browseId);
    });

final ytMusicPlaylistProvider = FutureProvider.autoDispose
    .family<YtPlaylistDetail?, String>((ref, browseId) {
      // Held briefly so back-navigation out of a playlist and straight back in
      // doesn't re-fetch a 100-track response.
      final link = ref.keepAlive();
      Future<void>.delayed(
        const Duration(minutes: 10),
      ).then((_) => link.close());
      return ref.watch(ytMusicApiProvider).playlist(browseId);
    });
