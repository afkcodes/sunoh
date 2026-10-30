// Port of sunoh-api src/music/route.ts: the unified /music routes. Each route
// looks at `?provider=` and either hands over to that provider's controller
// or, with no provider, to the unified (merged) one.
import '../gaana/gaana.dart' as gaana;
import '../local_backend.dart';
import '../response_cache.dart';
import '../saavn/saavn.dart' as saavn;
import '../spotify/controller.dart' as spotify;
import 'artist.dart';
import 'languages.dart';
import 'radio.dart';
import 'shared.dart';
import 'song_sections.dart';
import 'unified_controller.dart';

/// Picks the controller for `?provider=`. Exact match, as the server's
/// `provider === 'gaana'` comparisons were; anything else takes [fallback].
Ctl byProvider(Map<String, Ctl> table, Ctl fallback) =>
    (params, query) => (table[query['provider']] ?? fallback)(params, query);

Ctl _unsupported(String message) =>
    (params, query) async => throw LocalApiError(message);

/// The server answered a bare `{error}` body here; the envelope's message
/// carries the same text.
final _streamUnsupported = _unsupported(
  'Song streams are only supported for Gaana provider currently',
);

Future<LocalReply> _spotifyPlaylist(
  Map<String, String> params,
  Map<String, String> query,
) {
  // The Spotify importer takes ?url=; the music route only has the path id.
  final url = query['url'];
  final withUrl = {
    ...query,
    'url': url != null && url.isNotEmpty
        ? url
        : 'https://open.spotify.com/playlist/${params['playlistId']}',
  };
  return spotify.importPlaylistController(params, withUrl, null);
}

Future<LocalReply> _saavnOccasion(
  Map<String, String> params,
  Map<String, String> query,
) => saavn.channelController({...params, 'channelId': params['slug']!}, query);

void registerMusicRoutes(LocalRoutes r) {
  gaana.saavnSongSections = saavnSongSections;

  void get(String path, Ctl c, {CachePolicy? cache}) =>
      r.get(path, (p, q, _) => c(p, q), cache: cache);

  get(
    '/music/home',
    byProvider({
      'gaana': gaana.homeController,
      'saavn': saavn.homeController,
    }, unifiedHomeController),
    // 34 upstream requests cold, 31 of them to Gaana (ban risk). 30 min keeps
    // "new releases" current; the 24 h stale window means opening the app
    // after a night shows the old feed instantly while a new one loads.
    cache: const CachePolicy(
      fresh: Duration(minutes: 30),
      stale: Duration(hours: 24),
      persist: true,
    ),
  );
  get(
    '/music/search',
    byProvider({
      'gaana': gaana.searchController,
      'saavn': saavn.searchController,
    }, unifiedSearchController),
  );
  get(
    '/music/album/:albumId',
    byProvider({'gaana': gaana.albumController}, saavn.albumController),
  );
  get(
    '/music/song/:songId',
    byProvider({'gaana': gaana.songController}, saavn.songController),
  );
  get('/music/recommend', unifiedRecommendController);
  get(
    '/music/song/:songId/stream',
    byProvider({'gaana': gaana.songStreamController}, _streamUnsupported),
  );
  get(
    '/music/playlist/:playlistId',
    byProvider({
      'spotify': _spotifyPlaylist,
      'gaana': gaana.playlistController,
    }, saavn.playlistController),
  );
  get(
    '/music/occasions',
    byProvider(
      {'gaana': gaana.occasionController},
      _unsupported('Occasions are only supported for Gaana provider currently'),
    ),
    // The category list barely changes; 6 h is plenty.
    cache: const CachePolicy(fresh: Duration(hours: 6), persist: true),
  );
  get(
    '/music/occasions/:slug',
    byProvider(
      {'gaana': gaana.occasionDetailController, 'saavn': _saavnOccasion},
      _unsupported(
        'Occasion details are only supported for Gaana and Saavn provider '
        'currently',
      ),
    ),
  );
  get('/music/artist/:artistId', unifiedArtistController);
  get('/music/radio/session', unifiedRadioSessionController);
  get('/music/radio/:sessionId', unifiedRadioPlayController);
  // A fixed list; once a day is generous.
  get(
    '/music/languages',
    languagesController,
    cache: const CachePolicy(fresh: Duration(hours: 24), persist: true),
  );
}
