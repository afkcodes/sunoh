// GET /spotify/import?url=<playlist url> (port of spotify/controller.ts).
import '../local_backend.dart';
import 'match.dart';
import 'scraper.dart';

const _source = 'spotify';

Future<LocalReply> importPlaylistController(
  Map<String, String> params,
  Map<String, String> query,
  Object? body,
) async {
  final url = query['url'];
  if (url == null || url.isEmpty) {
    throw LocalApiError('Missing required parameter: url');
  }
  final id = extractPlaylistId(url);
  if (id == null) {
    throw LocalApiError(
      'Could not extract a Spotify playlist id from the input',
    );
  }
  final playlist = await fetchSpotifyPlaylist(id);
  if (playlist == null) {
    throw LocalApiError(
      'Failed to fetch playlist from Spotify (private, removed, or upstream error)',
      code: 502,
    );
  }

  final items = await matchTracks(playlist.tracks);
  final matched = items.where((m) => m['matched'] == true).length;

  return LocalReply(
    {
      'source': {
        'id': playlist.id,
        'name': playlist.name,
        // Absent (not null) when unknown, as JSON.stringify drops undefined.
        if (playlist.description != null) 'description': playlist.description,
        if (playlist.owner != null) 'owner': playlist.owner,
        if (playlist.artworkUrl != null) 'artworkUrl': playlist.artworkUrl,
        'url': playlist.url,
        'trackCount': playlist.trackCount,
      },
      'summary': {
        'total': items.length,
        'matched': matched,
        'unmatched': items.length - matched,
      },
      'items': items,
    },
    message:
        'Imported "${playlist.name}" — $matched/${items.length} matched on Saavn',
    source: _source,
  );
}
