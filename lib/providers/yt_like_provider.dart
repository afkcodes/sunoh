// Wiring for syncing in-app likes to YouTube Music (see audio/yt_like_sync).
//
// Everything is read lazily inside closures. The API client depends on the
// locale, which depends on AppState, and AppState is what calls into this
// provider: resolving any of it eagerly here would be a dependency cycle.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/ytmusic_api.dart';
import '../audio/yt_like_store.dart';
import '../audio/yt_like_sync.dart';
import 'app_state_provider.dart';
import 'yt_auth_provider.dart';
import 'ytmusic_provider.dart';

// Explicitly typed: it closes a provider cycle through AppState, and Dart
// cannot infer a type that depends on itself.
final Provider<YtLikeSync> ytLikeSyncProvider = Provider<YtLikeSync>(
  (ref) => YtLikeSync(
    store: YtLikeStore(),
    remote: () => YtMusicLikeRemote(ref.read(ytMusicApiProvider)),
    isSignedIn: () => ref.read(ytAuthProvider).isSignedIn,
    onFirstLikeSynced: () =>
        ref.read(appStateProvider).flashToast('Also liked on YouTube Music'),
  ),
);
