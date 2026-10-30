// Port of sunoh-api src/config/config.ts (saavn block) and the saavn parts of
// src/helpers/dataConfig.ts. Only endpoints the on-device port actually calls
// are kept; the rest of the TS table is unreachable from /music.
const saavnBaseUrl = 'https://www.jiosaavn.com/api.php';

/// Query params every Saavn call carries. Values are ints/strings exactly as
/// the TS config spells them so the query string is byte-for-byte alike.
const Map<String, Object> saavnCommonParams = {
  'api_version': '4',
  '_format': 'json',
  '_marker': 0,
  'ctx': 'web6dot0',
};

const saavnEndpoints = (
  home: 'webapi.getLaunchData',
  albumToken: 'webapi.get',
  albumRecommended: 'reco.getAlbumReco',
  songId: 'song.getDetails',
  songLink: 'webapi.get',
  songRecommended: 'reco.getreco',
  playlistId: 'playlist.getDetails',
  playlistToken: 'webapi.get',
  artistLink: 'webapi.get',
  radioFeatured: 'webradio.createFeaturedStation',
  radioArtist: 'webradio.createArtistStation',
  radioCreate: 'webradio.createStation',
  radioEntity: 'webradio.createEntityStation',
  radioSongs: 'webradio.getSong',
  featuredStations: 'webradio.getFeaturedStations',
  lyrics: 'lyrics.getLyrics',
  channelId: 'channel.getDetails',
  channelToken: 'webapi.get',
);

/// `config.saavn.endpoint.search`, keyed by the `type` query value.
const Map<String, String> saavnSearchEndpoints = {
  'top_search': 'content.getTopSearches',
  'all': 'autocomplete.get',
  'songs': 'search.getResults',
  'albums': 'search.getAlbumResults',
  'artists': 'search.getArtistResults',
  'playlists': 'search.getPlaylistResults',
  'more': 'search.getMoreResults',
};

// dataConfig.ts: each value is a dot path or an ordered list of fallbacks.
const Map<String, Object> homeConfig = {
  'heading': 'title',
  'title': 'title',
  'id': 'id',
  'subtitle': 'subtitle',
  'images': 'image',
  'type': 'type',
  'token': 'perma_url',
  'stationType': 'more_info.featured_station_type',
  'language': 'more_info.language',
};

const Map<String, Object> albumConfig = {
  'id': 'id',
  'title': ['title', 'name'],
  'subtitle': ['subtitle_desc', 'subtitle'],
  'description': 'header_desc',
  'token': ['perma_url', 'url'],
  'images': 'image',
  'language': 'language',
  'year': 'year',
  'list': 'list',
  'songCount': 'more_info.song_count',
  'followerCount': 'more_info.follower_count',
  'artists': 'more_info.artistMap.artists',
};

const Map<String, Object> songListConfig = {
  'id': ['id'],
  'title': 'title',
  'subtitle': 'subtitle',
  'images': 'image',
  'language': 'language',
  'year': 'year',
  'type': 'type',
  'playCount': 'play_count',
  'album': 'more_info.album',
  'albumId': 'more_info.album_id',
  'albumUrl': 'more_info.album_url',
  'mediaUrls': 'more_info.encrypted_media_url',
  'duration': 'more_info.duration',
  'copyright': 'more_info.copyright_text',
  'release_date': 'more_info.release_date',
  'hasLyrics': 'more_info.has_lyrics',
  'artists': 'more_info.artistMap.artists',
  'token': ['more_info.url', 'perma_url', 'url'],
};

const Map<String, Object> artistMetaConfig = {
  'title': 'name',
  'id': ['artistId', 'id'],
  'subtitle': 'subtitle',
  'images': ['image', 'image_url'],
  'followers': 'follower_count',
  'bio': 'bio',
  'token': ['perma_url', 'url'],
};

const Map<String, Object> songDetailsConfig = {
  'endpoint': 'source',
  'heading': 'title',
  'artistIds': 'source_params.artist_ids',
  'actorIds': 'source_params.actor_ids',
  'songId': 'source_params.song_id',
  'language': ['source_params.language', 'source_params.entity_language'],
  'type': 'source_params.entity_type',
  'pid': 'source_params.pid',
};

const Map<String, Object> albumRecoConfig = {
  'endpoint': 'source',
  'heading': 'title',
  'albumId': 'source_params.albumid',
  'language': ['source_params.language', 'source_params.entity_language'],
  'type': 'source_params.entity_type',
  'year': 'source_params.album_year',
  'listId': 'source_params.listid',
};
