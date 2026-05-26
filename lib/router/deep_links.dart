// Inbound deep-link dispatch. Handles both:
//
//   sunoh://<kind>/<id>[?source=…&q=…]              ← custom scheme
//   https://sunoh.online/<kind>/<id>[?source=…&q=…] ← App Links
//
// Path schema (kept deliberately small + URL-safe):
//
//   /album/<id>?source=saavn|gaana|spotify     → open album detail
//   /playlist/<id>?source=…                    → open playlist detail
//   /artist/<id>?source=…                      → open artist detail
//   /song/<id>?source=…                        → resolve + start playback
//   /search?q=…                                → switch to Search, pre-fill
//   /share/<id>                                → reserved (server-resolved
//                                                landing — falls back to a
//                                                toast for now)
//
// The dispatcher is intentionally tolerant: an unknown path or a missing id
// becomes a no-op + flash toast rather than a crash, since deep links arrive
// from untrusted sources (paste, chat, etc.).
//
// Cold-start vs warm wiring lives in main.dart's _Root — this file only
// owns the URI → action mapping.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/api_providers.dart';
import '../providers/app_state_provider.dart';
import 'router.dart';

/// Holds a search query handed off by a deep link until the Search screen
/// mounts and consumes it. The notifier exposes `consume()` so the screen
/// can read-and-clear in one shot — without that, hot-restart of the
/// Search tab would re-apply the old query every time.
class PendingSearchNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String q) => state = q;

  String? consume() {
    final v = state;
    if (v != null) state = null;
    return v;
  }
}

final pendingSearchProvider =
    NotifierProvider<PendingSearchNotifier, String?>(PendingSearchNotifier.new);

class DeepLinkRouter {
  DeepLinkRouter(this._ref);
  final Ref _ref;

  /// Entry point — called by main.dart for both cold-start URIs (initial
  /// app launch from a link) and warm URIs (the app_links stream).
  Future<void> handle(Uri uri) async {
    final segments = _segmentsFor(uri);
    final kind = segments.isNotEmpty ? segments[0].toLowerCase() : '';
    final id = segments.length > 1 ? segments[1] : '';
    final source = uri.queryParameters['source'];

    debugPrint('[deeplink] $uri → kind=$kind id=$id source=$source');

    final router = _router;
    if (router == null) {
      debugPrint('[deeplink] root router not ready, dropping $uri');
      return;
    }

    switch (kind) {
      case 'album':
      case 'playlist':
      case 'artist':
        if (id.isEmpty) {
          _toast('Bad $kind link');
          return;
        }
        final q = (source == null || source.isEmpty)
            ? ''
            : '?source=${Uri.encodeQueryComponent(source)}';
        router.go('/home/$kind/$id$q');
      case 'song':
        if (id.isEmpty) {
          _toast('Bad song link');
          return;
        }
        await _playSong(id, source: source);
      case 'search':
        final q = uri.queryParameters['q']?.trim() ?? '';
        if (q.isEmpty) {
          router.go('/search');
          return;
        }
        _ref.read(pendingSearchProvider.notifier).set(q);
        router.go('/search');
      case 'share':
        // Reserved for server-resolved share landings — once the backend
        // can map an opaque /share/<id> to a concrete album/playlist/song,
        // we'll fan out from here. For now, surface the unhandled link so
        // the user knows it arrived.
        _toast('Share landing isn’t wired yet');
      default:
        debugPrint('[deeplink] unrecognised path: ${uri.path}');
        _toast('Couldn’t open this link');
    }
  }

  Future<void> _playSong(String id, {String? source}) async {
    final api = _ref.read(sunohApiProvider);
    final song = await api.fetchSong(id, provider: source);
    if (song == null) {
      _toast('Couldn’t find that song');
      return;
    }
    // playApiSong overrides the active queue with the single track — same
    // behaviour as tapping a song row in search.
    await _ref
        .read(appStateProvider)
        .playApiSong(song, sourceLabel: 'SHARED LINK');
    _router?.push('/player');
  }

  GoRouter? get _router {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null) return null;
    try {
      return GoRouter.of(ctx);
    } catch (_) {
      return null;
    }
  }

  void _toast(String msg) {
    try {
      _ref.read(appStateProvider).flashToast(msg);
    } catch (_) {
      debugPrint('[deeplink] toast failed: $msg');
    }
  }

  /// Normalises both URI shapes into a path-segment list:
  ///   `sunoh://album/abc?source=x`  → ['album', 'abc']
  ///   `https://sunoh.online/album/abc?source=x` → ['album', 'abc']
  ///
  /// The custom scheme parses `album` as the URI host (not a path segment),
  /// so we prepend it manually when the scheme is `sunoh`.
  static List<String> _segmentsFor(Uri uri) {
    final pathParts =
        uri.pathSegments.where((s) => s.isNotEmpty).toList(growable: true);
    if (uri.scheme == 'sunoh' && (uri.host).isNotEmpty) {
      pathParts.insert(0, uri.host);
    }
    return pathParts;
  }
}

final deepLinkRouterProvider = Provider((ref) => DeepLinkRouter(ref));
