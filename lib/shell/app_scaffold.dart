// The persistent shell: routed screen + full-width bottom bar (mini
// player + nav) + toast.
//
// PERF: the bottom bar used to be a `BackdropFilter(sigma 24)` frosted
// panel. That blur sits over the scrolling content and re-rasterizes on
// EVERY frame of every scroll, app-wide — the single most GPU-dependent
// primitive in the tree, and the reason scrolling was smooth on some
// devices and janked badly on others. It's now an opaque bar plus a
// short gradient scrim above it: content still fades out as it passes
// underneath, but the per-frame cost is zero. The bar is also wrapped
// in a RepaintBoundary so it composites as its own layer and never
// repaints along with the feed scrolling beneath it.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../player/mini_player.dart';
import '../providers/app_state_provider.dart';
import '../theme/tokens.dart';
import '../widgets/spotify_import_banner.dart';
import '../widgets/ui.dart';
import 'bottom_nav.dart';

class AppScaffold extends ConsumerWidget {
  const AppScaffold({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;

    // Status-bar icons have to invert with the palette: light icons over a
    // light page are invisible. Applied here rather than once at startup
    // because the theme can change while the app is running, including on
    // its own when following the system.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: s.isLight ? Brightness.dark : Brightness.light,
        statusBarBrightness: s.isLight ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: c.bg,
        systemNavigationBarIconBrightness: s.isLight
            ? Brightness.dark
            : Brightness.light,
      ),
      child: Material(
        color: c.bg,
        child: Stack(
          children: [
            Positioned.fill(child: shell),

            Positioned(
              left: 16,
              right: 16,
              bottom: 156 + MediaQuery.of(context).padding.bottom,
              child: AnimatedSwitcher(
                duration: SunohMotion.ui,
                switchInCurve: SunohMotion.arrive,
                switchOutCurve: SunohMotion.ease,
                transitionBuilder: (child, a) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(
                    position: Tween(
                      begin: const Offset(0, 0.25),
                      end: Offset.zero,
                    ).animate(a),
                    child: child,
                  ),
                ),
                child: s.toast.isEmpty
                    ? const SizedBox.shrink()
                    : _Toast(
                        key: ValueKey(s.toast),
                        message: s.toast,
                        colors: c,
                      ),
              ),
            ),

            // Full-width, edge-to-edge bottom bar (mini player + nav).
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: RepaintBoundary(
                child: _BottomBar(shell: shell, colors: c),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.shell, required this.colors});
  final StatefulNavigationShell shell;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    // The mini player floats over the feed: the content fades into the
    // ground behind it (one gradient, no blur) and the nav bar below is
    // solid. Transparent areas of the gradient do not take taps, so the feed
    // stays scrollable right up to the card.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0, 0.6, 1],
              colors: [
                c.bg.withValues(alpha: 0),
                c.bg.withValues(alpha: 0.92),
                c.bg,
              ],
            ),
          ),
          // Kept non-const all the way down to MiniPlayer — see below.
          // ignore: prefer_const_constructors
          child: Padding(
            padding: const EdgeInsets.only(top: 28),
            // ignore: prefer_const_constructors
            child: Column(
              mainAxisSize: MainAxisSize.min,
              // ignore: prefer_const_literals_to_create_immutables
              children: [
                // Persistent Spotify-import banner — visible across all
                // screens while an import is running, completed, or
                // failed. Renders nothing in the idle state.
                const SpotifyImportBanner(),
                // NOT const — `const MiniPlayer()` made Flutter compare the
                // same widget reference between rebuilds and short-circuit
                // subtree reconciliation, which interfered with the mini
                // player's reactive subscription to appStateProvider (the
                // expanded player updated, the mini didn't).
                // ignore: prefer_const_constructors
                MiniPlayer(),
              ],
            ),
          ),
        ),
        ColoredBox(
          color: c.bg,
          child: BottomNav(
            currentIndex: shell.currentIndex,
            onTap: (i) =>
                shell.goBranch(i, initialLocation: i == shell.currentIndex),
          ),
        ),
      ],
    );
  }
}

/// A one-line confirmation in an ink bar above the mini player — the
/// inverse of the page, so it reads as a message rather than as content.
class _Toast extends StatelessWidget {
  const _Toast({super.key, required this.message, required this.colors});
  final String message;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: squircleDecoration(
          radius: SunohRadius.card,
          color: colors.fg,
          shadows: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Text(
          message,
          style: SunohType.sans(
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
            color: colors.bg,
          ),
        ),
      ),
    );
  }
}
