// On-device InnerTube `/player` client — resolves YouTube Music
// stream URLs straight from the phone, with the user's YouTube cookies
// attached. The cookies are captured by `ytmusic_signin_screen.dart`
// when the user signs in once via a WebView.
//
// Why cookies are mandatory:
//   In 2024–2025 YouTube tightened the bot check so /player returns
//   `LOGIN_REQUIRED: "Sign in to confirm you're not a bot"` for
//   unauthenticated requests from ALL IPs — residential phone IPs
//   included. The fix is sending a logged-in cookie set (specifically
//   the SAPISID-derived Authorization header) so the request is
//   treated as an authenticated user, not a probe.
//
// Search stays server-side (`/ytmusic/search` in sunoh-api) — anonymous
// search isn't bot-checked. Only /player needs auth.
//
// Direct port of OuterTune's `YTPlayerUtils.playerResponseForPlayback`
// + `InnerTube.player(...)`:
//   - ANDROID_VR_NO_AUTH client config (lighter format set, unsigned URLs)
//   - cookie + SAPISIDHASH auth attached when available

import 'dart:convert' show utf8;

import 'package:crypto/crypto.dart' show sha1;
import 'package:dio/dio.dart';

const String _origin = 'https://music.youtube.com';
const String _playerUrl = '$_origin/youtubei/v1/player?prettyPrint=false';

/// YouTube Music context for the ANDROID_VR_NO_AUTH client — the one
/// OuterTune calls MAIN_CLIENT with the comment "Is temporally used
/// as it is out only working client". Niche Oculus Quest YT client
/// that hasn't been tightened with PoToken / bot-check requirements.
const Map<String, dynamic> _androidVrClient = {
  'clientName': 'ANDROID_VR',
  'clientVersion': '1.61.48',
  'clientId': '28',
  'osVersion': '12',
  // gl + hl let YT pick a region; IN matches the rest of the app.
  'gl': 'IN',
  'hl': 'en',
};

const String _androidVrUserAgent =
    'com.google.android.apps.youtube.vr.oculus/1.61.48 '
    '(Linux; U; Android 12; en_US; Oculus Quest 3; '
    'Build/SQ3A.220605.009.A1; Cronet/132.0.6808.3)';

/// Resolved stream URL plus the bits the caller can use to drive UI
/// (title in the now-playing strip while the track is still loading,
/// duration shown in the scrubber).
class YouTubeMusicStream {
  const YouTubeMusicStream({
    required this.url,
    required this.mimeType,
    required this.bitrate,
    required this.expiresAt,
    this.title,
    this.artist,
    this.durationSeconds,
  });
  final String url;
  final String mimeType;
  final int bitrate;
  /// Epoch seconds the URL is expected to remain valid until. Read
  /// from YouTube's `streamingData.expiresInSeconds`. URLs are
  /// typically valid for ~6 h; we trust the value the server gives.
  final int expiresAt;
  final String? title;
  final String? artist;
  final int? durationSeconds;
}

/// Thrown when YouTube refuses to return a playable URL — typically
/// `LOGIN_REQUIRED` ("Sign in to confirm you're not a bot") on a flagged
/// IP, or `UNPLAYABLE` for region-locked / removed content. Surfaced to
/// the stream resolver so the user-facing toast names the actual reason.
class YouTubeMusicResolveException implements Exception {
  YouTubeMusicResolveException(this.message, {this.status});
  final String message;
  final String? status;

  @override
  String toString() =>
      status == null ? message : '$message (status=$status)';
}

/// Parse the raw `name=value; name=value; …` cookie header into a map
/// for SAPISID lookup. Keys are case-sensitive; YouTube uses mixed
/// case (`SAPISID`, `__Secure-3PAPISID`, etc.).
Map<String, String> _parseCookies(String cookieHeader) {
  final out = <String, String>{};
  for (final part in cookieHeader.split(';')) {
    final i = part.indexOf('=');
    if (i <= 0) continue;
    out[part.substring(0, i).trim()] = part.substring(i + 1).trim();
  }
  return out;
}

/// Build the `Authorization: SAPISIDHASH …` header from a SAPISID
/// cookie. YouTube's web client computes this for every authed call:
/// `SHA1(${epochSeconds} ${SAPISID} ${origin})` keyed by the timestamp.
/// Returns null when neither SAPISID nor __Secure-3PAPISID is present.
String? _buildSapisidHashAuth(String cookieHeader) {
  final cookies = _parseCookies(cookieHeader);
  final sapisid = cookies['SAPISID'] ?? cookies['__Secure-3PAPISID'];
  if (sapisid == null || sapisid.isEmpty) return null;
  final t = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final digest = sha1.convert(utf8.encode('$t $sapisid $_origin')).toString();
  return 'SAPISIDHASH ${t}_$digest';
}

