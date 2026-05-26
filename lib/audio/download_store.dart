// Hive-backed persistence for downloaded songs.
//
// One box named 'downloads'. Each entry is keyed by song id and stores:
//   - songJson:     the original FeedItem (so the Downloads screen has
//                   title/artist/artwork without another API hop)
//   - localPath:    absolute path to the on-disk audio file
//   - quality:      'high' / 'medium' / 'low' (informational; respects
//                   the user's Settings → Download quality at the time)
//   - bytesTotal:   final file size in bytes (filled on completion)
//   - state:        'done' / 'queued' / 'downloading' / 'paused' / 'failed'
//   - error:        optional error message when state == 'failed'
//   - addedAt:      ms-since-epoch the entry first appeared in the box
//
// Live progress (bytesDownloaded over time) is broadcast separately by
// DownloadManager so we don't thrash the disk on every chunk.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../api/dto.dart';

enum DownloadState { queued, downloading, paused, done, failed }

extension DownloadStateName on DownloadState {
  String get persistName => name;
  static DownloadState parse(String? raw) {
    if (raw == null) return DownloadState.queued;
    for (final s in DownloadState.values) {
      if (s.name == raw) return s;
    }
    return DownloadState.queued;
  }
}

/// In-memory + on-disk shape of a single download record. The store
/// returns these from `get` / `all`; the manager mutates state and
/// writes back via `put`.
@immutable
class DownloadEntry {
  const DownloadEntry({
    required this.song,
    required this.state,
    required this.localPath,
    required this.quality,
    required this.addedAt,
    this.bytesTotal = 0,
    this.error,
  });

  final FeedItem song;
  final DownloadState state;
  final String localPath;
  final String quality;
  final int addedAt;
  final int bytesTotal;
  final String? error;

  /// Stable id — every consumer keys off songId.
  String get id => song.id;

  DownloadEntry copyWith({
    DownloadState? state,
    String? localPath,
    int? bytesTotal,
    String? quality,
    String? error,
  }) {
    return DownloadEntry(
      song: song,
      state: state ?? this.state,
      localPath: localPath ?? this.localPath,
      quality: quality ?? this.quality,
      addedAt: addedAt,
      bytesTotal: bytesTotal ?? this.bytesTotal,
      error: error,
    );
  }

  Map<String, dynamic> toMap() => {
        'songJson': song.toJson(),
        'state': state.persistName,
        'localPath': localPath,
        'quality': quality,
        'addedAt': addedAt,
        'bytesTotal': bytesTotal,
        'error': error,
      };

  static DownloadEntry? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final m = raw.cast<String, dynamic>();
    final songMap = m['songJson'];
    if (songMap is! Map) return null;
    return DownloadEntry(
      song: FeedItem.fromJson(songMap.cast<String, dynamic>()),
      state: DownloadStateName.parse(m['state'] as String?),
      localPath: (m['localPath'] ?? '') as String,
      quality: (m['quality'] ?? 'high') as String,
      addedAt: (m['addedAt'] as num?)?.toInt() ?? 0,
      bytesTotal: (m['bytesTotal'] as num?)?.toInt() ?? 0,
      error: m['error'] as String?,
    );
  }
}

class DownloadStore {
  DownloadStore();

  static const _boxName = 'downloads';

  Future<Box>? _opening;

  Future<Box> _box() async {
    if (Hive.isBoxOpen(_boxName)) return Hive.box(_boxName);
    return _opening ??= _openOnce();
  }

  Future<Box> _openOnce() async {
    Box box;
    try {
      box = await Hive.openBox(_boxName);
    } catch (e, st) {
      // ignore: avoid_print
      print('[downloads-store] ⚠ openBox("$_boxName") FAILED: $e\n$st\n'
          '[downloads-store] deleting corrupted box and retrying…');
      try {
        await Hive.deleteBoxFromDisk(_boxName);
      } catch (_) {}
      box = await Hive.openBox(_boxName);
    }
    int bytes = -1;
    try {
      final p = box.path;
      if (p != null) {
        final f = File(p);
        if (await f.exists()) bytes = await f.length();
      }
    } catch (_) {}
    // ignore: avoid_print
    print('[downloads-store] opened "$_boxName" at ${box.path} '
        '(file=${bytes}b) — entries=${box.length}');
    return box;
  }

  Future<List<DownloadEntry>> all() async {
    final box = await _box();
    final out = <DownloadEntry>[];
    for (final v in box.values) {
      final e = DownloadEntry.fromMap(v);
      if (e != null) out.add(e);
    }
    // Newest first — addedAt is ms-since-epoch.
    out.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return out;
  }

  Future<DownloadEntry?> get(String songId) async {
    final box = await _box();
    return DownloadEntry.fromMap(box.get(songId));
  }

  Future<void> put(DownloadEntry entry) async {
    final box = await _box();
    await box.put(entry.id, entry.toMap());
    await box.flush();
  }

  Future<void> remove(String songId) async {
    final box = await _box();
    await box.delete(songId);
    await box.flush();
  }

  /// Fast existence check used by the LocalSourceProvider hot path. Reads
  /// directly off the open box without rebuilding the DownloadEntry — the
  /// resolver only cares about the local file path.
  Future<String?> localPathOf(String songId) async {
    final box = await _box();
    final raw = box.get(songId);
    if (raw is! Map) return null;
    final state = raw['state'];
    if (state != DownloadState.done.persistName) return null;
    final p = raw['localPath'];
    return (p is String && p.isNotEmpty) ? p : null;
  }
}
