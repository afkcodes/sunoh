// sunoh. — a quiet, editorial music streaming app.
// Flutter implementation of the Claude Design prototype (sunoh.html).

import 'dart:async';
import 'dart:math' as math;

import 'package:app_links/app_links.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';
import 'package:permission_handler/permission_handler.dart';

import 'api/client.dart';
import 'api/stream_resolver.dart';
import 'audio/audio_handler.dart';
import 'audio/audio_repo.dart';
import 'audio/audio_service_bridge.dart';
import 'audio/library_store.dart';
import 'audio/playback_state_store.dart';
import 'audio/settings_store.dart';
import 'router/deep_links.dart';
import 'router/router.dart';

/// One app-wide scroll feel: Android-style **stretch** overscroll on every
/// platform (clamping physics + stretching indicator), draggable with
/// mouse/trackpad too. Single source of truth — don't set `physics:` per view.
///
/// Uses [_LooseClampingScrollPhysics] so flings glide further than stock
/// Android physics — closer to iOS feel without the iOS bounce at edges.
class SunohScrollBehavior extends MaterialScrollBehavior {
  const SunohScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const _LooseClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics());

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return StretchingOverscrollIndicator(
      axisDirection: details.direction,
      child: child,
    );
  }

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

/// ClampingScrollPhysics with reduced fling friction. The default friction
/// used by [ClampingScrollSimulation] is 0.015 (matches Android's
/// `OverScroller`); we drop to 0.007 so flings glide ~2× further, which
/// approximates an iOS feel without switching to BouncingScrollPhysics (the
/// iOS bounce-at-top revealed bare bg above the detail hero historically).
/// Overscroll behavior stays clamping → still shows the StretchingOverscrollIndicator.
class _LooseClampingScrollPhysics extends ClampingScrollPhysics {
  const _LooseClampingScrollPhysics({super.parent});

