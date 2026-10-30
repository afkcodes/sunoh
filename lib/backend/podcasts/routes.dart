// The /podcasts routes of sunoh-api, answered on the phone from PodcastIndex
// and Apple's charts. Ported from src/podcast/controller.ts and route.ts;
// /podcasts/trending and /podcasts/recent are unused by the app and omitted.
import 'dart:ui' show PlatformDispatcher;

import '../local_backend.dart';
import '../response_cache.dart';
import 'country.dart';
import 'home.dart';
import 'mappers.dart';
import 'podcast_index_client.dart';

const _source = 'podcastindex';

void registerPodcastRoutes(LocalRoutes r, {PodcastIndexClient? client}) {
  final pi = client ?? PodcastIndexClient();

  // Up to ~126 PodcastIndex requests; charts move slowly, so 6 h fresh and a
  // 3 day stale window (shown instantly, refreshed behind it).
  r.get(
    '/podcasts/home',
    (p, q, b) async {
      pi.ensureConfigured();
      final country = resolveCountry(
        explicit: q['country'],
        deviceCountry: PlatformDispatcher.instance.locale.countryCode,
      );
      final sections = await buildHome(pi, country);
      if (sections.isEmpty) {
        throw LocalApiError('No sections returned from upstream', code: 502);
      }
      return LocalReply(
        sections,
        message: 'Podcasts home ($country)',
        source: _source,
      );
    },
    cache: const CachePolicy(
      fresh: Duration(hours: 6),
      stale: Duration(days: 3),
      persist: true,
    ),
  );

  r.get('/podcasts/categories', (p, q, b) async {
    pi.ensureConfigured();
    final up = await pi.get('/categories/list');
    if (!up.ok) throw _fail(up, 'Categories fetch failed');
    final list = (up.data?['feeds'] as List?) ?? const [];
    return LocalReply(
      {'list': list, 'count': list.length},
      message: 'Categories',
      source: _source,
    );
  }, cache: const CachePolicy(fresh: Duration(hours: 24), persist: true));

  r.get('/podcasts/by-category/:slug', (p, q, b) async {
    pi.ensureConfigured();
    final slug = p['slug'];
    final up = await pi.get('/podcasts/trending', {
      'max': q['max'] ?? 30,
      'cat': slug,
      'lang': q['lang'],
    });
    if (!up.ok) throw _fail(up, 'Category fetch failed');
    final shows = mapPodcastShows(up.data?['feeds']);
    return LocalReply(
      {'list': shows, 'count': shows.length, 'category': slug},
      message: 'Podcasts in $slug',
      source: _source,
    );
  });

  r.get('/podcasts/search', (p, q, b) async {
    pi.ensureConfigured();
    final term = (q['q'] ?? q['query'] ?? '').trim();
    if (term.isEmpty) {
      throw LocalApiError('Missing required query parameter `q`');
    }
    final up = await pi.get('/search/byterm', {
      'q': term,
      'max': q['max'] ?? 30,
      'similar': q['similar'],
      'fulltext': true,
    });
    if (!up.ok) throw _fail(up, 'Search failed');
    final shows = mapPodcastShows(up.data?['feeds']);
    return LocalReply(
      {'list': shows, 'count': shows.length, 'query': term},
      message: 'Search results',
      source: _source,
    );
  });

  r.get('/podcasts/episode/:guid', (p, q, b) async {
    pi.ensureConfigured();
    final guid = p['guid'];
    var up = (guid == null || guid.isEmpty)
        ? const PiResult(ok: false)
        : await pi.get('/episodes/byguid', {
            'guid': guid,
            'feedurl': q['feedurl'],
            'feedid': q['feedid'],
          });
    // Prefer guid; fall back to the numeric id when the guid finds nothing.
    if (!up.ok && (q['id'] ?? '').isNotEmpty) {
      up = await pi.get('/episodes/byid', {'id': q['id']});
    }
    if (!up.ok) throw _fail(up, 'Episode fetch failed');
    final raw = up.data?['episode'];
    if (raw is! Map) throw LocalApiError('Episode not found', code: 404);
    return LocalReply(
      mapPodcastEpisode(raw.cast<String, dynamic>()),
      message: 'Episode',
      source: _source,
    );
  });

  r.get('/podcasts/:id/episodes', (p, q, b) async {
    pi.ensureConfigured();
    final up = await pi.get('/episodes/byfeedid', {
      'id': p['id'],
      'max': q['max'] ?? 50,
      'since': q['since'],
      'enclosure': q['enclosure'],
    });
    if (!up.ok) throw _fail(up, 'Episodes fetch failed');
    final eps = mapPodcastEpisodes(up.data?['items']);
    return LocalReply(
      {'list': eps, 'count': eps.length},
      message: 'Episodes',
      source: _source,
    );
  });

  r.get('/podcasts/:id', (p, q, b) async {
    pi.ensureConfigured();
    final id = p['id'];
    final (show, eps) = await (
      pi.get('/podcasts/byfeedid', {'id': id}),
      pi.get('/episodes/byfeedid', {
        'id': id,
        'max': q['max'] ?? 30,
        'since': q['since'],
      }),
    ).wait;
    final feed = show.data?['feed'];
    if (!show.ok || feed is! Map) throw _fail(show, 'Show fetch failed');
    final episodes = eps.ok ? mapPodcastEpisodes(eps.data?['items']) : [];
    return LocalReply(
      {
        ...mapPodcastShow(feed.cast<String, dynamic>()),
        'episodes': episodes,
        'episodeCount': episodes.length,
      },
      message: 'Show + recent episodes',
      source: _source,
    );
  });
}

/// Upstream failure as the server reported it: 502 with PodcastIndex's text.
LocalApiError _fail(PiResult r, String fallback) => LocalApiError(
  (r.error == null || r.error!.isEmpty) ? fallback : r.error!,
  code: 502,
);
