// The write side of a signed-in account: rating a video and keeping a
// playlist of the tracks liked in Sunoh.
//
// Everything else in the YouTube tier is a read. These calls change the user's
// account, so they differ from the rest in two ways:
//
//   - they report HOW they failed. A read can fold every failure into "no
//     rows"; a write has to tell "you are offline, try later" (throws) from
//     "YouTube said no, do not retry" (returns false) from "that playlist is
//     gone" (a distinct answer), or a queue built on top retries forever or
//     gives up too early;
//   - nothing here is logged beyond a 4-character id prefix. Ids are the one
//     thing about the user's listening that reaches a log line.
//
// Request shapes follow the web client as documented by the community
// ytmusicapi project (like/like, like/removelike, playlist/create,
// browse/edit_playlist). They could not be exercised live from a dev machine:
// the session lives in the phone's Keystore.

part of 'ytmusic_api.dart';

/// What the sync engine needs from YouTube. An interface so the engine can be
/// tested with a fake and so `audio/` depends on a shape rather than on Dio.
abstract interface class YtLikeRemote {
  /// Like or un-like [videoId] on the account. True when YouTube accepted it,
  /// false when it refused for a reason retrying will not fix. Throws on a
  /// network or server failure, which a retry may fix.
  Future<bool> rate(String videoId, {required bool like});

  /// Playlist id of the library playlist titled exactly [title], or null.
  Future<String?> findPlaylist(String title);

  /// Create a private playlist and return its id, or null on refusal.
  Future<String?> createPlaylist(String title, String description);

  /// videoId -> setVideoId for every entry of [playlistId]; null when the
  /// playlist no longer exists. setVideoId is the per-entry handle removal
  /// needs: removing by videoId alone is rejected.
  Future<Map<String, String>?> entries(String playlistId);

  Future<bool> addVideo(String playlistId, String videoId);

  Future<bool> removeVideo(
    String playlistId,
    String videoId,
    String setVideoId,
  );
}

/// A write's outcome: status for the caller to classify, body for ids.
class _Reply {
  const _Reply(this.status, this.data);
  final int status;
  final Map<String, dynamic>? data;
  bool get ok => status >= 200 && status < 300;
}

/// 4xx answers that mean "this playlist does not exist (any more)".
bool _isGone(int status) => status == 404 || status == 400;

/// First four characters of an id: enough to correlate log lines, not enough
/// to identify what someone listened to.
String idPrefix(String id) => id.length <= 4 ? id : id.substring(0, 4);

class YtMusicLikeRemote implements YtLikeRemote {
  YtMusicLikeRemote(this._api);
  final YtMusicApi _api;

  @override
  Future<bool> rate(String videoId, {required bool like}) async {
    final r = await _api._send(like ? 'like/like' : 'like/removelike', {
      ..._api._context,
      'target': {'videoId': videoId},
    });
    return r.ok;
  }

  @override
  Future<String?> findPlaylist(String title) async {
    final body = await _api._post('browse', {
      ..._api._context,
      'browseId': _kLikedPlaylists,
    });
    if (body == null) return null;
    final shelves = _singleColumnShelves(body);
    final items = _libraryItems(shelves);
    String? more;
    for (final shelf in shelves) {
      more ??= _continuationOf(shelf);
    }
    for (final raw in await _api._continuationRows(more)) {
      final m = _asMap(raw);
      final item = m == null ? null : _parseTwoRowItem(m);
      if (item != null) items.add(item);
    }
    for (final item in items) {
      if (item.type == 'playlist' && item.title == title) {
        return _playlistIdOf(item.id);
      }
    }
    return null;
  }

  @override
  Future<String?> createPlaylist(String title, String description) async {
    final r = await _api._send('playlist/create', {
      ..._api._context,
      'title': title,
      'description': description,
      'privacyStatus': 'PRIVATE',
    });
    final id = r.data?['playlistId'];
    return r.ok && id is String && id.isNotEmpty ? id : null;
  }