/// Resolve a video id → playable audio URL by hitting InnerTube
/// directly from the device. [cookieHeader], when provided, is the
/// raw cookie string the user captured during the sign-in flow —
/// without it, YouTube returns `LOGIN_REQUIRED` on every request
/// today (regardless of IP). The function is pure; caller supplies
/// the cookie from `AppState.ytMusicCookie`.
Future<YouTubeMusicStream> resolveYouTubeMusicStream(
  String videoId, {
  String? cookieHeader,
}) async {
  if (cookieHeader == null || cookieHeader.isEmpty) {
    throw YouTubeMusicResolveException(
      'Not signed in to YouTube Music. '
      'Open Settings → Connect YouTube Music to sign in once.',
      status: 'NO_AUTH',
    );
  }

  // A fresh Dio instance per call — the request is heavyweight (single
  // POST + parse) and there's no per-host state worth carrying.
  // Connection pooling under-the-hood still kicks in for repeat hits
  // because Dio uses the system HTTP client.
  final headers = <String, String>{
    'content-type': 'application/json',
    'x-goog-api-format-version': '1',
    'x-youtube-client-name': _androidVrClient['clientId'],
    'x-youtube-client-version': _androidVrClient['clientVersion'],
    'x-origin': _origin,
    'referer': '$_origin/',
    'user-agent': _androidVrUserAgent,
    'accept-language': 'en-US,en;q=0.9',
    'cookie': cookieHeader,
  };
  final auth = _buildSapisidHashAuth(cookieHeader);
  if (auth != null) headers['authorization'] = auth;

  final dio = Dio(BaseOptions(
    headers: headers,
    sendTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
  ));

  final Response<Map<String, dynamic>> res;
  try {
    res = await dio.post<Map<String, dynamic>>(
      _playerUrl,
      data: {
        'context': {
          'client': _androidVrClient,
          'user': {'lockedSafetyMode': false},
        },
        'videoId': videoId,
        // Marketing-app-style fields some clients require for premium
        // / age-restricted content. Harmless on others.
        'contentCheckOk': true,
        'racyCheckOk': true,
      },
    );
  } on DioException catch (e) {
    throw YouTubeMusicResolveException(
      'Network error talking to music.youtube.com: ${e.message}',
    );
  }

  final body = res.data;
  if (body == null) {
    throw YouTubeMusicResolveException('Empty /player response');
  }

  final status =
      (body['playabilityStatus'] as Map?)?['status']?.toString();
  if (status != null && status != 'OK') {
    final reason =
        (body['playabilityStatus'] as Map?)?['reason']?.toString() ?? '';
    throw YouTubeMusicResolveException(
      reason.isEmpty
          ? 'YouTube refused to play this track'
          : 'YouTube: $reason',
      status: status,
    );
  }

  final streamingData = body['streamingData'] as Map<String, dynamic>?;
  final adaptive = streamingData?['adaptiveFormats'];
  if (adaptive is! List || adaptive.isEmpty) {
    throw YouTubeMusicResolveException('No streaming formats returned');
  }

  // Highest-bitrate audio-only format, regardless of codec — same
  // pick rule as the server-side mapper. mpv handles both Opus
  // (webm) and AAC (mp4) natively.
  Map<String, dynamic>? best;
  int bestBitrate = -1;
  for (final raw in adaptive) {
    if (raw is! Map) continue;
    final fmt = raw.cast<String, dynamic>();
    final mime = (fmt['mimeType'] as String?) ?? '';
    if (!mime.startsWith('audio/')) continue;
    final url = (fmt['url'] as String?) ?? '';
    if (url.isEmpty) continue; // signed-URL formats — skip on this client
    final br = (fmt['averageBitrate'] as int?) ??
        (fmt['bitrate'] as int?) ??
        0;
    if (br > bestBitrate) {
      best = fmt;
      bestBitrate = br;
    }
  }
  if (best == null) {
    throw YouTubeMusicResolveException('No audio-only format found');
  }

  final expiresIn =
      int.tryParse((streamingData?['expiresInSeconds'] as String?) ?? '') ??
          21600;
  final videoDetails = body['videoDetails'] as Map<String, dynamic>?;
  final durRaw = videoDetails?['lengthSeconds'];
  final duration = durRaw is String ? int.tryParse(durRaw) : null;

  return YouTubeMusicStream(
    url: best['url'] as String,
    mimeType: (best['mimeType'] as String?) ?? '',
    bitrate: bestBitrate,
    expiresAt:
        DateTime.now().millisecondsSinceEpoch ~/ 1000 + expiresIn,
    title: videoDetails?['title'] as String?,
    artist: videoDetails?['author'] as String?,
    durationSeconds: duration,
  );
}
