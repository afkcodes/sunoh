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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../player/mini_player.dart';
import '../providers/app_state_provider.dart';
import '../theme/tokens.dart';
import '../widgets/spotify_import_banner.dart';
import 'bottom_nav.dart';

class AppScaffold extends ConsumerWidget {
  const AppScaffold({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;

    return Material(
      color: c.bg,
      child: Stack(
        children: [
          Positioned.fill(child: shell),

          if (s.toast.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 150 + MediaQuery.of(context).padding.bottom,
              child: _Toast(message: s.toast, colors: c),
            ),

          // Full-width, edge-to-edge bottom bar (mini player + nav).
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: RepaintBoundary(child: _BottomBar(shell: shell, colors: c)),
          ),
        ],
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Soft fade so feed content dissolves into the bar instead of
        // being cut off by a hard edge — the read the blur used to give
        // us, for the cost of one gradient.
        IgnorePointer(
          child: SizedBox(
            height: 24,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [c.bg.withValues(alpha: 0), c.bg],
                ),
              ),
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: c.bg,
            border: Border(top: BorderSide(color: c.line, width: 0.5)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
              MiniPlayer(),
              BottomNav(
                currentIndex: shell.currentIndex,
                onTap: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Toast extends StatelessWidget {
  const _Toast({required this.message, required this.colors});
  final String message;
  final SunohColors colors;
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            // Opaque: at alpha 0.92 the blur behind this was paying a full
            // framebuffer read-back to tint 8% of a pill. On a tile-based
            // GPU (Mali) that read-back is disproportionately expensive;
            // visually it's indistinguishable from solid.
            color: const Color(0xFF141418),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 0.5),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 24, offset: const Offset(0, 8)),
            ],
          ),
          child: Text(message,
              style: SunohType.sans(
                  fontSize: 12, fontWeight: FontWeight.w500, color: const Color(0xFFFAFAFA))),
        ),
      ),
    );
  }
}
