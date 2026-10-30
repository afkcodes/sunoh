// Shared types for the Spotify import (port of sunoh-api src/spotify/types.ts).
// Kept apart so scraper and match do not import each other.

/// One playlist row. The JSON form carries exactly the keys the server's
/// browser scraper produced (`id, name, artists, album, durationMs, url`),
/// because the app's DTO and the parity test compare against that shape.
class SpotifyTrack {
  const SpotifyTrack({
    required this.id,
    required this.name,
    required this.artists,
    required this.album,
    required this.durationMs,
    required this.url,
    this.isrc,
  });

  final String id;
  final String name;
  final List<String> artists;
  final String album;
  final int durationMs;
  final String url;

  /// Neither source exposes it today (the scraper never did either); kept so
  /// match.dart's ISRC pass works the day one does. Not serialised.
  final String? isrc;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'artists': artists,
    'album': album,
    'durationMs': durationMs,
    'url': url,
  };
}

class SpotifyPlaylist {
  const SpotifyPlaylist({
    required this.id,
    required this.name,
    required this.url,
    required this.tracks,
    this.description,
    this.owner,
    this.artworkUrl,
  });

  final String id;
  final String name;
  final String? description;
  final String? owner;
  final String? artworkUrl;
  final String url;
  final List<SpotifyTrack> tracks;

  int get trackCount => tracks.length;
}
