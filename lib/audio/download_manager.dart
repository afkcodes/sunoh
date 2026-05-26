// DownloadManager — the runtime brain behind offline-cache.
//
// Responsibilities:
//   * Resolves a song's stream URL (via the existing StreamResolver) and
//     downloads it to `<docs>/downloads/<songId>.<ext>` with Dio.
//   * Caps concurrent downloads (default 2) so the queue can be primed
//     with a whole album without hammering the network.
//   * Persists per-entry state in [DownloadStore] so a restart picks up
//     the same downloaded library.
//   * Exposes a [LocalSourceProvider] that the resolver consults BEFORE
//     hitting the network — once a song's `state == done`, playback
//     skips the network round-trip entirely.
//   * Broadcasts live progress (bytesDownloaded over bytesTotal) so the
//     UI can render a per-row progress ring without polling Hive.
//
// What it deliberately does NOT do (yet):
//   * Range / resume on a half-finished file. Failed downloads start over.
//   * WiFi-only gating. Easy to add — see [downloadOptions] todo below.
//   * Background continuation when the app is killed. The audio_service
//     foreground service keeps us alive during playback; downloads
//     happen "while the app is open" for now.

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../api/dto.dart';
import '../api/stream_resolver.dart';
import 'download_store.dart';

/// Snapshot of a single in-flight download. Pushed onto [progressStream]
/// on every Dio chunk callback (throttled to ~10 Hz to keep the UI
/// readable). UI widgets keyed by [songId] just take the latest.
class DownloadProgress {
  const DownloadProgress({
    required this.songId,
    required this.received,
    required this.total,
  });
  final String songId;
  final int received;
  final int total;
  double get fraction => total <= 0 ? 0 : (received / total).clamp(0.0, 1.0);
}

class DownloadManager implements LocalSourceProvider {
  DownloadManager({
    required this.resolver,
    required this.store,
    Dio? dio,
    this.maxConcurrent = 2,
  }) : _dio = dio ?? Dio();

  final StreamResolver resolver;
  final DownloadStore store;
  final Dio _dio;
  final int maxConcurrent;

  /// All entries currently known to the manager. Mirrors [store] in
  /// memory so UI providers can subscribe without an async box read on
  /// every rebuild. Keys are song ids.
  final Map<String, DownloadEntry> _entries = <String, DownloadEntry>{};

  /// FIFO of song ids waiting on a free slot. New requests get appended;
  /// the manager drains it whenever an active slot finishes.
  final List<String> _pending = <String>[];

  /// Cancel tokens for each active download — used when the user removes
  /// or pauses an entry mid-download.
  final Map<String, CancelToken> _active = <String, CancelToken>{};

  /// Emits an entry whenever its state or stored bytes change. Wider than
  /// [progressStream] (one event per chunk vs one per state transition)
  /// so UI can rebuild list rows on add/remove/done.
  final StreamController<DownloadEntry> _entryEvents =
      StreamController<DownloadEntry>.broadcast();
  Stream<DownloadEntry> get entryEvents => _entryEvents.stream;

  /// Per-chunk progress for the currently-downloading songs.
  final StreamController<DownloadProgress> _progressEvents =
      StreamController<DownloadProgress>.broadcast();
  Stream<DownloadProgress> get progressStream => _progressEvents.stream;

  /// Initialise: load every persisted entry into memory + repair any
  /// crashed-mid-download rows (left as `downloading` from the previous
  /// session) by flipping them to `failed` so the user can retry.
  Future<void> init() async {
    final all = await store.all();
    for (final e in all) {
      var entry = e;
      if (entry.state == DownloadState.downloading) {
        entry = entry.copyWith(
            state: DownloadState.failed,
            error: 'Interrupted by app restart');
        await store.put(entry);
      }
      _entries[entry.id] = entry;
    }
    debugPrint('[downloads] init complete — ${_entries.length} entries');
  }

