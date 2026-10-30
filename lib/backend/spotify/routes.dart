// Port of sunoh-api src/spotify (route.ts).
import '../local_backend.dart';
import 'controller.dart';

void registerSpotifyRoutes(LocalRoutes r) {
  r.get('/spotify/import', importPlaylistController);
}
