// Home-feed Riverpod provider — fetches `/music/home` once per languages
// selection, keeps the result alive for ~30 min (matches the RN client's
// staleTime), and exposes refresh.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dto.dart';
import 'api_providers.dart';

/// Family parameter so different language selections cache independently.
final homeFeedProvider = FutureProvider.autoDispose
    .family<List<HomeSection>, String?>((ref, languages) async {
  // Keep the response cached even when nothing is listening, so navigating
  // away and back doesn't refetch (similar to RN's staleTime).
  final link = ref.keepAlive();
  Future<void>.delayed(const Duration(minutes: 30)).then((_) => link.close());

  final api = ref.watch(sunohApiProvider);
  return api.fetchHome(languages: languages);
});
