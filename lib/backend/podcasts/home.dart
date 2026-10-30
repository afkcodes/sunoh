// The /podcasts/home aggregator: Apple charts resolved through PodcastIndex.
// Ported from controller.ts (COUNTRY_CONFIG, resolveByItunesIds, home).
import 'package:dio/dio.dart';

import '../upstream.dart';
import 'itunes.dart';
import 'mappers.dart';
import 'podcast_index_client.dart';

typedef _Section = ({String heading, String? genreId});

// Apple genre ids: 1303 Comedy, 1304 Education, 1311 News, 1318 Technology,
// 1321 Business, 1324 Society & Culture.
const Map<String, ({String appleCode, List<_Section> sections})> _config = {
  'IN': (
    appleCode: 'in',
    sections: [
      (heading: 'Top podcasts in India', genreId: null),
      (heading: 'News', genreId: '1311'),
      (heading: 'Comedy', genreId: '1303'),
      (heading: 'Society & Culture', genreId: '1324'),
      (heading: 'Business', genreId: '1321'),
      (heading: 'Education', genreId: '1304'),
    ],
  ),
  'US': (
    appleCode: 'us',
    sections: [
      (heading: 'Top podcasts', genreId: null),
      (heading: 'News', genreId: '1311'),
      (heading: 'Comedy', genreId: '1303'),
      (heading: 'Technology', genreId: '1318'),
      (heading: 'Business', genreId: '1321'),
      (heading: 'Society & Culture', genreId: '1324'),
    ],
  ),
};

/// Over-fetch from Apple because byitunesid misses shows PodcastIndex lacks.
const _appleFetchCount = 20;
const _perSectionCap = 12;

Future<List<Map<String, Object?>>> buildHome(
  PodcastIndexClient pi,
  String country, {
  Dio? appleDio,
}) async {
  final cfg = _config[country] ?? _config['IN']!;
  final dio = appleDio ?? upstreamDio();
  final sections = await Future.wait(
    cfg.sections.map((s) async {
      final ids = await appleChart(
        dio,
        cfg.appleCode,
        _appleFetchCount,
        genreId: s.genreId,
      );
      return _resolve(pi, ids);
    }),
  );

  // First section wins a show that appears in several charts.
  final seen = <String>{};
  final out = <Map<String, Object?>>[];
  for (var i = 0; i < sections.length; i++) {
    final kept = <Map<String, Object?>>[];
    for (final show in sections[i]) {
      if (!seen.add('${show['id']}')) continue;
      kept.add(show);
      if (kept.length >= _perSectionCap) break;
    }
    if (kept.isEmpty) continue;
    out.add({
      'heading': cfg.sections[i].heading,
      'data': kept,
      'source': 'podcastindex',
    });
  }
  return out;
}

/// iTunes ids to PodcastIndex shows in chart order, dropping misses.
Future<List<Map<String, Object?>>> _resolve(
  PodcastIndexClient pi,
  List<String> ids,
) async {
  final results = await Future.wait(
    ids.map((id) => pi.get('/podcasts/byitunesid', {'id': id})),
  );
  final out = <Map<String, Object?>>[];
  for (final r in results) {
    if (!r.ok) continue;
    final feed = r.data?['feed'];
    // An unknown show still comes back as a feed, with id 0 and no title.
    if (feed is! Map || !_present(feed['id']) || !_present(feed['title'])) {
      continue;
    }
    out.add(mapPodcastShow(feed.cast<String, dynamic>()));
  }
  return out;
}

bool _present(Object? v) => v != null && v != 0 && v != '';
