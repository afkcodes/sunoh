// Riverpod providers for the sunoh-radio integration.
//
// Mirrors the shape of `podcast_provider.dart`. Only the search
// provider exists today — that's all the search screen needs. The
// "Radio" top-tab + home/category providers will land alongside the
// Flutter Radio UI work; this file expands when that ships.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dto.dart';
import 'api_providers.dart';

/// `radioSearchProvider(query)` — typed search across sunoh-radio's
/// catalog. 5 min `keepAlive` so navigating away + back to the search
/// screen doesn't re-fetch when the query is unchanged. Empty query
/// short-circuits to an empty list (no upstream call).
final radioSearchProvider = FutureProvider.autoDispose
    .family<List<FeedItem>, String>((ref, query) async {
  final link = ref.keepAlive();
  Future<void>.delayed(const Duration(minutes: 5)).then((_) => link.close());
  if (query.trim().isEmpty) return const [];
  final api = ref.watch(sunohApiProvider);
  return api.fetchRadioSearch(query);
});
