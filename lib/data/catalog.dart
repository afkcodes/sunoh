// The sunoh. catalog — fictional placeholder library content.
// Ported verbatim from the design prototype's data.jsx.

import 'models.dart';

const List<Track> kTracks = [
  Track(id: 't01', title: 'Velour Sky', artist: 'Aerial Trust', album: 'a01', duration: 218, plays: '12.4M'),
  Track(id: 't02', title: 'Goldenrod', artist: 'Aerial Trust', album: 'a01', duration: 191, plays: '8.1M'),
  Track(id: 't03', title: 'Half-Hour Sun', artist: 'Aerial Trust', album: 'a01', duration: 244, plays: '4.7M'),
  Track(id: 't04', title: 'Late Reply', artist: 'Aerial Trust', album: 'a01', duration: 173, plays: '3.2M'),
  Track(id: 't05', title: 'Mineral, Moss', artist: 'Aerial Trust', album: 'a01', duration: 256, plays: '2.9M'),
  Track(id: 't06', title: 'Civic Park', artist: 'Aerial Trust', album: 'a01', duration: 198, plays: '2.1M'),
  Track(id: 't07', title: 'Telegraph', artist: 'Aerial Trust', album: 'a01', duration: 165, plays: '1.8M'),
  Track(id: 't08', title: 'Postcard from Lisbon', artist: 'Aerial Trust', album: 'a01', duration: 271, plays: '1.6M'),
  Track(id: 't10', title: 'Static Shoreline', artist: 'Niamh Calder', album: 'a02', duration: 224, plays: '22.3M'),
  Track(id: 't11', title: 'Marble', artist: 'Niamh Calder', album: 'a02', duration: 207, plays: '15.0M'),
  Track(id: 't12', title: 'Six Bridges', artist: 'Niamh Calder', album: 'a02', duration: 251, plays: '9.6M'),
  Track(id: 't13', title: 'Brass Rotunda', artist: 'Niamh Calder', album: 'a02', duration: 282, plays: '6.4M'),
  Track(id: 't20', title: 'Crater Lake', artist: 'OKO', album: 'a03', duration: 312, plays: '4.1M'),
  Track(id: 't21', title: 'Soft Industry', artist: 'OKO', album: 'a03', duration: 245, plays: '3.0M'),
  Track(id: 't22', title: 'Pewter', artist: 'OKO', album: 'a03', duration: 198, plays: '2.4M'),
  Track(id: 't30', title: 'Holland Avenue', artist: 'June Halliday', album: 'a04', duration: 215, plays: '11.2M'),
  Track(id: 't31', title: 'Salt & Iron', artist: 'June Halliday', album: 'a04', duration: 187, plays: '7.7M'),
  Track(id: 't32', title: 'Wishbone', artist: 'June Halliday', album: 'a04', duration: 234, plays: '5.3M'),
  Track(id: 't40', title: 'Quartz Hours', artist: 'Sable & Ash', album: 'a05', duration: 268, plays: '3.8M'),
  Track(id: 't41', title: 'Drift, North', artist: 'Sable & Ash', album: 'a05', duration: 311, plays: '2.5M'),
];

const List<Album> kAlbums = [
  Album(id: 'a01', title: 'Velour Sky', artist: 'Aerial Trust', year: 2024, kind: 'Album', trackCount: 8, duration: '46 min'),
  Album(id: 'a02', title: 'Static Shoreline', artist: 'Niamh Calder', year: 2023, kind: 'Album', trackCount: 11, duration: '52 min'),
  Album(id: 'a03', title: 'Slow Industry', artist: 'OKO', year: 2025, kind: 'EP', trackCount: 5, duration: '24 min'),
  Album(id: 'a04', title: 'Holland Avenue', artist: 'June Halliday', year: 2024, kind: 'Album', trackCount: 10, duration: '38 min'),
  Album(id: 'a05', title: 'Quartz Hours', artist: 'Sable & Ash', year: 2022, kind: 'Album', trackCount: 12, duration: '57 min'),
  Album(id: 'a06', title: 'Atrium', artist: 'Mira Voss', year: 2025, kind: 'Single', trackCount: 1, duration: '4 min'),
  Album(id: 'a07', title: 'Counterweight', artist: 'Field Notes', year: 2024, kind: 'Album', trackCount: 9, duration: '41 min'),
];

