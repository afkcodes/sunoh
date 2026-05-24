// Riverpod providers for the detail screens. Keyed by an (id, source) record
// so the same id can coexist across providers (a saavn album and a gaana
// album might share an id) and so we can pass the provider hint through to
// the API (sunoh-api routes album/playlist by ?provider=…).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dto.dart';
import 'api_providers.dart';

/// Family key for the detail providers. `source` is the backend provider
/// hint ('saavn' | 'gaana' | 'spotify'); null lets the API default.
typedef DetailKey = ({String id, String? source});

void _keepAlive(Ref ref, Duration ttl) {
  final link = ref.keepAlive();
  Future<void>.delayed(ttl).then((_) => link.close());
}

final albumProvider = FutureProvider.autoDispose
    .family<AlbumDetail, DetailKey>((ref, key) async {
  _keepAlive(ref, const Duration(minutes: 30));
  return ref.watch(sunohApiProvider).fetchAlbum(key.id, provider: key.source);
});

final playlistProvider = FutureProvider.autoDispose
    .family<PlaylistDetail, DetailKey>((ref, key) async {
  _keepAlive(ref, const Duration(minutes: 30));
  return ref
      .watch(sunohApiProvider)
      .fetchPlaylist(key.id, provider: key.source);
});

final artistProvider = FutureProvider.autoDispose
    .family<ArtistDetail, DetailKey>((ref, key) async {
  _keepAlive(ref, const Duration(minutes: 30));
  return ref.watch(sunohApiProvider).fetchArtist(key.id, provider: key.source);
});
