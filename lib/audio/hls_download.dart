// Downloading an HLS stream as one playable file.
//
// Gaana ships its audio as HLS — a playlist of six-second MPEG-TS segments —
// where saavn ships a single .m4a. Dio can fetch a file; it cannot fetch a
// playlist, so gaana songs were refused with "HLS streams aren't downloadable
// yet" and the download action was hidden on every gaana row.
//
// It turns out to need no more than this file. MPEG-TS is designed to be
// concatenated: writing the segments end to end produces a valid stream that
// mpv plays directly. Verified against a real track before this was written —
// 55 segments appended came back from ffprobe as `mpegts, aac, 44100 Hz,
// stereo, 329.5s`, the complete song. No remux, no ffmpeg, no new dependency.
//
// Encryption is the case this deliberately does not handle. Gaana's playlists
// carry no EXT-X-KEY, and rather than half-implement AES-128 HLS against a
// provider that does not use it, an encrypted playlist is refused with a clear
// reason. If some provider starts encrypting, this fails loudly instead of
// writing a file of undecryptable bytes that fails much later at playback.

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Thrown when a playlist cannot be turned into a file. The message reaches
/// the download row, so it says what is wrong rather than "failed".
class HlsUnsupported implements Exception {
  const HlsUnsupported(this.reason);
  final String reason;
  @override
  String toString() => reason;
}

class HlsDownloader {
  const HlsDownloader(this._dio);
  final Dio _dio;

  /// Fetch [masterUrl] and write the whole stream to [toPath].
  ///
  /// [onProgress] counts segments rather than bytes: an HLS download has no
  /// Content-Length for the whole thing, and segments are close enough to
  /// uniform that "18 of 55" is both honest and smooth. Returns the byte size
  /// of the finished file.
  Future<int> download({
    required String masterUrl,
    required String toPath,
    required CancelToken cancel,
    required void Function(int done, int total) onProgress,
  }) async {
    final playlistUrl = await _mediaPlaylistUrl(masterUrl, cancel);
    final playlist = await _text(playlistUrl, cancel);

    if (playlist.contains('#EXT-X-KEY')) {
      throw const HlsUnsupported('This track is encrypted and can’t be saved');
    }

    final segments = _uris(
      playlist,
    ).map((u) => Uri.parse(playlistUrl).resolve(u).toString()).toList();
    if (segments.isEmpty) {
      throw const HlsUnsupported('This track’s playlist was empty');
    }

    final file = File(toPath);
    // Append mode, one open handle for the whole run: reopening per segment
    // would be dozens of syscalls for no benefit, and a half-written file is
    // never visible because the caller writes to `.part` and renames.
    final sink = file.openWrite(mode: FileMode.write);
    var written = 0;
    try {
      for (var i = 0; i < segments.length; i++) {
        final bytes = await _bytes(segments[i], cancel);
        sink.add(bytes);
        written += bytes.length;
        onProgress(i + 1, segments.length);
      }
    } finally {
      await sink.close();
    }
    debugPrint(
      '[downloads] hls wrote ${segments.length} segments, '
      '${(written / 1024).round()} KiB',
    );
    return written;
  }

  /// The media playlist to pull segments from.
  ///
  /// A master playlist lists variants; a media playlist lists segments. Both
  /// arrive at this URL depending on the provider, so the shape is detected
  /// rather than assumed. When it is a master, the highest bandwidth wins:
  /// a download is kept, so it is worth its size in a way a stream on mobile
  /// data is not.
  Future<String> _mediaPlaylistUrl(String masterUrl, CancelToken cancel) async {
    final text = await _text(masterUrl, cancel);
    if (!text.contains('#EXT-X-STREAM-INF')) return masterUrl;

    final lines = text.split('\n');
    var bestBandwidth = -1;
    String? bestUri;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (!line.startsWith('#EXT-X-STREAM-INF')) continue;
      final match = RegExp(r'BANDWIDTH=(\d+)').firstMatch(line);
      final bandwidth = int.tryParse(match?.group(1) ?? '') ?? 0;
      // The URI is the next line that is neither blank nor a tag.
      for (var j = i + 1; j < lines.length; j++) {
        final candidate = lines[j].trim();
        if (candidate.isEmpty || candidate.startsWith('#')) continue;
        if (bandwidth > bestBandwidth) {
          bestBandwidth = bandwidth;
          bestUri = candidate;
        }
        break;
      }
    }
    if (bestUri == null) {
      throw const HlsUnsupported('This track’s playlist had no streams');
    }
    return Uri.parse(masterUrl).resolve(bestUri).toString();
  }

  /// Playlist lines that are neither blank nor tags — the segment URIs.
  static List<String> _uris(String playlist) => [
    for (final line in playlist.split('\n'))
      if (line.trim().isNotEmpty && !line.trim().startsWith('#')) line.trim(),
  ];

  Future<String> _text(String url, CancelToken cancel) async {
    final res = await _dio.get<String>(
      url,
      cancelToken: cancel,
      options: Options(responseType: ResponseType.plain),
    );
    final body = res.data;
    if (body == null || body.isEmpty) {
      throw const HlsUnsupported('This track’s playlist could not be read');
    }
    return body;
  }

  Future<List<int>> _bytes(String url, CancelToken cancel) async {
    final res = await _dio.get<List<int>>(
      url,
      cancelToken: cancel,
      options: Options(responseType: ResponseType.bytes),
    );
    return res.data ?? const [];
  }
}
