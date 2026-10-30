// Fetching a Gaana track's waveform before it has been played.
//
// Gaana streams are HLS and mpv cannot decode HLS ahead, so its own envelope
// only fills behind the playhead. This pass downloads the song's smallest
// variant in the background, measures it natively (waveform_analyse.dart) and
// stores the result (waveform_store.dart), so the scrubber shows the whole
// song the first time it is opened, not only what has played.
//
// The lowest variant is enough: loudness over 400 bins does not change with
// bitrate, and the point is to cost as little data as possible. One fetch runs
// at a time, for the current track first and then the next in the queue, and
// is cancelled when the queue moves past both. A track that fails is not
// retried this session; one that was merely cancelled is.
//
// The "lowest" variant is still near full quality on Gaana (3.5 to 6 MB a
// song), so this doubles the data of every new song. It therefore runs only on
// an unmetered network (WaveformAnalyser.isMetered, asked of Android each
// time a song is considered) and never on the 'data' stream-quality setting.
// The skip is logged once per session, not per track.
//
// The signed stream URL is never logged; ids appear as a 4-character prefix.

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../api/dto.dart';
import '../api/stream_resolver.dart';
import 'hls_download.dart';
import 'waveform_analyse.dart';
import 'waveform_peaks.dart';

class WaveformAgent {
  WaveformAgent({
    required this.feed,
    required this.resolver,
    required Stream<FeedItem?> songs,
    required FeedItem? Function() next,
    WaveformAnalyser analyser = const WaveformAnalyser(),
    Dio? dio,
  }) : _next = next,
       _analyser = analyser,
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 10),
               receiveTimeout: const Duration(seconds: 20),
             ),
           ) {
    _sub = songs.listen(_onSong);
  }

  final WaveformFeed feed;
  final StreamResolver resolver;
  final FeedItem? Function() _next;
  final WaveformAnalyser _analyser;
  final Dio _dio;
  late final StreamSubscription<FeedItem?> _sub;

  final Set<String> _tried = {};
  List<FeedItem> _wanted = const [];
  CancelToken? _cancel;
  String? _running;
  bool _busy = false;
  bool _loggedSkip = false;

  void _onSong(FeedItem? current) {
    feed.songChanged(current?.id);
    final next = _next();
    _wanted = [?current, ?next];
    final running = _running;
    if (running != null && !_wanted.any((s) => s.id == running)) {
      _cancel?.cancel();
    }
    unawaited(_pump());
  }

  bool _eligible(FeedItem song) =>
      song.source == 'gaana' &&
      !_tried.contains(song.id) &&
      !feed.hasComplete(song.id) &&
      resolver.quality != StreamQuality.data;

  /// Whether data may be spent on a fetch now.
  Future<bool> _allowed() async {
    final metered = await _analyser.isMetered();
    if (metered && !_loggedSkip) {
      _loggedSkip = true;
      debugPrint('[waveform] fetch-ahead off: metered network');
    }
    return !metered;
  }

  Future<void> _pump() async {
    if (_busy) return;
    _busy = true;
    try {
      while (true) {
        final job = _wanted.where(_eligible).firstOrNull;
        if (job == null) break;
        // Not marked tried: a later song, on Wi-Fi, is considered afresh.
        if (!await _allowed()) break;
        _tried.add(job.id);
        await _run(job);
      }
    } finally {
      _busy = false;
    }
  }

  bool _stillWanted(String id) => _wanted.any((s) => s.id == id);

  Future<void> _run(FeedItem song) async {
    final tag = song.id.length > 4 ? song.id.substring(0, 4) : song.id;
    final cancel = _cancel = CancelToken();
    _running = song.id;
    File? file;
    try {
      final url = (await resolver.resolve(song)).url;
      // A download or a local file resolves to something that is not HLS.
      if (!(Uri.tryParse(url)?.path.endsWith('.m3u8') ?? false)) return;
      if (!_stillWanted(song.id)) {
        _tried.remove(song.id);
        return;
      }
      final dir = await getTemporaryDirectory();
      file = File('${dir.path}/wf_${song.id.hashCode}.ts');
      debugPrint('[waveform] fetching ahead $tag (lowest variant)');
      final bytes = await HlsDownloader(_dio).download(
        masterUrl: url,
        toPath: file.path,
        cancel: cancel,
        onProgress: (_, _) {},
        lowestBitrate: true,
      );
      final measured = await _analyser.measure(file.path);
      if (measured == null) {
        debugPrint('[waveform] could not measure $tag');
        return;
      }
      feed.ingest(song.id, measured);
      debugPrint('[waveform] measured $tag (${(bytes / 1024).round()} KiB)');
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) _tried.remove(song.id);
      // The type only: a DioException's message carries the signed URL.
      debugPrint('[waveform] fetch failed for $tag: ${e.runtimeType}');
    } finally {
      _running = null;
      try {
        if (file != null && file.existsSync()) file.deleteSync();
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    _cancel?.cancel();
    await _sub.cancel();
  }
}
