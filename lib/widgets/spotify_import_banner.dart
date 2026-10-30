// Persistent banner pinned above the bottom nav while a Spotify
// playlist import is in flight (or has just finished / failed).
//
// States it renders:
//   - `fetching`  → "Importing from Spotify · 1m 23s elapsed" over a running
//                   2 px bar. No dismiss — the import is still in flight on
//                   the server side. Tapping a cancel here wouldn't stop the
//                   upstream work, only orphan it; the user can dismiss it
//                   once it completes.
//   - `completed` → "Imported <name> — N tracks matched" with a dismiss.
//                   Tapping opens the new user playlist.
//   - `failed`    → "Spotify import failed — <reason>" · Retry / Dismiss.
//   - `idle`      → renders nothing (zero-size).
//
// Drawn as the prototype's download card: title over a dimmer line, actions
// on the right, a hairline progress bar along the bottom while work runs.
//
// Sits inside the AppScaffold's Stack, between the toast layer and the
// bottom bar — so it's visible on every tab + every detail screen.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remixicon/remixicon.dart';

import '../providers/app_state_provider.dart';
import '../router/router.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import 'motion.dart';
import 'ui.dart';

class SpotifyImportBanner extends ConsumerWidget {
  const SpotifyImportBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final state = s.spotifyImport;
    if (state.status == SpotifyImportStatus.idle) {
      return const SizedBox.shrink();
    }
    final c = s.colors;
    return Padding(
      // The mini player's inset, so the two floating cards line up.
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      // Lifted off the page by a raised fill rather than a hairline. It has
      // to stay opaque — it floats over content — so the raised surface is
      // composited onto bgSoft.
      child: DecoratedBox(
        decoration: squircleDecoration(
          radius: SunohRadius.card,
          color: Color.alphaBlend(c.surface2, c.bgSoft),
        ),
        child: switch (state.status) {
          SpotifyImportStatus.fetching => _Fetching(state: state, colors: c),
          SpotifyImportStatus.completed => _Completed(state: state, colors: c),
          SpotifyImportStatus.failed => _Failed(state: state, colors: c),
          SpotifyImportStatus.idle => const SizedBox.shrink(),
        },
      ),
    );
  }
}

/// The card's layout, shared by all three states.
class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.subtitle,
    required this.colors,
    this.subtitleColor,
    this.actions = const [],
    this.running = false,
  });

  final String title;
  final String subtitle;
  final SunohColors colors;
  final Color? subtitleColor;
  final List<Widget> actions;

  /// Draws the indeterminate bar along the bottom.
  final bool running;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 12, actions.isEmpty ? 14 : 4, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SunohType.sans(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: c.fg,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SunohType.sans(
                        fontSize: 12.5,
                        color: subtitleColor ?? c.fgDim,
                      ),
                    ),
                  ],
                ),
              ),
              ...actions,
            ],
          ),
          if (running)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: c.line,
                color: c.fg,
              ),
            ),
        ],
      ),
    );
  }
}

class _Fetching extends StatefulWidget {
  const _Fetching({required this.state, required this.colors});
  final SpotifyImportState state;
  final SunohColors colors;
  @override
  State<_Fetching> createState() => _FetchingState();
}

class _FetchingState extends State<_Fetching> {
  Timer? _tick;
  @override
  void initState() {
    super.initState();
    // Refresh the elapsed-time string once a second. Cheap; only renders
    // a single Text node.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final started = widget.state.startedAt;
    final elapsed = started == null ? null : DateTime.now().difference(started);
    return _Card(
      title: 'Importing from Spotify',
      subtitle: elapsed == null
          ? 'This can take a couple of minutes'
          : '${_formatElapsed(elapsed)} elapsed — usually 1–2 min',
      colors: widget.colors,
      running: true,
    );
  }

  static String _formatElapsed(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    if (m == 0) return '${s}s';
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }
}

class _Completed extends ConsumerWidget {
  const _Completed({required this.state, required this.colors});
  final SpotifyImportState state;
  final SunohColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    final s = ref.read(appStateProvider);
    final name = state.sourceName ?? 'playlist';
    final matched = state.matchedTracks ?? 0;
    final total = state.totalTracks ?? matched;
    final tail = (total > 0 && total != matched)
        ? '$matched of $total'
        : '$matched';
    return Pressable(
      onTap: () {
        final id = state.newPlaylistId;
        s.dismissSpotifyImport();
        if (id != null) context.openUserPlaylist(id);
      },
      child: _Card(
        title: 'Imported "$name"',
        subtitle: '$tail tracks matched — tap to open',
        colors: c,
        actions: [_Dismiss(colors: c, onTap: s.dismissSpotifyImport)],
      ),
    );
  }
}

class _Failed extends ConsumerWidget {
  const _Failed({required this.state, required this.colors});
  final SpotifyImportState state;
  final SunohColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    final s = ref.read(appStateProvider);
    final url = state.sourceUrl;
    return _Card(
      title: 'Spotify import failed',
      subtitle: state.errorMessage ?? 'Import failed',
      // The reason carries the error, in the one red; the title stays ink so
      // the card does not shout.
      subtitleColor: c.danger,
      colors: c,
      actions: [
        if (url != null)
          Pressable(
            onTap: () {
              s.dismissSpotifyImport();
              // Re-arming: defer one frame so the banner's idle state lands
              // first; otherwise the new `fetching` state can collide with
              // the in-flight dismiss notify and we'd see a flash of idle in
              // between.
              Future.microtask(() => s.importSpotifyPlaylist(url));
            },
            // The primary action, so the accent pill.
            child: Container(
              height: 34,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: squircleDecoration(radius: 17, color: c.accent),
              child: Text(
                'Retry',
                style: SunohType.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: c.onAccent,
                ),
              ),
            ),
          ),
        _Dismiss(colors: c, onTap: s.dismissSpotifyImport),
      ],
    );
  }
}

class _Dismiss extends StatelessWidget {
  const _Dismiss({required this.colors, required this.onTap});
  final SunohColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconBtn(
    icon: RemixIcons.close_circle_line,
    size: 18,
    color: colors.fgDim,
    onTap: onTap,
  );
}