  @override
  _LooseClampingScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _LooseClampingScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  Simulation? createBallisticSimulation(
      ScrollMetrics position, double velocity) {
    final Tolerance tolerance = toleranceFor(position);
    if (position.outOfRange) {
      double end;
      if (position.pixels > position.maxScrollExtent) {
        end = position.maxScrollExtent;
      } else if (position.pixels < position.minScrollExtent) {
        end = position.minScrollExtent;
      } else {
        return null;
      }
      return ScrollSpringSimulation(
        spring,
        position.pixels,
        end,
        math.min(0.0, velocity),
        tolerance: tolerance,
      );
    }
    if (velocity.abs() < tolerance.velocity) return null;
    if (velocity > 0.0 && position.pixels >= position.maxScrollExtent) {
      return null;
    }
    if (velocity < 0.0 && position.pixels <= position.minScrollExtent) {
      return null;
    }
    return ClampingScrollSimulation(
      position: position.pixels,
      velocity: velocity,
      tolerance: tolerance,
      friction: 0.007,
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Local persistence (queue + future library/history/settings boxes).
  await Hive.initFlutter();
  // ignore: avoid_print
  print('[hive] init complete — boxes will land in '
      'getApplicationDocumentsDirectory() (/data/data/<pkg>/app_flutter/).');

  // mpv FFI bindings init — synchronous, cheap.
  // Using `print` not `debugPrint` so these always surface in logcat.
  // ignore: avoid_print
  print('[audio] MpvAudioKit.ensureInitialized()');
  MpvAudioKit.ensureInitialized();
  // ignore: avoid_print
  print('[audio] MpvAudioKit ready');

  // Phase 1: synchronous mpv setup. Playback works after this line.
  final resolver = StreamResolver(buildSunohDio());
  final handler = SunohAudioHandler(resolver: resolver);
  final repo = AudioRepo(
    handler: handler,
    resolver: resolver,
    store: PlaybackStateStore(),
    settings: SettingsStore(),
    library: LibraryStore(),
  );
  // ignore: avoid_print
  print('[audio] AudioRepo ready ✓ (Phase 1 — mpv only)');

  // Phase 2 add-on: try to wire audio_service for OS integration. Runs in
  // the background with a hard 5s timeout. If it succeeds, the bridge gets
  // attached to the repo. If it hangs or throws, in-app playback is
  // unaffected — we just don't get lockscreen/notification controls.
  unawaited(_tryWireAudioService(handler).then((bridge) {
    if (bridge != null) {
      repo.attachBridge(bridge);
    }
  }));

  runApp(ProviderScope(
    overrides: [audioRepoProvider.overrideWithValue(repo)],
    child: const _Root(),
  ));
}

Future<SunohAudioServiceBridge?> _tryWireAudioService(
    SunohAudioHandler handler) async {
  // Request POST_NOTIFICATIONS first. On Android 13+ this triggers the
  // system permission dialog; on older versions / iOS it's a no-op.
  try {
    final status = await Permission.notification
        .request()
        .timeout(const Duration(seconds: 3));
    // ignore: avoid_print
    print('[audio-svc] notification permission: $status');
  } catch (e) {
    // ignore: avoid_print
    print('[audio-svc] permission request errored: $e (continuing anyway)');
  }

  // ignore: avoid_print
  print('[audio-svc] AudioService.init starting…');
  try {
    final bridge = await AudioService.init(
      builder: () => SunohAudioServiceBridge(handler),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.sunoh.sunoh.audio',
        androidNotificationChannelName: 'sunoh playback',
        // Keep the foreground service alive even when paused. The
        // audio_service default (`true`) ends the FG service on pause —
        // which lets the OS kill the app aggressively when backgrounded,
        // and any brief mid-track stream-state blip that flickers through
        // "not playing" reads as "pause". Music apps want the FG service
        // alive until the user explicitly stops.
        // NOTE: `androidNotificationOngoing` and `androidStopForegroundOnPause:
        // false` are mutually exclusive (asserted by the package) — the
        // ongoing flag would have no effect once the FG service stays alive
        // through pause. So we drop `androidNotificationOngoing: true` too.
        androidStopForegroundOnPause: false,
      ),
    ).timeout(const Duration(seconds: 5));
    // ignore: avoid_print
    print('[audio-svc] init complete ✓');
    return bridge;
  } catch (e, st) {
    // ignore: avoid_print
    print('[audio-svc] init FAILED: $e');
    debugPrint(st.toString());
    return null;
  }
}

class _Root extends ConsumerStatefulWidget {
  const _Root();
  @override
  ConsumerState<_Root> createState() => _RootState();
}

class _RootState extends ConsumerState<_Root> {
  final GoRouter _router = buildRouter();
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    // Defer until after first frame so GoRouter has built its initial
    // route + the rootNavigatorKey context is live. Without this, a cold
    // start from a link races the router and the dispatch is a no-op.
    WidgetsBinding.instance.addPostFrameCallback((_) => _wireDeepLinks());
  }

  Future<void> _wireDeepLinks() async {
    final dispatcher = ref.read(deepLinkRouterProvider);
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) {
        // ignore: avoid_print
        print('[deeplink] cold-start uri: $initial');
        await dispatcher.handle(initial);
      }
    } catch (e) {
      // ignore: avoid_print
      print('[deeplink] getInitialLink failed: $e');
    }
    _linkSub = _appLinks.uriLinkStream.listen(
      (uri) {
        // ignore: avoid_print
        print('[deeplink] warm uri: $uri');
        dispatcher.handle(uri);
      },
      onError: (Object e) {
        // ignore: avoid_print
        print('[deeplink] stream error: $e');
      },
    );
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Dark only — light status-bar icons over the near-black bg.
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));
    return MaterialApp.router(
      title: 'sunoh.',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const SunohScrollBehavior(),
      routerConfig: _router,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
      ),
    );
  }
}
