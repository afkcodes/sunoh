// One-time YouTube Music sign-in flow.
//
// Loads `music.youtube.com` in a WebView. When the user signs in,
// YouTube sets a `SAPISID` cookie on the document. We poll
// `document.cookie` (it's JS-readable for SAPISID since YouTube's
// own JS reads it for SAPISIDHASH), capture the full cookie string,
// hand it to AppState which persists it and threads it into the
// stream resolver.
//
// Once captured we pop back to Settings — no further interaction
// needed. The cookie lasts ~6 months; when it expires the YT tier
// in the stream resolver throws a labeled error pointing the user
// back here to re-auth.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../providers/app_state_provider.dart';
import '../theme/tokens.dart';

class YouTubeMusicSignInScreen extends ConsumerStatefulWidget {
  const YouTubeMusicSignInScreen({super.key});

  @override
  ConsumerState<YouTubeMusicSignInScreen> createState() =>
      _YouTubeMusicSignInScreenState();
}

class _YouTubeMusicSignInScreenState
    extends ConsumerState<YouTubeMusicSignInScreen> {
  late final WebViewController _controller;
  Timer? _cookiePoll;
  /// `true` once we've successfully captured a SAPISID cookie and
  /// kicked off the persist + pop flow — guards against double-
  /// triggering on a fast-firing poll.
  bool _captured = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(_kDesktopUa)
      ..loadRequest(Uri.parse(_kStartUrl));
    // Cookies become available a moment after the post-login redirect
    // settles. Polling every 1.5 s catches the transition without
    // hitting the WebView too aggressively. Stops once captured.
    _cookiePoll = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      _checkForLoggedInCookies();
    });
  }

  @override
  void dispose() {
    _cookiePoll?.cancel();
    super.dispose();
  }

  Future<void> _checkForLoggedInCookies() async {
    if (_captured || !mounted) return;
    final raw = await _controller.runJavaScriptReturningResult('document.cookie');
    // Webviews wrap the result as a JSON-encoded string on Android —
    // `'\"a=b; c=d\"'` — strip the wrap defensively.
    final cookieStr = raw.toString();
    final unwrapped = cookieStr.startsWith('"') && cookieStr.endsWith('"')
        ? cookieStr.substring(1, cookieStr.length - 1).replaceAll(r'\"', '"')
        : cookieStr;
    if (!unwrapped.contains('SAPISID')) return;
    _captured = true;
    _cookiePoll?.cancel();
    final state = ref.read(appStateProvider);
    await state.setYouTubeMusicCookie(unwrapped);
    state.flashToast('Signed in to YouTube Music');
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(SolarIconsOutline.altArrowLeft, color: c.fg),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Sign in to YouTube Music',
          style: SunohType.sans(
              fontSize: 15, fontWeight: FontWeight.w600, color: c.fg),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
            child: Text(
              'Sign in once with the Google account you want sunoh to use '
              'for YouTube Music. Cookies are stored only on this device.',
              style: SunohType.sans(
                  fontSize: 12.5, color: c.fgMute, height: 1.4),
            ),
          ),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }
}

/// YouTube Music's WebView-friendly entry. Sending the user straight
/// to `accounts.google.com` is tempting but it ends up redirecting to
/// the consumer YT-music page anyway, and we want the SAPISID set
/// against the `music.youtube.com` origin specifically.
const String _kStartUrl = 'https://music.youtube.com/';

/// Desktop UA so YouTube doesn't push the "use the YouTube Music app"
/// interstitial that mobile UAs trigger. WebView's default UA is
/// Chrome-Mobile which YT sometimes blocks at the login page.
const String _kDesktopUa =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/126.0.0.0 Safari/537.36';
