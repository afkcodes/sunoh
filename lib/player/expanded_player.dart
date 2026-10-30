// The expanded player.
//
// Top to bottom: where the music is playing from, the cover (swipe it to
// skip), title and artist with the like button, a waveform scrubber, the
// transport, and the output device with the player's tools. The ground is a
// gradient taken from the cover's colour, strongest at the top and gone by
// the controls, so the colour belongs to the song but never sits behind text
// it was not checked against.
//
// The full-bleed artwork backdrop (immersive_backdrop.dart) was replaced by
// this layout in the 2026 redesign; the cover is a square again so it can
// fly in from the mini player's thumbnail and be swiped between songs.
//
// Opening and closing are owned by player_route.dart. Drag the page down to
// close; it follows the finger and springs back if let go early.
//
// PERF: the position tick only reaches the scrubber (a ValueListenableBuilder
// inside WaveformScrubber); the rest of the page rebuilds on track and state
// changes only.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:remixicon/remixicon.dart';

import '../api/dto.dart';
import '../data/catalog.dart';
import '../data/lyric_line.dart';
import '../overlays/track_menu_sheet.dart';
import '../providers/app_state_provider.dart';
import '../providers/palette_provider.dart';
import '../router/router.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/quality_tag.dart';
import '../widgets/ui.dart';
import 'cover_carousel.dart';
import 'marquee_text.dart';
import 'player_bottom.dart';
import 'player_controls.dart';
import 'player_route.dart';
import 'waveform_scrubber.dart';

/// Height everything under the cover needs at its gaps, used to shrink the
/// cover on a short screen rather than overflow. On a tall screen the cover
/// stops at the width and the Spacers around the block in _Body share the
/// rest.
const double _kBelowCover = 362;

class ExpandedPlayer extends ConsumerStatefulWidget {
  const ExpandedPlayer({super.key});
  @override
  ConsumerState<ExpandedPlayer> createState() => _ExpandedPlayerState();
}

