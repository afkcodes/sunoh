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
    // No setUserAgent — Google's "this browser may not be secure"
    // block fires when the UA claims desktop Chrome but the renderer
    // is a WebView. Letting webview_flutter use its default Android
    // WebView UA (mobile-Chrome) gets us past the block. Same call
    // OuterTune makes in their LoginScreen.kt.
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
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

/// Direct entry into the WebView-compatible login flow. Sending
/// `?continue=music.youtube.com` makes Google bounce back to YT Music
/// after sign-in completes, so the SAPISID + related cookies land on
/// the right origin. Same URL OuterTune uses for the same reason —
/// the bare `music.youtube.com/` route would otherwise force users
/// through an extra "Sign in" tap, and that secondary flow uses a
/// stricter WebView-blocking login surface.
const String _kStartUrl =
    'https://accounts.google.com/ServiceLogin?continue=https%3A%2F%2Fmusic.youtube.com';
