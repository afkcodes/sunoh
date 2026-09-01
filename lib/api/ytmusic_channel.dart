// Dart side of the native YouTube Music stream resolver.
//
// Why native: YouTube gates its music catalog ("- Topic" / Art Track uploads)
// behind a BotGuard bot check. Probing the whole InnerTube client ladder shows
// no client returns playable audio for those tracks unauthenticated — every
// one answers LOGIN_REQUIRED / UNPLAYABLE "Sign in to confirm you're not a
// bot" — even though ordinary videos resolve fine. Clearing it needs a PO
// token minted by running Google's obfuscated BotGuard JS in a real WebView,
// which Dart can't do. So resolution lives in Kotlin (see
// android/.../ytmusic/YtMusicBridge.kt) and we just receive a playable URL.
//
// Android-only. Every method degrades to null / no-op elsewhere so callers
// don't need platform checks.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A resolved YouTube Music audio stream.
class YtMusicStream {
  const YtMusicStream({
    required this.url,
    required this.headers,
    this.itag,
    this.mimeType,
    this.bitrate,
    this.contentLength,
    this.loudnessDb,
    this.clientName,
    this.expiresAt,
    this.requireBoundedRange = false,
    this.rangeChunkSizeBytes = 0,
    this.useRangeChunks = false,
  });

  /// Direct `googlevideo.com` URL. SABR is refused natively, so this is always
  /// a plain URL mpv can open — never a SABR/protobuf endpoint.
  final String url;

  /// Headers the media fetch must carry. The URL is signed against the client
  /// that minted it, so the User-Agent has to match.
  final Map<String, String> headers;

  final int? itag;
  final String? mimeType;
  final int? bitrate;
  final int? contentLength;

  /// Track loudness, for future volume normalisation. Not applied yet.
  final double? loudnessDb;

  /// Which InnerTube client won the fallback ladder. Useful in logs when
  /// diagnosing "works for some tracks only".
  final String? clientName;

  final DateTime? expiresAt;

  /// Whether the upstream wants explicit bounded byte ranges. mpv drives its
  /// own range requests; surfaced for diagnostics because unranged reads are
  /// measurably throttled by googlevideo.
  final bool requireBoundedRange;
  final int rangeChunkSizeBytes;
  final bool useRangeChunks;

  static YtMusicStream? fromMap(Map<Object?, Object?>? m) {
    if (m == null) return null;
    final url = m['url'] as String?;
    if (url == null || url.isEmpty) return null;
    final rawHeaders = m['headers'];
    final headers = <String, String>{};
    if (rawHeaders is Map) {
      rawHeaders.forEach((k, v) {
        if (k != null && v != null) headers[k.toString()] = v.toString();
      });
    }
    final expiresMs = (m['expiresAtMs'] as num?)?.toInt();
    return YtMusicStream(
      url: url,
      headers: headers,
      itag: (m['itag'] as num?)?.toInt(),
      mimeType: m['mimeType'] as String?,
      bitrate: (m['bitrate'] as num?)?.toInt(),
      contentLength: (m['contentLength'] as num?)?.toInt(),
      loudnessDb: (m['loudnessDb'] as num?)?.toDouble(),
      clientName: m['clientName'] as String?,
      expiresAt: expiresMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(expiresMs),
      requireBoundedRange: m['requireBoundedRange'] as bool? ?? false,
      rangeChunkSizeBytes: (m['rangeChunkSizeBytes'] as num?)?.toInt() ?? 0,
      useRangeChunks: m['useRangeChunks'] as bool? ?? false,
    );
  }

  @override
  String toString() =>
      'YtMusicStream(itag: $itag, ${bitrate ?? '?'}bps, client: $clientName, '
      'expires: $expiresAt)';
}

class YtMusicChannel {
  YtMusicChannel._();
  static final YtMusicChannel instance = YtMusicChannel._();

  static const MethodChannel _channel = MethodChannel(
    'codes.afk.sunoh/ytmusic',
  );

  bool get _supported => defaultTargetPlatform == TargetPlatform.android;

  /// Spin up the PO-token WebView ahead of first playback.
  ///
  /// A cold mint costs a WebView launch plus BotGuard evaluation (~2-5s).
  /// Calling this at startup moves that off the first play. Fire-and-forget:
  /// failure just means the first resolve pays the cost.
  Future<void> prewarm() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('prewarm');
      // ignore: avoid_print
      print('[ytmusic] prewarm complete');
    } catch (e) {
      // ignore: avoid_print
      print('[ytmusic] prewarm failed (non-fatal): $e');
    }
  }

  /// Resolve [videoId] to a playable audio stream, or null if it can't be
  /// resolved. Never throws — callers fall through to another source.
  ///
  /// [quality] mirrors the app's stream-quality setting: `auto` / `high` /
  /// `data`.
  Future<YtMusicStream?> resolve(
    String videoId, {
    String quality = 'auto',
  }) async {
    if (!_supported || videoId.isEmpty) return null;
    try {
      final res = await _channel.invokeMethod<Map<Object?, Object?>>(
        'resolve',
        {'videoId': videoId, 'quality': quality},
      );
      final stream = YtMusicStream.fromMap(res);
      // ignore: avoid_print
      print('[ytmusic] resolved $videoId -> $stream');
      return stream;
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('[ytmusic] resolve failed for $videoId: ${e.message}');
      return null;
    } catch (e) {
      // ignore: avoid_print
      print('[ytmusic] resolve error for $videoId: $e');
      return null;
    }
  }
}
