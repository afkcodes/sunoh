// Shared "start a radio station" flow — pulled out of HomeScreen so the
// channel detail screen (and anywhere else with a radio_station tile)
// can fire it via one call.
//
// What it does:
//   1. POST /music/radio/session with the seed (id / name / type /
//      provider / lang). Saavn quick-stations ship empty `id`s — the
//      backend's featured-station creator falls back to `name` for those,
//      which is why we always pass the title.
//   2. GET the resulting `/music/radio/<sessionId>` for the first batch
//      of songs.
//   3. Hand them to AppState.playApiQueue so playback + the player UI
//      light up.
//
// Failure messages surface via `flashToast` so the user gets a hint
// without us showing a stack trace. Pre-flight prints survive
// release-mode logcat — invaluable when troubleshooting "tap did
// nothing on radio X".

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dto.dart';
import '../providers/api_providers.dart';
import '../providers/app_state_provider.dart';

Future<void> startRadioStation(
  WidgetRef ref,
  FeedItem item, {
  String? provider,
  String? kind,
}) async {
  final s = ref.read(appStateProvider);
  final api = ref.read(sunohApiProvider);
  final resolvedProvider = provider ?? item.source ?? 'saavn';
  // Priority for the radio-session `type` param:
  //   explicit override (e.g. 'artist' on artist tiles) →
  //   item.stationType from the feed →
  //   'featured' fallback (works for the saavn quick_stations whose id
  //    is empty — name carries the seed).
  final stationKind = kind ?? item.stationType ?? 'featured';
  // ignore: avoid_print
  print('[radio] starting station id="${item.id}" kind="$stationKind" '
      'provider="$resolvedProvider" name="${item.title}" lang="${item.language}"');
  s.flashToast('Starting ${item.title}…');
  try {
    final sessionId = await api.fetchRadioSession(
      id: item.id,
      type: stationKind,
      provider: resolvedProvider,
      name: item.title,
      lang: item.language,
    );
    // ignore: avoid_print
    print('[radio] session response → '
        '${sessionId ?? 'NULL (request failed or empty data)'}');
    if (sessionId == null) {
      s.flashToast('Couldn’t start ${item.title}');
      return;
    }
    final songs = await api.fetchRadioSongs(sessionId, count: 20);
    // ignore: avoid_print
    print('[radio] fetched ${songs.length} songs for session "$sessionId"');
    if (songs.isEmpty) {
      s.flashToast('No songs available on this station');
      return;
    }
    await s.playApiQueue(songs, 0,
        sourceLabel: 'RADIO · ${item.title}');
  } catch (e, st) {
    // ignore: avoid_print
    print('[radio] FAILED: $e\n$st');
    s.flashToast('Radio failed: $e');
  }
}
