// Unified radio (port of unifiedRadioSessionController and
// unifiedRadioPlayController in sunoh-api src/music/controller.ts). A session
// id is the provider prefix plus that provider's station id, so the play
// route knows where to send it.
import 'package:flutter/foundation.dart';

import '../gaana/gaana.dart' as gaana;
import '../gaana/util.dart' show get, or, truthy;
import '../local_backend.dart';
import '../saavn/saavn.dart' as saavn;
import 'shared.dart';

String _languages(Map<String, String> query) =>
    firstNonEmpty([query['lang'], query['languages']]) ?? 'hindi,english';

/// Creates a Saavn station with [ctl]; null when Saavn refuses (the TS only
/// checked `status === 'success'`, so every failure is "no station").
Future<String?> _createStation(Ctl ctl, Map<String, String?> query) async {
  try {
    final r = await ctl({}, {
      for (final e in query.entries)
        if (e.value != null) e.key: e.value!,
    });
    final id = get(r.data, 'stationid');
    return truthy(id) ? '$id' : null;
  } catch (_) {
    return null;
  }
}

/// The Saavn radio endpoint wants a Saavn entity id, but the home feed mixes
/// providers, so callers often hold a Gaana slug. Resolve it through a Saavn
/// song search; on any miss keep the original id (a clean upstream error beats
/// a silent mismatch). Saavn's canonical `songId` wins over the per-row `id`,
/// which its radio creator rejects.
Future<String?> _pivotToSaavnId(
  Map<String, String> query,
  String? id,
  String languages,
) async {
  final provider = query['provider'];
  final looksGaana = id != null && (id.contains('-') || id.length > 16);
  if (!((provider != null && provider.isNotEmpty && provider != 'saavn') ||
      looksGaana)) {
    return id;
  }
  final searchQuery = (firstNonEmpty([query['name'], query['query'], id]) ?? '')
      .trim();
  if (searchQuery.isEmpty) return id;
  try {
    final res = await saavn.getSaavnSearchData(
      searchQuery,
      'songs',
      1,
      5,
      languages,
    );
    final list = get(res, 'list');
    final top = list is List && list.isNotEmpty ? list.first : null;
    final topId = or(get(top, 'songId'), get(top, 'id'));
    if (truthy(topId)) {
      // Ids and queries identify content; keep them out of the log.
      debugPrint('[music] radio session: pivoted to a Saavn song id');
      return '$topId';
    }
    debugPrint('[music] radio session: pivot search found nothing');
  } catch (_) {
    debugPrint('[music] radio session: pivot search failed');
  }
  return id;
}

Future<LocalReply> unifiedRadioSessionController(
  Map<String, String> params,
  Map<String, String> query,
) => unifiedGuard('Failed to init radio session', () async {
  final id = query['id'];
  final type = query['type'] ?? 'song';
  final languages = _languages(query);
  final name = firstNonEmpty([query['name'], query['query']]);

  // Gaana has no "radio from a song id" endpoint, so only non-song Gaana ids
  // are taken as ready-made stations; songs fall through to Saavn.
  if (query['provider'] == 'gaana' && type != 'song') {
    return unified({'stationId': 'gaana_$id'}, 'Radio session created');
  }

  final String? stationId;
  if (type == 'artist') {
    stationId = await _createStation(saavn.artistStationController, {
      'artistId': id,
      'name': name,
      'lang': languages,
    });
  } else if (type == 'featured') {
    stationId = await _createStation(saavn.stationController, {
      'name': firstNonEmpty([name, id]),
      'lang': languages,
    });
  } else {
    stationId = await _createStation(saavn.entityStationController, {
      'entityId': await _pivotToSaavnId(query, id, languages),
      'entityType': type,
      'lang': languages,
    });
  }

  if (stationId == null) throw LocalApiError('Failed to create Saavn station');
  return unified({'stationId': 'saavn_$stationId'}, 'Radio session created');
});

Future<LocalReply> unifiedRadioPlayController(
  Map<String, String> params,
  Map<String, String> query,
) => unifiedGuard('Failed to fetch radio songs', () async {
  final sessionId = params['sessionId'] ?? '';
  final languages = _languages(query);

  if (sessionId.startsWith('gaana_')) {
    // The server also fetched Gaana's station list here and ignored it; that
    // call is skipped on device, it costs a full home request for nothing.
    try {
      final r = await gaana.radioDetailController(
        {'radioId': sessionId.replaceFirst('gaana_', '')},
        {'lang': languages},
      );
      return unified(r.data, 'Radio songs fetched');
    } on LocalApiError {
      throw LocalApiError('Failed to fetch Gaana radio songs');
    }
  }

  if (sessionId.startsWith('saavn_')) {
    try {
      final count = firstNonEmpty([query['count'], query['k']]);
      final next = query['next'];
      final r = await saavn.stationSongsController(
        {'stationId': sessionId.replaceFirst('saavn_', '')},
        {'count': ?count, 'next': ?next, 'lang': languages},
      );
      return unified(r.data, 'Radio songs fetched');
    } on LocalApiError {
      throw LocalApiError('Failed to fetch Saavn radio songs');
    }
  }

  throw LocalApiError('Invalid session ID format');
});
