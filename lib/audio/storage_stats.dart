// On-disk usage summary, surfaced in Settings → Library → Storage.
// Walks the Hive box files + the OS temp dir (where cached_network_image
// drops decoded artwork via flutter_cache_manager).

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

class StorageStats {
  const StorageStats({
    required this.hiveBytes,
    required this.imageBytes,
  });
  final int hiveBytes;
  final int imageBytes;

  int get totalBytes => hiveBytes + imageBytes;

  static const empty = StorageStats(hiveBytes: 0, imageBytes: 0);
}

/// Compute current on-disk usage. Returns 0s for any segment we can't
/// reach (permissions, filesystem oddities) — caller renders something
/// reasonable either way.
Future<StorageStats> computeStorageStats() async {
  return StorageStats(
    hiveBytes: await _hiveBoxSize(),
    imageBytes: await _imageCacheSize(),
  );
}

/// Wipe the cached_network_image cache (file system + in-memory copy).
/// Hive data is intentionally NOT touched — library, liked songs, queue,
/// and settings survive.
Future<void> clearImageCache() async {
  try {
    await DefaultCacheManager().emptyCache();
    // Also drop any decoded images held in the global Image cache so the
    // next render goes through the resolver again. Without this, freshly-
    // emptied disk-cache items can re-appear from RAM until the user
    // scrolls them out of view.
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  } catch (e) {
    debugPrint('[storage] clearImageCache failed: $e');
  }
}

Future<int> _hiveBoxSize() async {
  var total = 0;
  // Iterate the boxes we actually use; if a box hasn't been opened yet
  // this session, its on-disk size doesn't count toward "right now" —
  // matches the intuitive "what is sunoh using right now" question.
  for (final name in const ['playback', 'settings', 'library']) {
    try {
      if (!Hive.isBoxOpen(name)) continue;
      final box = Hive.box(name);
      final p = box.path;
      if (p == null) continue;
      final f = File(p);
      if (await f.exists()) total += await f.length();
    } catch (e) {
      debugPrint('[storage] box "$name" size unknown: $e');
    }
  }
  return total;
}

Future<int> _imageCacheSize() async {
  try {
    // flutter_cache_manager stores files under the platform temp dir's
    // `libCachedImageData/` subfolder by default. We sum every regular
    // file beneath it.
    final tempDir = await getTemporaryDirectory();
    final cacheDir = Directory('${tempDir.path}/libCachedImageData');
    if (!await cacheDir.exists()) return 0;
    var total = 0;
    await for (final entity
        in cacheDir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } catch (_) {/* skip transient files */}
      }
    }
    return total;
  } catch (e) {
    debugPrint('[storage] image cache size unknown: $e');
    return 0;
  }
}

/// Compact human-friendly byte count. Avoids the `intl` dep — we just
/// pick the largest unit that keeps the number under 1000.
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var idx = 0;
  while (value >= 1024 && idx < units.length - 1) {
    value /= 1024;
    idx += 1;
  }
  final fmt = value >= 100 || idx == 0
      ? value.toStringAsFixed(0)
      : value >= 10
          ? value.toStringAsFixed(1)
          : value.toStringAsFixed(2);
  return '$fmt ${units[idx]}';
}