const List<Artist> kArtists = [
  Artist(id: 'ar01', name: 'Aerial Trust', monthly: '2.4M', tags: ['Indie', 'Dream Pop', 'Lo-fi']),
  Artist(id: 'ar02', name: 'Niamh Calder', monthly: '8.1M', tags: ['Folk', 'Singer-songwriter']),
  Artist(id: 'ar03', name: 'OKO', monthly: '910K', tags: ['Electronic', 'Ambient']),
  Artist(id: 'ar04', name: 'June Halliday', monthly: '1.6M', tags: ['Jazz', 'Soul']),
  Artist(id: 'ar05', name: 'Sable & Ash', monthly: '430K', tags: ['Post-rock', 'Instrumental']),
];

const List<Playlist> kPlaylists = [
  Playlist(id: 'p01', title: 'After Hours', curator: 'sunoh editorial', tracks: 32, hours: '2h 14m', sub: 'Smoke-stained jazz, quiet basement piano, 3am rooms.'),
  Playlist(id: 'p02', title: 'Soft Concrete', curator: 'You', tracks: 41, hours: '2h 48m', sub: 'Your saved warm-electronic things.'),
  Playlist(id: 'p03', title: 'On the Way Home', curator: 'sunoh editorial', tracks: 24, hours: '1h 32m', sub: 'Slow walk, headphones, last train.'),
  Playlist(id: 'p04', title: 'Workbench', curator: 'You', tracks: 58, hours: '3h 41m', sub: 'For deep, head-down work.'),
  Playlist(id: 'p05', title: 'Threshold Hours', curator: 'sunoh editorial', tracks: 19, hours: '1h 18m', sub: 'Dawn, dusk, the seam between.'),
  Playlist(id: 'p06', title: 'Saturday Bedroom', curator: 'You', tracks: 47, hours: '3h 02m', sub: 'Long, warm, untidy.'),
];

const List<Station> kStations = [
  Station(id: 's01', name: 'KIOSK 92.3', freq: '92.3', tag: 'Late-night jazz', live: 'On air · Coltrane Variations', listeners: '3,402'),
  Station(id: 's02', name: 'Tideline FM', freq: '88.7', tag: 'Ambient · Drone', live: 'On air · Long Wave Field', listeners: '1,180'),
  Station(id: 's03', name: 'Chroma Public', freq: '101.9', tag: 'Public radio', live: 'On air · Morning Edition', listeners: '12.4K'),
  Station(id: 's04', name: 'Mineral Beat', freq: '105.5', tag: 'House · Downtempo', live: 'On air · DJ Phyla', listeners: '6,718'),
  Station(id: 's05', name: 'Holland Park', freq: '96.1', tag: 'Indie · New releases', live: 'On air · Sundown Mix', listeners: '4,902'),
  Station(id: 's06', name: 'BBC-ish 4', freq: '94.2', tag: 'Talk · Documentaries', live: 'On air · The Reading Room', listeners: '8,201'),
];

const List<Podcast> kPodcasts = [
  Podcast(id: 'pd01', title: 'Long Form, Slowly', host: 'Avery Park', cadence: 'Weekly', episodes: 142, sub: 'Two-hour conversations with the people building the small, strange things of the internet.'),
  Podcast(id: 'pd02', title: 'The Reading Room', host: 'Cleo Marsh', cadence: 'Twice weekly', episodes: 88, sub: 'Short essays read aloud — fiction, criticism, a little philosophy.'),
  Podcast(id: 'pd03', title: 'Tideline', host: 'Iyer & Kowalski', cadence: 'Monthly', episodes: 31, sub: 'A field recording show. We go somewhere and listen.'),
  Podcast(id: 'pd04', title: 'Soft Industry', host: 'Helene Voss', cadence: 'Weekly', episodes: 204, sub: 'Designers, makers, and the quieter half of the design industry.'),
];

