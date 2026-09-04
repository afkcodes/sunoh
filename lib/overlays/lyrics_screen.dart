// Karaoke lyrics overlay: active-line highlight, a word-by-word sweep where
// the source gave word timings, and auto-scroll.
//
// Lyrics are looked up across every source in `lib/api/lyrics/`, keyed by the
// currently playing API song's title + artist + duration. When there's no API
// song (dummy/local catalog tracks, the cold-launch landing track) we fall
// back to the bundled `kLyrics` map so the screen still demos.
//
// This file is the sheet's chrome. The list itself is `lyrics_body.dart`.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';

import '../api/dto.dart';
import '../audio/lyrics_clock.dart';
import '../data/catalog.dart';
import '../providers/app_state_provider.dart';
import '../providers/lyrics_provider.dart';
import '../share/share_link.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/ui.dart';
import 'lyrics_body.dart';
import 'lyrics_parts.dart';

class LyricsScreen extends ConsumerStatefulWidget {
  const LyricsScreen({super.key});
  @override
  ConsumerState<LyricsScreen> createState() => _LyricsScreenState();
}

/// The accent wash over the sheet: how strong it starts, and how far down it
/// has faded to nothing. The scrim at the top of the lyric list has to
/// reproduce this exactly at its own height, so both live here rather than
/// inline in the one place that used to need them.
const double _kTintAlpha = 0.22;
const double _kTintStop = 0.55;

class _LyricsScreenState extends ConsumerState<LyricsScreen>
    with SingleTickerProviderStateMixin {
  final controller = ScrollController();

  /// Milliseconds, running at vsync — the whole reason word timing is
  /// possible. Lives for the length of the sheet only; nothing else in the app
  /// needs a clock this fine, and one running behind a closed sheet would be a
  /// frame callback for nothing.
  LyricsClock? _clock;

  @override
  void initState() {
    super.initState();
    final state = ref.read(appStateProvider);
    final handler = state.audioRepo?.handler;
    if (handler != null) {
      _clock = LyricsClock(
        vsync: this,
        positions: handler.positionStream,
        positionNow: () => handler.position,
        // The AppState instance is stable for the app's life, so this reads a
        // field rather than going through the provider container sixty times
        // a second.
        isPlaying: () => state.isPlaying,
      );
      return;
    }
    // No engine behind the sheet — the bundled demo lyrics on a dummy track.
    // The 1 Hz tick is all there is, and line-synced demo text is all it has
    // to drive.
    _tick = state.positionTick;
    _tick!.addListener(_onTick);
    _onTick();
  }

  /// Stands in for [_clock] when there is no engine; see [initState].
  final ValueNotifier<int> _fallback = ValueNotifier<int>(0);
  ValueNotifier<int>? _tick;

  void _onTick() => _fallback.value = (_tick?.value ?? 0) * 1000;

  ValueListenable<int> get _positionMs => _clock ?? _fallback;

  /// Tapping a line jumps playback to it.
  ///
  /// AppState.seek deals in whole seconds, so this floors rather than rounds:
  /// landing a hair before the line means its first word is still sung, where
  /// rounding up would clip it.
  void _seekTo(int timeMs) =>
      ref.read(appStateProvider).seek((timeMs / 1000).floor());

  @override
  void dispose() {
    _tick?.removeListener(_onTick);
    _fallback.dispose();
    _clock?.dispose();
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
    return ColoredBox(
      color: c.bg,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              accent.withValues(alpha: _kTintAlpha),
              Colors.transparent,
            ],
            stops: const [0, _kTintStop],
          ),
        ),
        child: LayoutBuilder(
          builder: (context, box) {
            final sheetHeight = box.maxHeight;
            return SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconBtn(
                          icon: SolarIconsOutline.altArrowDown,
                          color: c.fgDim,
                          size: 22,
                          onTap: () => context.pop(),
                        ),
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
                              subtitle:
                                  apiSong.displaySubtitle ?? apiSong.subtitle,
                              source: apiSong.source,
                            );
                          },
                        ),
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
                          radius: 6,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                track.title,
                                style: SunohType.sans(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w500,
                                  color: c.fg,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                track.artist,
                                style: SunohType.sans(
                                  fontSize: 12,
                                  color: c.fgMute,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _FadedEdges(
                      colors: c,
                      accent: accent,
                      sheetHeight: sheetHeight,
                      child: query == null
                          ? LyricsBody(
                              colors: c,
                              lines: fallbackLines,
                              synced: true,
                              controller: controller,
                              clock: _positionMs,
                              onSeek: _seekTo,
                            )
                          : _LiveLyrics(
                              query: query,
                              colors: c,
                              controller: controller,
                              clock: _positionMs,
                              onSeek: _seekTo,
                            ),
                    ),
                  ),
                ],
              ),
            );
          },
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
      // SimpMusic matches on the video id, which is the one source that cannot
      // hand back a different edit of the song. Only YouTube tracks have one;
      // for everything else it stays empty and that source sits the race out.
      videoId: song.source == 'youtube' ? song.id : '',
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
}

class _LiveLyrics extends ConsumerWidget {
  const _LiveLyrics({
    required this.query,
    required this.colors,
    required this.controller,
    required this.clock,
    required this.onSeek,
  });

