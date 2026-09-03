// sunoh. — a quiet, editorial music streaming app.
// Flutter implementation of the Claude Design prototype (sunoh.html).

import 'dart:async';
import 'dart:math' as math;

import 'package:app_links/app_links.dart';
import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';
import 'package:permission_handler/permission_handler.dart';

import 'api/client.dart';
import 'api/lossless_api.dart';
import 'api/sponsorblock.dart';
import 'api/stream_resolver.dart';
import 'api/sunoh_api.dart';
import 'api/ytmusic_channel.dart';
import 'audio/audio_handler.dart';
import 'audio/audio_repo.dart';
import 'audio/audio_service_bridge.dart';
import 'audio/auto_browse.dart';
import 'audio/auto_catalog.dart';
import 'audio/download_manager.dart';
import 'audio/download_store.dart';
import 'audio/library_store.dart';
import 'audio/playback_state_store.dart';
import 'audio/settings_store.dart';
import 'audio/sponsorblock_skipper.dart';
import 'cast/cast_service.dart';
import 'config/env.dart';
import 'providers/app_state_provider.dart';
import 'providers/downloads_provider.dart';
import 'providers/ytmusic_provider.dart';
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
      const _LooseClampingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      );

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
    ScrollMetrics position,
    double velocity,
  ) {
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

  // Flutter's default decoded-image budget is 100 MiB, and this app blows
  // through it on one screen. A home feed of ~20 shelves is a couple of
  // hundred tiles, and a tile decoded at its 384 px cache tier costs
  // 384*384*4 = 590 KB — call it 118 MB before a detail screen's 1200 px hero
  // adds another 5.8 MB of its own.
  //
  // Past the limit Flutter evicts, so opening an album and coming back found
  // the feed's bitmaps gone and re-decoded every one of them from disk. That
  // is the "all the images re-render when I go back" symptom: not widget
  // churn — SunohArt already handles that — but a cache too small to hold one
  // screen's worth of art.
  //
  // Flutter's default is 100 MiB, which was marginal here for a reason worth
  // recording: home tiles were decoding at the 720 rung and costing 2 MB each
  // (see the tier ladder in widgets/album_art.dart), so the default held only
  // about 48 images — less than one screen of feed plus a detail page.
  //
  // With the tier fixed a tile is under 1 MB, so this holds roughly 190. That
  // is comfortably more than the working set: the sections on screen, plus
  // whatever a detail screen decodes on top.
  //
  // Deliberately not larger. It was briefly 320 MiB while chasing a flicker on
  // back-navigation, and measurement showed that was the wrong suspect — the
  // cache sits pinned at whatever ceiling it is given, evicting constantly,
  // and the flicker was an eager rebuild of the whole feed rather than a cache
  // miss. Hundreds of MB of native bitmap buys nothing here and is how an app
  // gets killed in the background on a mid-range phone.
  //
  // A ceiling, not an allocation: only what has actually been decoded is held,
  // least-recently-used goes first, and Flutter drops all of it under memory
  // pressure.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 128 << 20;
  PaintingBinding.instance.imageCache.maximumSize = 1000;

  // Say so once, loudly, rather than letting the catalog screens fail with a
  // generic network error that looks like the backend is down.
  if (Env.missing.isNotEmpty) {
    debugPrint(
      '[env] built without ${Env.missing.join(', ')} — '
      'copy env.example.json to env.json and pass '
      '--dart-define-from-file=env.json',
    );
  }

  // Local persistence (queue + future library/history/settings boxes).
  await Hive.initFlutter();
  // ignore: avoid_print
  print(
    '[hive] init complete — boxes will land in '
    'getApplicationDocumentsDirectory() (/data/data/<pkg>/app_flutter/).',
  );

  // mpv FFI bindings init — synchronous, cheap.
  // Using `print` not `debugPrint` so these always surface in logcat.
  // ignore: avoid_print
  print('[audio] MpvAudioKit.ensureInitialized()');
  MpvAudioKit.ensureInitialized();
  // ignore: avoid_print
  print('[audio] MpvAudioKit ready');

  // Phase 1: synchronous mpv setup. Playback works after this line.
  // One Dio for both: the lossless lookup talks to the same sunoh-api host and
  // benefits from the same base URL, interceptors and timeouts.
  final sunohDio = buildSunohDio();
  final resolver = StreamResolver(sunohDio)..lossless = LosslessApi(sunohDio);
  // Downloads — wire the offline tier before the handler is built so any
  // restored playback queue benefits from the local file lookup on the
  // very first resolve. Failures here MUST be swallowed: the manager
  // is additive (no downloads → network only), so a broken Hive box
  // shouldn't prevent in-app playback.
  final downloadStore = DownloadStore();
  final downloadManager = DownloadManager(
    resolver: resolver,
    store: downloadStore,
  );
  try {
    await downloadManager.init();
    resolver.localSource = downloadManager;
    // ignore: avoid_print
    print('[downloads] manager ready, resolver.localSource attached');
  } catch (e, st) {
    // ignore: avoid_print
    print('[downloads] init failed (continuing without offline tier): $e\n$st');
  }
  // Cast SDK init — fire-and-forget. Devices without Google Play
  // Services will silently fail to discover anything; the rest of the
  // app keeps working.
  unawaited(CastService.instance.init());
  // Firebase Analytics init — also fire-and-forget. Wrapped in its own
  // try/catch so a missing `android/app/google-services.json` or a
  // device without Play Services degrades to "analytics disabled" with
  // a single log line, instead of blocking app boot. Every call site
  // checks `_ready` before touching the SDK so it's safe to call before
  // this future resolves.
  final handler = SunohAudioHandler(resolver: resolver);
  final repo = AudioRepo(
    handler: handler,
    resolver: resolver,
    store: PlaybackStateStore(),
    settings: SettingsStore(),
    library: LibraryStore(),
    // Its own Dio: buildSunohDio carries our base URL and sunoh-api
    // headers, none of which belong on a request to sponsor.ajay.app.
    sponsorBlock: SponsorBlockSkipper(
      client: SponsorBlockClient(
        Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 8),
            receiveTimeout: const Duration(seconds: 12),
          ),
        ),
      ),
    ),
  );
  // ignore: avoid_print
  print('[audio] AudioRepo ready ✓ (Phase 1 — mpv only)');

  // Android Auto browse tree. Reads the same Hive-backed library the phone
  // UI does and starts playback through the same repo, so the car and the
  // phone can never disagree about what "Liked Songs" means.
  // The car's Music tab must match the phone's, so it needs the user's
  // language selection. Read once here and held in a cell the tree reads
  // synchronously — the browse callbacks are hot and can't await a box open.
  String? autoLanguages;
  unawaited(
    repo.settings
        .loadPlayback()
        .then((s) {
          final langs = s?.languages;
          if (langs != null && langs.isNotEmpty) {
            autoLanguages = langs.join(',');
          }
        })
        .catchError((_) {}),
  );
  final autoBrowse = AutoBrowseTree(
    library: repo.library,
    api: SunohApi(buildSunohDio()),
    downloads: downloadManager,
    playQueue: repo.playQueue,
    languages: () => autoLanguages,
  );

  // Phase 2 add-on: try to wire audio_service for OS integration. Runs in
  // the background with a hard 5s timeout. If it succeeds, the bridge gets
  // attached to the repo. If it hangs or throws, in-app playback is
  // unaffected — we just don't get lockscreen/notification controls, and
  // the car sees no app at all.
  unawaited(
    _tryWireAudioService(handler, autoBrowse).then((bridge) {
      if (bridge != null) {
        repo.attachBridge(bridge);
        // Swiping the app from recents shuts the process down, and the queue
        // and position have to reach disk before it goes. The bridge is built
        // before the repo exists, so the hook is handed over here.
        bridge.onBeforeShutdown = repo.persistAll;
      }
    }),
  );

  runApp(
    ProviderScope(
      overrides: [
        audioRepoProvider.overrideWithValue(repo),
        downloadManagerProvider.overrideWithValue(downloadManager),
      ],
      child: const _Root(),
    ),
  );
}