  // ── LocalSourceProvider ─────────────────────────────────────────────────

  @override
  Future<String?> localUrlFor(String songId) async {
    final entry = _entries[songId];
    if (entry == null || entry.state != DownloadState.done) return null;
    // Verify the file is still on disk — the user may have nuked the
    // app's documents dir, restored from a backup that doesn't include
    // the audio cache, etc. Don't return a file:// path that won't open.
    if (!await File(entry.localPath).exists()) return null;
    return Uri.file(entry.localPath).toString();
  }

  // ── Public API ──────────────────────────────────────────────────────────

  /// Current snapshot — UI providers subscribe to [entryEvents] to stay
  /// in sync after this.
  List<DownloadEntry> snapshot() {
    final list = _entries.values.toList();
    list.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return list;
  }

  DownloadEntry? entryFor(String songId) => _entries[songId];

  /// Queue a song for download. Idempotent for `done` / in-flight rows.
  /// Returns the resulting entry (existing or newly created).
  Future<DownloadEntry> enqueue(FeedItem song,
      {String quality = 'high'}) async {
    final existing = _entries[song.id];
    if (existing != null) {
      if (existing.state == DownloadState.done ||
          existing.state == DownloadState.downloading ||
          existing.state == DownloadState.queued) {
        return existing;
      }
      // Retry path — was failed/paused.
    }
    final docs = await getApplicationDocumentsDirectory();
    final dlDir = Directory('${docs.path}/downloads');
    if (!await dlDir.exists()) {
      await dlDir.create(recursive: true);
    }
    // Filename uses song id only — extension is filled in once we know
    // the resolved URL's content type (saavn typically m4a, gaana m3u8).
    // Stored path is the *final* file path; the temp file we Dio into
    // matches plus a `.part` suffix until completion.
    final entry = DownloadEntry(
      song: song,
      state: DownloadState.queued,
      localPath: '${dlDir.path}/${song.id}',
      quality: quality,
      addedAt: DateTime.now().millisecondsSinceEpoch,
    );
    _entries[song.id] = entry;
    await store.put(entry);
    _entryEvents.add(entry);
    _pending.add(song.id);
    _drain();
    return entry;
  }

  /// Cancel an in-flight download OR remove a `done` entry + its file.
  Future<void> remove(String songId) async {
    final token = _active.remove(songId);
    token?.cancel('removed');

    final entry = _entries.remove(songId);
    _pending.remove(songId);
    await store.remove(songId);
    if (entry != null) {
      try {
        final f = File(entry.localPath);
        if (await f.exists()) await f.delete();
        final part = File('${entry.localPath}.part');
        if (await part.exists()) await part.delete();
      } catch (e) {
        debugPrint('[downloads] file delete failed for $songId: $e');
      }
      _entryEvents.add(entry.copyWith(state: DownloadState.failed));
    }
    _drain();
  }

  /// Stop an active download without deleting its entry. The row stays
  /// in `paused` so the user can resume later.
  Future<void> pause(String songId) async {
    final token = _active.remove(songId);
    token?.cancel('paused');
    final entry = _entries[songId];
    if (entry == null) return;
    final next = entry.copyWith(state: DownloadState.paused);
    _entries[songId] = next;
    await store.put(next);
    _entryEvents.add(next);
    _drain();
  }

  /// Re-queue a `failed` or `paused` entry.
  Future<void> resume(String songId) async {
    final entry = _entries[songId];
    if (entry == null) return;
    if (entry.state == DownloadState.downloading ||
        entry.state == DownloadState.queued ||
        entry.state == DownloadState.done) {
      return;
    }
    final next = entry.copyWith(state: DownloadState.queued, error: null);
    _entries[songId] = next;
    await store.put(next);
    _entryEvents.add(next);
    if (!_pending.contains(songId)) _pending.add(songId);
    _drain();
  }