const List<Episode> kEpisodes = [
  Episode(id: 'e01', pod: 'pd01', num: 142, title: 'On building things you can hold', date: 'May 18', duration: '1h 48m', sub: 'A conversation with a printmaker in Marfa about the long arc of slow work.'),
  Episode(id: 'e02', pod: 'pd01', num: 141, title: 'The fourth quiet redesign', date: 'May 11', duration: '2h 12m', sub: 'Three product designers on the redesigns nobody talks about — the ones that smooth a surface they didn’t name.'),
  Episode(id: 'e03', pod: 'pd01', num: 140, title: 'A small bookshop, a long lease', date: 'May 04', duration: '1h 56m', sub: 'Twenty-one years of an independent shop in Lisbon.'),
  Episode(id: 'e04', pod: 'pd01', num: 139, title: 'The map is a kind of permission', date: 'Apr 27', duration: '2h 04m', sub: 'A cartographer on how a place changes once it is drawn.'),
  Episode(id: 'e05', pod: 'pd01', num: 138, title: 'Studio visit — the ceramicist', date: 'Apr 20', duration: '1h 41m', sub: ''),
  Episode(id: 'e06', pod: 'pd01', num: 137, title: 'Maintenance as authorship', date: 'Apr 13', duration: '2h 18m', sub: ''),
];

const List<Mix> kMixes = [
  Mix(id: 'm01', title: 'Daily Mix 01', sub: 'Aerial Trust, OKO, Sable & Ash + 47 more'),
  Mix(id: 'm02', title: 'Daily Mix 02', sub: 'Niamh Calder, June Halliday + 42 more'),
  Mix(id: 'm03', title: 'Discover Wknd', sub: 'Made for you, refreshed Sunday'),
  Mix(id: 'm04', title: 'Time Capsule', sub: 'Songs you loved in 2019'),
];

// Karaoke-style lyric lines keyed by track id. Each line has a start time (s).
const Map<String, List<LyricLine>> kLyrics = {
  't01': [
    LyricLine(0, 'It starts with a slow sky,'),
    LyricLine(6, 'velour at the edges,'),
    LyricLine(11, 'a city not yet awake.'),
    LyricLine(17, ''),
    LyricLine(21, 'You said ‘wait,’'),
    LyricLine(26, 'so I waited a year'),
    LyricLine(31, 'and the sky did the same.'),
    LyricLine(37, ''),
    LyricLine(41, 'Velour sky, velour sky,'),
    LyricLine(47, 'I will meet you halfway,'),
    LyricLine(53, 'half a sun, half a song.'),
    LyricLine(60, ''),
    LyricLine(65, 'It ends with a slow sky,'),
    LyricLine(71, 'soft as a closing door,'),
    LyricLine(77, 'a city going home.'),
    LyricLine(85, ''),
    LyricLine(90, '— instrumental —'),
  ],
};

// ── Helpers ───────────────────────────────────────────────────────────────

String fmt(num sec) {
  final m = (sec ~/ 60);
  final s = (sec % 60).floor();
  return '$m:${s.toString().padLeft(2, '0')}';
}

List<Track> tracksOfAlbum(String albumId) =>
    kTracks.where((t) => t.album == albumId).toList();

Album? albumOf(String id) {
  for (final a in kAlbums) {
    if (a.id == id) return a;
  }
  return null;
}

Artist? artistByName(String name) {
  for (final a in kArtists) {
    if (a.name == name) return a;
  }
  return null;
}

Artist? artistById(String id) {
  for (final a in kArtists) {
    if (a.id == id) return a;
  }
  return null;
}

Playlist? playlistOf(String id) {
  for (final p in kPlaylists) {
    if (p.id == id) return p;
  }
  return null;
}

Station? stationOf(String id) {
  for (final s in kStations) {
    if (s.id == id) return s;
  }
  return null;
}

Podcast? podcastOf(String id) {
  for (final p in kPodcasts) {
    if (p.id == id) return p;
  }
  return null;
}

List<Episode> episodesOf(String podId) =>
    kEpisodes.where((e) => e.pod == podId).toList();
