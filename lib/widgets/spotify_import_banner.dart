// Persistent banner pinned above the bottom nav while a Spotify
// playlist import is in flight (or has just finished / failed).
//
// States it renders:
//   - `fetching`  → "Importing <name>… 1m 23s" with an indeterminate
//                   progress bar. No dismiss — the import is still
//                   in flight on the server side. Tapping a cancel
//                   here wouldn't stop the upstream work, only orphan
//                   it; the user can dismiss it once it completes.
//   - `completed` → "Imported <name> — N songs · View ↗" with a
//                   dismiss. Tapping opens the new user playlist.
//   - `failed`    → "Import failed — <reason> · Retry / Dismiss".
//   - `idle`      → renders nothing (zero-size).
//
// Sits inside the AppScaffold's Stack, between the toast layer and the
// bottom bar — so it's visible on every tab + every detail screen.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../providers/app_state_provider.dart';
import '../router/router.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';

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
    final accent = s.resolvedAccent;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: Material(
        color: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF15151A),
              border: Border.all(color: c.line, width: 0.5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: switch (state.status) {
              SpotifyImportStatus.fetching =>
                _Fetching(state: state, accent: accent, colors: c),
              SpotifyImportStatus.completed =>
                _Completed(state: state, accent: accent, colors: c),
              SpotifyImportStatus.failed =>
                _Failed(state: state, accent: accent, colors: c),
              SpotifyImportStatus.idle => const SizedBox.shrink(),
            },
          ),
        ),
      ),
    );
  }
}

class _Fetching extends StatefulWidget {
  const _Fetching({
    required this.state,
    required this.accent,
    required this.colors,
  });
  final SpotifyImportState state;
  final Color accent;
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
    final c = widget.colors;
    final started = widget.state.startedAt;
    final elapsed = started == null ? null : DateTime.now().difference(started);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: widget.accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Importing from Spotify',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SunohType.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: c.fg,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  elapsed == null
                      ? 'This can take a couple of minutes'
                      : '${_formatElapsed(elapsed)} elapsed — usually 1–2 min',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SunohType.sans(fontSize: 11.5, color: c.fgMute),
                ),
              ],
            ),
          ),
        ],
      ),
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
  const _Completed({
    required this.state,
    required this.accent,
    required this.colors,
  });
  final SpotifyImportState state;
  final Color accent;
  final SunohColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    final s = ref.read(appStateProvider);
    final name = state.sourceName ?? 'playlist';
    final matched = state.matchedTracks ?? 0;
    final total = state.totalTracks ?? matched;
    final tail = (total > 0 && total != matched) ? '$matched of $total' : '$matched';
    return InkWell(
      onTap: () {
        final id = state.newPlaylistId;
        s.dismissSpotifyImport();
        if (id != null) context.openUserPlaylist(id);
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(SolarIconsBold.checkCircle, color: accent, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Imported "$name"',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SunohType.sans(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: c.fg),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$tail tracks matched — tap to open',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SunohType.sans(fontSize: 11.5, color: c.fgMute),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: s.dismissSpotifyImport,
              icon: Icon(SolarIconsOutline.closeCircle,
                  size: 18, color: c.fgDim),
              splashRadius: 18,
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }
}

class _Failed extends ConsumerWidget {
  const _Failed({
    required this.state,
    required this.accent,
    required this.colors,
  });
  final SpotifyImportState state;
  final Color accent;
  final SunohColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    final s = ref.read(appStateProvider);
    final msg = state.errorMessage ?? 'Import failed';
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFFE05656).withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(SolarIconsBold.dangerCircle,
                color: Color(0xFFE05656), size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Spotify import failed',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SunohType.sans(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: c.fg),
                ),
                const SizedBox(height: 2),
                Text(
                  msg,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SunohType.sans(fontSize: 11.5, color: c.fgMute),
                ),
              ],
            ),
          ),
          if (state.sourceUrl != null)
            GestureDetector(
              onTap: () {
                final url = state.sourceUrl!;
                s.dismissSpotifyImport();
                // Re-arming: defer one frame so the banner's idle
                // state lands first; otherwise the new `fetching`
                // state can collide with the in-flight dismiss
                // notify and we'd see a flash of idle in between.
                Future.microtask(() => s.importSpotifyPlaylist(url));
              },
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Text(
                  'Retry',
                  style: SunohType.sans(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: accent),
                ),
              ),
            ),
          IconButton(
            onPressed: s.dismissSpotifyImport,
            icon: Icon(SolarIconsOutline.closeCircle,
                size: 18, color: c.fgDim),
            splashRadius: 18,
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}