  /// Re-enable bulk + single API to be discovered ergonomically.
  Future<void> enqueueAll(Iterable<FeedItem> songs,
      {String quality = 'high'}) async {
    for (final s in songs) {
      await enqueue(s, quality: quality);
    }
  }

  // ── Internals ───────────────────────────────────────────────────────────

  void _drain() {
    while (_active.length < maxConcurrent && _pending.isNotEmpty) {
      final id = _pending.removeAt(0);
      final entry = _entries[id];
      if (entry == null) continue;
      if (entry.state != DownloadState.queued) continue;
      unawaited(_download(entry));
    }
  }

  Future<void> _download(DownloadEntry entryIn) async {
    final cancel = CancelToken();
    _active[entryIn.id] = cancel;

    // Mark as in-flight.
    var entry = entryIn.copyWith(state: DownloadState.downloading);
    _entries[entry.id] = entry;
    await store.put(entry);
    _entryEvents.add(entry);

    try {
      // Resolve to a playable URL (same path mpv would take, so the
      // downloaded file is byte-for-byte the network stream). The
      // resolver also pulls embedded mediaUrls / enriched metadata.
      final resolved = await resolver.resolve(entry.song);
      final url = resolved.url;
      final urlForExt = url.toLowerCase();
      // Pick a safe extension. Default to .m4a (saavn's typical aac/m4a
      // container); HLS playlists (.m3u8) aren't downloaded as a single
      // file, so we currently skip them with a friendly error.
      String ext = '.m4a';
      if (urlForExt.contains('.mp3')) {
        ext = '.mp3';
      } else if (urlForExt.contains('.m4a')) {
        ext = '.m4a';
      } else if (urlForExt.contains('.aac')) {
        ext = '.aac';
      } else if (urlForExt.contains('.opus')) {
        ext = '.opus';
      } else if (urlForExt.contains('.m3u8') ||
          urlForExt.contains('hls')) {
        throw const _UnsupportedHlsException();
      }
      final finalPath = '${entry.localPath}$ext';
      final partPath = '$finalPath.part';

      // Download to .part then rename atomically — the resolver checks
      // existence on the final path, so a half-written file is never
      // visible to playback.
      await _dio.download(
        url,
        partPath,
        cancelToken: cancel,
        options: Options(responseType: ResponseType.bytes),
        onReceiveProgress: (received, total) {
          if (received <= 0) return;
          _progressEvents.add(DownloadProgress(
            songId: entry.id,
            received: received,
            total: total,
          ));
        },
      );

      final partFile = File(partPath);
      final size = await partFile.length();
      await partFile.rename(finalPath);

      entry = entry.copyWith(
        state: DownloadState.done,
        localPath: finalPath,
        bytesTotal: size,
        error: null,
      );
      _entries[entry.id] = entry;
      await store.put(entry);
      _entryEvents.add(entry);
    } on _UnsupportedHlsException {
      entry = entry.copyWith(
        state: DownloadState.failed,
        error: 'HLS streams aren’t downloadable yet',
      );
      _entries[entry.id] = entry;
      await store.put(entry);
      _entryEvents.add(entry);
    } catch (e, st) {
      // Cancels show up as DioException with type=cancel — we already
      // flipped state to paused/removed in those code paths, so don't
      // overwrite with `failed`.
      if (cancel.isCancelled) {
        debugPrint('[downloads] cancelled ${entry.id} (${cancel.cancelError?.message})');
      } else {
        debugPrint('[downloads] failed ${entry.id}: $e\n$st');
        entry = entry.copyWith(
          state: DownloadState.failed,
          error: '$e',
        );
        _entries[entry.id] = entry;
        await store.put(entry);
        _entryEvents.add(entry);
      }
    } finally {
      _active.remove(entry.id);
      _drain();
    }
  }
}

class _UnsupportedHlsException implements Exception {
  const _UnsupportedHlsException();
  @override
  String toString() => 'HLS playlists are not single-file downloadable';
}