  @override
  Future<Map<String, String>?> entries(String playlistId) async {
    final r = await _api._send('browse', {
      ..._api._context,
      'browseId': 'VL$playlistId',
    });
    if (_isGone(r.status)) return null;
    if (!r.ok || r.data == null) throw StateError('playlist read ${r.status}');
    final out = <String, String>{};
    _collectEntries(r.data, out);
    // Follow the playlist's own track continuation only; see the same note
    // in playlist() on why not the whole response.
    final shelf = _findRenderer(r.data, 'musicPlaylistShelfRenderer');
    for (final raw in await _api._continuationRows(
      shelf == null ? null : _continuationOf(shelf),
    )) {
      _collectEntries(raw, out);
    }
    return out;
  }

  @override
  Future<bool> addVideo(String playlistId, String videoId) async {
    final r = await _api._send('browse/edit_playlist', {
      ..._api._context,
      'playlistId': playlistId,
      'actions': [
        {
          'action': 'ACTION_ADD_VIDEO',
          'addedVideoId': videoId,
          // Second line of defence behind the entries() check: a retry after
          // a lost response must not add the track twice.
          'dedupeOption': 'DEDUPE_OPTION_SKIP',
        },
      ],
    });
    if (_isGone(r.status)) throw const YtPlaylistGone();
    return r.ok;
  }

  @override
  Future<bool> removeVideo(
    String playlistId,
    String videoId,
    String setVideoId,
  ) async {
    final r = await _api._send('browse/edit_playlist', {
      ..._api._context,
      'playlistId': playlistId,
      'actions': [
        {
          'action': 'ACTION_REMOVE_VIDEO',
          'removedVideoId': videoId,
          'setVideoId': setVideoId,
        },
      ],
    });
    if (_isGone(r.status)) throw const YtPlaylistGone();
    return r.ok;
  }
}

/// Raised by an edit when the playlist has been deleted on YouTube. The engine
/// reacts by forgetting its stored id and recreating.
class YtPlaylistGone implements Exception {
  const YtPlaylistGone();
}

/// Library tiles carry the browse id (`VLPL...`); edits want the bare id.
String _playlistIdOf(String browseId) =>
    browseId.startsWith('VL') ? browseId.substring(2) : browseId;

/// Pull `playlistItemData` (videoId + playlistSetVideoId) out of track rows.
/// Searched by key rather than walked to: first page and continuation rows
/// nest the same renderer at different depths.
void _collectEntries(Object? node, Map<String, String> out, [int depth = 0]) {
  if (depth > 24) return;
  if (node is Map) {
    final data = node['playlistItemData'];
    if (data is Map) {
      final v = data['videoId'];
      final s = data['playlistSetVideoId'];
      if (v is String && s is String && v.isNotEmpty && s.isNotEmpty) {
        out.putIfAbsent(v, () => s);
      }
    }
    for (final value in node.values) {
      _collectEntries(value, out, depth + 1);
    }
  } else if (node is List) {
    for (final value in node) {
      _collectEntries(value, out, depth + 1);
    }
  }
}

extension YtMusicWrites on YtMusicApi {
  /// POST that keeps the status. [_post] drops it, which is right for reads
  /// and wrong here. 5xx throws (Dio, via validateStatus), which is what the
  /// queue wants: a server hiccup is retryable.
  Future<_Reply> _send(String path, Map<String, dynamic> body) async {
    final auth = await _auth();
    final res = await _dio.post<Map<String, dynamic>>(
      '$_kBase/$path?prettyPrint=false',
      data: YtMusicApi._withVisitorData(body, auth['X-Goog-Visitor-Id']),
      options: _optionsWith(auth),
    );
    final status = res.statusCode ?? 0;
    // An expired session is not a verdict on the request. Throwing keeps the
    // op queued for after the user signs in again instead of dropping a like
    // that was perfectly valid.
    if (status == 401 || status == 403) throw StateError('auth $status');
    return _Reply(status, res.data);
  }
}
