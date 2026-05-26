// Karaoke-style lyrics overlay with active-line highlight + auto-scroll.
//
// Lyrics are fetched from LRCLIB (see lib/providers/lyrics_provider.dart)
// keyed by the currently playing API song's title + artist + duration.
// When there's no API song (dummy/local catalog tracks, the cold-launch
// landing track, etc.) we fall back to the bundled `kLyrics` map so the
// screen still demos.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';

import '../api/dto.dart';
import '../data/catalog.dart';
import '../data/models.dart';
import '../providers/app_state_provider.dart';
import '../providers/lyrics_provider.dart';
import '../share/share_link.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/ui.dart';

class LyricsScreen extends ConsumerStatefulWidget {
  const LyricsScreen({super.key});
  @override
  ConsumerState<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends ConsumerState<LyricsScreen> {
  final controller = ScrollController();
  int _lastIdx = -2;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final accent = s.resolvedAccent;
    final track = s.current;
    final apiSong = s.currentApiSong;

    final query = _queryFor(apiSong);
    // No API song (dummy/local catalog) → keep the bundled lyrics demo.
    final fallbackLines = kLyrics[track.id] ?? kLyrics['t01']!;

    // Opaque base + soft accent tint at the top edge. The previous
    // gradient leaned on the route's transparent background, so the
    // expanded player bled through and the sheet read as smoky. Layer
    // the tint over an opaque c.bg so the page is its own thing.
    return Container(
      color: c.bg,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [accent.withValues(alpha: 0.22), Colors.transparent],
            stops: const [0, 0.55],
          ),
        ),
        child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconBtn(icon: SolarIconsOutline.altArrowDown, color: c.fgDim, size: 22, onTap: () => context.pop()),
                  eyebrow('LYRICS', c.fgMute),
                  IconBtn(
                      icon: SolarIconsOutline.share,
                      color: c.fgDim,
                      size: 18,
                      onTap: () {
                        // Lyrics overlay is bound to the currently playing
                        // song. Use the API song (real id + source) when
                        // available; fall back silently if the queue is a
                        // dummy/local entry with no shareable identity.
                        if (apiSong == null) return;
                        shareSunohLink(
                          kind: 'song',
                          id: apiSong.id,
                          title: apiSong.title,
                          subtitle: apiSong.displaySubtitle ?? apiSong.subtitle,
                          source: apiSong.source,
                        );
                      }),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Row(
                children: [
                  SunohArt(
                      id: apiSong?.id ?? track.id,
                      imageUrl: apiSong?.artwork,
                      size: 44,
                      radius: 6),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(track.title,
                            style: SunohType.sans(fontSize: 13.5, fontWeight: FontWeight.w500, color: c.fg)),
                        const SizedBox(height: 1),
                        Text(track.artist, style: SunohType.sans(fontSize: 12, color: c.fgMute)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: query == null
                  ? _LyricsBody(
                      colors: c,
                      lines: fallbackLines,
                      synced: true,
                      controller: controller,
                      tick: s.positionTick,
                      onActive: _onActive,
                    )
                  : _LiveLyrics(
                      query: query,
                      colors: c,
                      controller: controller,
                      tick: s.positionTick,
                      onActive: _onActive,
                    ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  /// Build a [LyricsQuery] from the currently-playing API song. Returns
  /// null when there isn't enough metadata to attempt a lookup — the UI
  /// then falls back to bundled lyrics.
  LyricsQuery? _queryFor(FeedItem? song) {
    if (song == null) return null;
    final title = song.title.trim();
    if (title.isEmpty) return null;
    final artist = _artistNameOf(song);
    if (artist.isEmpty) return null;
    return LyricsQuery(
      track: title,
      artist: artist,
      durationSec: _durationSecOf(song),
    );
  }

  static String _artistNameOf(FeedItem song) {
    final fromRefs = (song.artists ?? const <ApiArtistRef>[])
        .map((a) => a.name.trim())
        .where((n) => n.isNotEmpty)
        .toList();
    if (fromRefs.isNotEmpty) return fromRefs.first;
    return (song.subtitle ?? '').trim();
  }

  static int? _durationSecOf(FeedItem song) {
    final raw = (song.duration ?? '').trim();
    if (raw.isEmpty) return null;
    return int.tryParse(raw);
  }

  void _onActive(int idx, int total) {
    if (idx == _lastIdx) return;
    _lastIdx = idx;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!controller.hasClients) return;
      final target =
          (idx.clamp(0, total - 1) * 52.0 - 160)
              .clamp(0.0, controller.position.maxScrollExtent);
      controller.animateTo(target,
          // Longer + Material 3's emphasised curve — slower out, faster
          // settle — feels less mechanical than easeOutCubic when the
          // line below is fading up at the same time.
          duration: const Duration(milliseconds: 720),
          curve: Curves.easeInOutCubicEmphasized);
    });
  }
}

class _LiveLyrics extends ConsumerWidget {
  const _LiveLyrics({
    required this.query,
    required this.colors,
    required this.controller,
    required this.tick,
    required this.onActive,
  });