class _ExpandedPlayerState extends ConsumerState<ExpandedPlayer> {
  /// The route's hand-driven close (player_route.dart). The drag below only
  /// reports distance; the route moves the page and the cover together.
  PlayerDismiss? _dismiss;
  bool _dragging = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dismiss = playerDismissOf(context);
  }

  void _onDragUpdate(DragUpdateDetails d) {
    final dismiss = _dismiss;
    if (dismiss == null) return;
    if (!_dragging) {
      // Only a downward pull starts a close; an upward flick does nothing.
      if (d.delta.dy <= 0) return;
      _dragging = true;
      dismiss.begin();
    }
    dismiss.update(d.delta.dy);
  }

  void _onDragEnd(DragEndDetails d) {
    if (!_dragging) return;
    _dragging = false;
    _dismiss?.end(d.primaryVelocity ?? 0);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final url = s.currentApiSong?.artwork ?? '';
    final palette = url.isEmpty
        ? null
        : ref.watch(artPaletteProvider(url)).value;
    final accent = s.themedAccent(palette?.accent ?? s.resolvedAccent);

    return GestureDetector(
      onVerticalDragUpdate: _onDragUpdate,
      onVerticalDragEnd: _onDragEnd,
      onVerticalDragCancel: () => _onDragEnd(DragEndDetails()),
      child: Stack(
        children: [
          Positioned.fill(
            child: _Backdrop(tint: accent, colors: c, isLight: s.isLight),
          ),
          SafeArea(
            child: Column(
              children: [
                PlayerEntrance(
                  order: 0,
                  child: _Header(s: s, colors: c),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) => _Body(
                      s: s,
                      colors: c,
                      coverSize: math.min(
                        box.maxWidth - 48,
                        box.maxHeight - _kBelowCover,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The cover's colour, strongest at the top and gone by the controls. Half
/// the strength on light, where the same mix turns the page muddy behind
/// dark text.
class _Backdrop extends StatelessWidget {
  const _Backdrop({
    required this.tint,
    required this.colors,
    required this.isLight,
  });
  final Color tint;
  final SunohColors colors;
  final bool isLight;

  @override
  Widget build(BuildContext context) {
    final bg = colors.bg;
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: tint),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOut,
      builder: (_, t, _) {
        final tone = t ?? tint;
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0, 0.52, 0.92],
              colors: [
                Color.lerp(bg, tone, isLight ? 0.22 : 0.42)!,
                Color.lerp(bg, tone, isLight ? 0.08 : 0.16)!,
                bg,
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.s, required this.colors});
  final AppState s;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    // API songs carry "PLAYLIST · Title" / "ALBUM · Title": the category is
    // the eyebrow and the rest is the name. The dummy path falls back to the
    // album.
    var eyebrowText = 'PLAYING FROM';
    final String mainText;
    final label = s.apiSourceLabel;
    if (label != null && label.isNotEmpty) {
      final parts = label.split(' · ');
      if (parts.length >= 2) eyebrowText = parts.first;
      mainText = parts.length >= 2 ? parts.sublist(1).join(' · ') : label;
    } else {
      mainText = albumOf(s.current.album)?.title ?? 'Library';
    }
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            IconBtn(
              icon: RemixIcons.arrow_down_s_line,
              color: c.fg,
              size: 24,
              onTap: () => context.pop(),
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  eyebrow(eyebrowText, c.fgDim, size: 10, letterSpacing: 1.2),
                  const SizedBox(height: 2),
                  Text(
                    mainText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: SunohType.sans(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: c.fg,
                    ),
                  ),
                ],
              ),
            ),
            IconBtn(
              icon: RemixIcons.more_fill,
              color: c.fg,
              size: 22,
              onTap: () {
                final song = s.currentApiSong;
                if (song == null) return;
                showTrackMenuSheet(
                  context,
                  song: song,
                  sourceLabel: s.apiSourceLabel,
                  sourceRef: s.apiSourceRef,
                  // Pop the player before pushing a destination, or the
                  // album lands behind it and looks like nothing happened.
                  fromPlayer: true,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.s, required this.colors, required this.coverSize});
  final AppState s;
  final SunohColors colors;
  final double coverSize;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final track = s.current;
    final repo = s.currentApiSong == null ? null : s.audioRepo;
    final q = repo?.queue ?? const <FeedItem>[];
    final i = repo?.currentIndex ?? 0;

    // The prototype's fixed gaps between cover, title, waveform, controls and
    // tools, with the height the cover cannot use (it is capped by the width)
    // split around the whole block, a third above and two thirds below, so
    // the cover stays high under the header. Shared
    // between the gaps instead, it opened a hole under the controls once the
    // up-next card was gone.
    return Column(
      children: [
        const SizedBox(height: 14),
        const Spacer(),
        CoverCarousel(
          size: coverSize,
          currentId: track.id,
          currentArt: s.currentApiSong?.artwork,
          prev: i > 0 && i - 1 < q.length ? q[i - 1] : null,
          next: i + 1 < q.length ? q[i + 1] : null,
          onNext: s.next,
          // The swipe means "the song before", even past the first few
          // seconds where the back button restarts the current one.
          onPrev: () => repo == null ? s.prev() : repo.previous(),
        ),
        const SizedBox(height: 20),
        PlayerEntrance(
          order: 0,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _TitleBlock(s: s, c: c, lyric: _currentLyric(s)),
                ),
                LikeButton(
                  liked: s.isLikedCurrentApi,
                  colors: c,
                  onTap: () {
                    final item = s.currentApiSong;
                    item != null ? s.toggleLikedApi(item) : s.toggleLike();
                  },
                ),
              ],
            ),
          ),
        ),
        PlayerEntrance(
          order: 1,
          child: Padding(
            // 10 over the prototype's gaps: it crowded the title and controls.
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
            child: WaveformScrubber(
              trackId: track.id,
              waveform: repo?.waveform,
              position: s.positionTick,
              duration: s.currentDurationSec,
              onSeek: s.seek,
              colors: c,
            ),
          ),
        ),
        PlayerEntrance(
          order: 2,
          child: PlayerTransport(s: s, c: c),
        ),
        const SizedBox(height: 16),
        PlayerEntrance(
          order: 3,
          child: PlayerTools(s: s, c: c),
        ),
        // The queue is one tap away in the tools row; the player does not
        // preview the next song.
        const Spacer(flex: 2),
        const SizedBox(height: 16),
      ],
    );
  }

  /// The synced lyric line at the current position, or null when the song
  /// has no lyrics (most live API songs).
  static String? _currentLyric(AppState s) {
    final lines = kLyrics[s.currentApiSong?.id ?? s.current.id];
    if (lines == null || lines.isEmpty) return null;
    final posMs = s.position * 1000;
    LyricLine? active;
    for (final l in lines) {
      if (l.timeMs > posMs) break;
      if (l.text.trim().isNotEmpty) active = l;
    }
    return active?.text;
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.s, required this.c, required this.lyric});
  final AppState s;
  final SunohColors c;
  final String? lyric;

  @override
  Widget build(BuildContext context) {
    final track = s.current;
    final line = lyric;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MarqueeText(
          track.title,
          style: SunohType.heading(fontSize: 23, color: c.fg, height: 1.2),
        ),
        const SizedBox(height: 2),
        Text(
          track.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: SunohType.sans(fontSize: 16, color: c.fgDim),
        ),
        // Renders nothing for an ordinary lossy track.
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: QualityTag(colors: c),
        ),
        if (line != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: LyricsTeaser(
              line: line,
              accent: c.accent,
              onTap: () => context.openLyrics(),
            ),
          ),
      ],
    );
  }
}
