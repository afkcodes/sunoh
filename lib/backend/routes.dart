// The single registry of on-device sunoh-api routes. Each feature area
// registers its own; see local_backend.dart for why they exist.
import 'local_backend.dart';
import 'music/routes.dart';
import 'podcasts/routes.dart';
import 'spotify/routes.dart';

LocalRoutes buildLocalRoutes() {
  final r = LocalRoutes();
  registerMusicRoutes(r);
  registerPodcastRoutes(r);
  registerSpotifyRoutes(r);
  return r;
}