  final LyricsQuery query;
  final SunohColors colors;
  final ScrollController controller;
  final ValueListenable<int> tick;
  final void Function(int idx, int total) onActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(lyricsProvider(query));
    return async.when(
      loading: () => _Hint(colors: colors, label: 'Finding lyrics…'),
      error: (e, _) => _Hint(
        colors: colors,
        label: 'Couldn’t load lyrics',
        detail: '$e',
      ),
      data: (r) {
        if (r.instrumental) {
          return _Hint(
            colors: colors,
            label: 'Instrumental',
            detail: 'No lyrics for this track.',
          );
        }
        if (!r.found || r.lines.isEmpty) {
          return _Hint(
            colors: colors,
            label: 'No lyrics found',
            detail: 'Nobody has uploaded lyrics for this song yet.',
          );
        }
        return _LyricsBody(
          colors: colors,
          lines: r.lines,
          synced: r.synced,
          controller: controller,
          tick: tick,
          onActive: onActive,
        );
      },
    );
  }
}

class _LyricsBody extends StatelessWidget {
  const _LyricsBody({
    required this.colors,
    required this.lines,
    required this.synced,
    required this.controller,
    required this.tick,
    required this.onActive,
  });

  final SunohColors colors;
  final List<LyricLine> lines;
  final bool synced;
  final ScrollController controller;
  final ValueListenable<int> tick;
  final void Function(int idx, int total) onActive;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return ValueListenableBuilder<int>(
      valueListenable: tick,
      builder: (context, pos, _) {
        // Plain-text lyrics don't carry real timing — keep them static so
        // we don't pretend to highlight the "right" line.
        final idx = synced ? _activeIndex(lines, pos) : -1;
        if (synced) onActive(idx, lines.length);
        return ListView.builder(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 80),
          itemCount: lines.length,
          itemBuilder: (context, i) {
            final l = lines[i];
            if (l.line.trim().isEmpty) return const SizedBox(height: 14);
            final active = i == idx;
            final past = i < idx;
            // Duration + curve mirror the scroll animation so the line
            // grows up to "active" while the list eases into position —
            // they finish together instead of one ahead of the other.
            return AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 520),
              curve: Curves.easeInOutCubicEmphasized,
              style: SunohType.heading(
                fontSize: active ? 28 : 22,
                color: c.fg
                    .withValues(alpha: active ? 1.0 : (past ? 0.4 : 0.55)),
                height: 1.3,
                letterSpacing: -0.3,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(l.line),
              ),
            );
          },
        );
      },
    );
  }

  static int _activeIndex(List<LyricLine> lines, int position) {
    var idx = -1;
    for (var k = 0; k < lines.length; k++) {
      if (lines[k].t <= position) {
        idx = k;
      } else {
        break;
      }
    }
    return idx;
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.colors, required this.label, this.detail});
  final SunohColors colors;
  final String label;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 60, 28, 60),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: SunohType.heading(fontSize: 22, color: c.fgDim)),
            if (detail != null) ...[
              const SizedBox(height: 10),
              Text(detail!,
                  textAlign: TextAlign.center,
                  style: SunohType.sans(fontSize: 13, color: c.fgMute)),
            ],
          ],
        ),
      ),
    );
  }
}
