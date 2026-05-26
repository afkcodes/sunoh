// Riverpod surface for the download layer.
//
// `downloadManagerProvider` is overridden in `main.dart` with the singleton
// built at startup (next to AudioRepo). Everything else in the app reads
// off these providers — keeps the manager constructible-once and means a
// missed init wouldn't accidentally spin up a second instance later.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/download_manager.dart';
import '../audio/download_store.dart';

/// Overridden in main.dart. Read it via `ref.read(downloadManagerProvider)`
/// — `ref.watch` is rarely useful since the manager itself doesn't expose
/// rebuild-worthy state (subscribe to its streams instead).
final downloadManagerProvider = Provider<DownloadManager>(
  (_) => throw UnimplementedError(
      'downloadManagerProvider must be overridden in main.dart'),
);

/// Reactive list of every download in flight + on disk. Subscribes to
/// `entryEvents` so add/remove/state transitions reach the UI immediately
/// — but NOT per-byte progress (use [downloadProgressProvider] for that;
/// rebuilding a list on every Dio chunk would tank the frame budget).
final downloadEntriesProvider =
    StreamProvider.autoDispose<List<DownloadEntry>>((ref) async* {
  final mgr = ref.watch(downloadManagerProvider);
  // Initial snapshot up front so the first frame has data.
  yield mgr.snapshot();
  await for (final _ in mgr.entryEvents) {
    yield mgr.snapshot();
  }
});

/// Per-song live progress, throttled by Dio's chunk callback. Family key
/// is the songId — widgets that show a progress ring on one row only
/// listen to their own song.
final downloadProgressProvider =
    StreamProvider.autoDispose.family<DownloadProgress, String>(
  (ref, songId) {
    final mgr = ref.watch(downloadManagerProvider);
    return mgr.progressStream.where((p) => p.songId == songId);
  },
);

/// Convenience accessor for the single entry of a song. UI rows use this
/// to render the right glyph (cloud-download / spinner / check / retry).
DownloadEntry? watchDownloadEntry(WidgetRef ref, String songId) {
  final entries = ref.watch(downloadEntriesProvider).asData?.value;
  if (entries == null) return null;
  for (final e in entries) {
    if (e.id == songId) return e;
  }
  return null;
}
