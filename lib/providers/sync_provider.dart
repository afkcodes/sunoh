// Riverpod surface for library sync.
//
// A ChangeNotifier because sync has more states than loading/loaded: it can be
// off, configured but never run, syncing, or blocked because the folder grant
// was revoked, and each needs something different said to the user.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../audio/audio_repo.dart';
import '../sync/sync_service.dart';

final syncProvider = ChangeNotifierProvider<SyncService>((ref) {
  final repo = ref.watch(audioRepoProvider);
  final service = SyncService(library: repo.library, settings: repo.settings);
  // Restore configuration off the first frame; a folder behind a cloud
  // provider can block for a moment and must not stall the build that made it.
  WidgetsBinding.instance.addPostFrameCallback((_) => service.restore());
  return service;
});
