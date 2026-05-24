// Live search Riverpod provider — fetches `/music/search?q=…&type=all`
// per-query. Caching is intentionally short (5 min) because typed queries
// turn over fast and stale results aren't useful.
//
// Debouncing is the SCREEN's job (the user is still typing), not this
// provider's — the family is keyed by the debounced final query so each
// distinct query has a single coalesced inflight + cache entry.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dto.dart';
import 'api_providers.dart';

final searchProvider = FutureProvider.autoDispose
    .family<List<HomeSection>, String>((ref, query) async {
  // 5-min keepAlive — long enough that scrolling to and from results stays
  // instant, short enough that the local cache doesn't grow per typed query.
  final link = ref.keepAlive();
  Future<void>.delayed(const Duration(minutes: 5)).then((_) => link.close());

  final api = ref.watch(sunohApiProvider);
  return api.fetchSearch(query);
});