  final LyricsQuery query;
  final SunohColors colors;
  final ScrollController controller;
  final ValueListenable<int> clock;
  final void Function(int timeMs) onSeek;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(lyricsProvider(query));
    return async.when(
      loading: () => LyricsHint(colors: colors, label: 'Finding lyrics…'),
      error: (e, _) => LyricsHint(
        colors: colors,
        label: 'Couldn’t load lyrics',
        detail: '$e',
      ),
      data: (r) {
        if (r.instrumental) {
          return LyricsHint(
            colors: colors,
            label: 'Instrumental',
            detail: 'No lyrics for this track.',
          );
        }
        if (!r.found || r.lines.isEmpty) {
          return LyricsHint(
            colors: colors,
            label: 'No lyrics found',
            detail: 'None of the lyrics databases had this song.',
          );
        }
        return LyricsBody(
          colors: colors,
          lines: r.lines,
          synced: r.synced,
          controller: controller,
          clock: clock,
          onSeek: onSeek,
          source: r.source,
        );
      },
    );
  }
}

/// Softens the top and bottom of the lyric list so lines dissolve into the
/// sheet instead of being cut off mid-stroke at the header.
///
/// Two gradient scrims painted over the list, not a [ShaderMask] over it. The
/// mask is the tidier tool and the wrong one here: it puts a layer the height
/// of the whole list into every frame the list scrolls, which is the sort of
/// thing this GPU is worst at. A scrim is one gradient rect and no layer.
///
/// The cost of that choice is that a scrim has to *match* what it fades into
/// rather than erasing it — paint the wrong colour and the fade reads as a
/// band across the top of the list rather than as nothing at all. Which is
/// what a guessed accent alpha did: measured against the real backdrop it was
/// eleven levels of red too bright, and the seam was visible.
///
/// So it isn't guessed. The sheet's wash is a known gradient over a known
/// height ([_kTintAlpha] fading out by [_kTintStop]), and this widget is
/// handed that height, so the tint at its own top edge is arithmetic. Paint a
/// colour over itself and it disappears at any alpha, which is exactly what a
/// scrim needs.
class _FadedEdges extends StatelessWidget {
  const _FadedEdges({
    required this.colors,
    required this.accent,
    required this.sheetHeight,
    required this.child,
  });

  final SunohColors colors;
  final Color accent;

  /// Height of the box the sheet's gradient is painted over.
  final double sheetHeight;

  final Widget child;

  /// The colour the sheet is painting at [y] down its own gradient.
  ///
  /// Reproduced by lerping the same two stops the gradient has, rather than
  /// by fading the accent's alpha — which is what the first attempt did, and
  /// why the fade still showed as a band. The second stop is
  /// `Colors.transparent`, and transparent is transparent *black*: the wash
  /// darkens towards black as it thins, so accent-at-lower-alpha stays too
  /// warm and too bright the whole way down. Measured, the scrim was painting
  /// the sheet's full-strength colour a third of the way down the screen.
  Color _sheetColourAt(double y) {
    if (sheetHeight <= 0) return colors.bg;
    final through = (y / (sheetHeight * _kTintStop)).clamp(0.0, 1.0);
    final wash = Color.lerp(
      accent.withValues(alpha: _kTintAlpha),
      Colors.transparent,
      through,
    )!;
    return Color.alphaBlend(wash, colors.bg);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      // This widget fills what is left under the header, so its own top edge
      // sits that far down the sheet.
      final top = sheetHeight - box.maxHeight;
      final atTop = _sheetColourAt(top);
      final atBottom = _sheetColourAt(sheetHeight);

      return Stack(
        children: [
          Positioned.fill(child: child),
          // Ignoring pointers matters: a tap on a faded line still has to
          // reach the line, now that tapping one seeks to it.
          _Scrim(color: atTop, height: _kTopFade, fromTop: true),
          _Scrim(color: atBottom, height: _kBottomFade, fromTop: false),
        ],
      );
    },
  );
}

/// Deep enough that a line dissolves over several of its own rows rather than
/// stepping out over a few pixels — the fade being short is half of what made
/// the old one read as an edge.
const double _kTopFade = 76;
const double _kBottomFade = 104;

class _Scrim extends StatelessWidget {
  const _Scrim({
    required this.color,
    required this.height,
    required this.fromTop,
  });

  final Color color;
  final double height;
  final bool fromTop;

  @override
  Widget build(BuildContext context) => Positioned(
    top: fromTop ? 0 : null,
    bottom: fromTop ? null : 0,
    left: 0,
    right: 0,
    height: height,
    child: IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: fromTop ? Alignment.topCenter : Alignment.bottomCenter,
            end: fromTop ? Alignment.bottomCenter : Alignment.topCenter,
            // Eased rather than linear. A straight ramp gives away where it
            // starts, because alpha falls fastest exactly at the opaque end;
            // holding it there and letting go slowly puts the visible part of
            // the change in the middle, where there is no edge to notice.
            colors: [
              color,
              color.withValues(alpha: 0.72),
              color.withValues(alpha: 0),
            ],
            stops: const [0, 0.42, 1],
          ),
        ),
      ),
    ),
  );
}