Future<SunohAudioServiceBridge?> _tryWireAudioService(
  SunohAudioHandler handler,
  AutoBrowseTree autoBrowse,
) async {
  // Request POST_NOTIFICATIONS first. On Android 13+ this triggers the
  // system permission dialog; on older versions / iOS it's a no-op.
  try {
    final status = await Permission.notification.request().timeout(
      const Duration(seconds: 3),
    );
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
      builder: () => SunohAudioServiceBridge(handler, browse: autoBrowse),
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
        // Returned from onGetRoot. Tells Android Auto how to lay the browse
        // tree out (collections as a grid, tracks as a list); without it the
        // car falls back to its own default, which renders track lists as
        // artwork tiles and makes long lists unreadable at a glance.
        androidBrowsableRootExtras: kAutoRootExtras,
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolveYtRegion());
    // Warm the YouTube Music PO-token WebView. A cold mint costs a WebView
    // spin-up plus BotGuard evaluation (~2-5s); doing it now means the first
    // YouTube track the user taps doesn't pay for it. Fire-and-forget — the
    // channel swallows its own failures, and a cold resolve still works.
    unawaited(YtMusicChannel.instance.prewarm());
  }

  /// Detect the YouTube region from the connection once per launch.
  ///
  /// Fire-and-forget and never awaited by anything: the resolver already
  /// answers from the device locale, so the first feed renders immediately
  /// and only re-fetches if the IP lookup disagrees. Skipped entirely when
  /// the user has set an explicit region.
  Future<void> _resolveYtRegion() async {
    final before = ref.read(ytLocaleProvider);
    if (!before.countryIsAuto) return;
    final found = await ref.read(ytLocaleResolverProvider).refreshFromIp();
    if (found == null || found == before.country || !mounted) return;
    ref.invalidate(ytLocaleProvider);
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
    // The overlay style is set per-frame by AppScaffold, which knows the
    // palette. All that is needed here is the brightness for ThemeData.
    final brightness = ref.watch(appStateProvider).brightness;
    return MaterialApp.router(
      title: 'sunoh.',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const SunohScrollBehavior(),
      routerConfig: _router,
      // Brightness tracks the app's own theme so descendants can ask
      // `Theme.of(context).brightness` — which is how SunohArt decides how
      // heavy a shadow to cast — without every one of them threading the
      // palette down.
      theme: ThemeData(
        useMaterial3: true,
        brightness: brightness,
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
      ),
    );
  }
}
