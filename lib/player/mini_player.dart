// Mini player — a card floating over the bottom bar, tinted by the artwork.
//
// It used to be transparent content inside the bar, separated from the feed by
// a hairline, which made it read as part of the chrome rather than as the song
// that is playing. As a card it has an edge of its own, and taking its colour
// from the sleeve ties it to the full player it opens into: the player grows
// out of this card's rectangle (player_route.dart reads it through
// [miniPlayerKey]) while the thumbnail flies up as the big cover.
//
// Tap it, or drag it upwards, to open the player. The tint is a flat blend
// over `bgSoft`, not a gradient or a blur, so it costs one fill.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../cast/cast_button.dart';
import '../providers/app_state_provider.dart';
import '../providers/palette_provider.dart';
import '../router/router.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/cover_hero.dart' show straightRectTween;
import '../widgets/playing_bars.dart';
import '../widgets/quality_tag.dart';
import '../widgets/ui.dart';
import 'cover_carousel.dart' show kPlayerArtCurve, kPlayerArtHeroTag;
import 'player_route.dart';

class MiniPlayer extends ConsumerStatefulWidget {
  const MiniPlayer({super.key});

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer> {
  /// Upward drag so far, negative; the card follows at 40% of the finger.
  double _lift = 0;

  void _endLift(DragEndDetails d) {
    final open = _lift < -36 || (d.primaryVelocity ?? 0) < -500;
    setState(() => _lift = 0);
    if (open) context.openPlayer();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final track = s.current;

    // The live palette for the current artwork, read directly rather than
    // through AppState's cached accent, which lags the track change.
    final url = s.currentApiSong?.artwork ?? '';
    final palette = url.isEmpty
        ? null
        : ref.watch(artPaletteProvider(url)).value;
    final accent = s.themedAccent(palette?.accent ?? s.resolvedAccent);
    // Stronger on dark: the same alpha over a light card reads twice as
    // saturated, and pushes the artist line below contrast.
    final card = Color.alphaBlend(
      accent.withValues(alpha: s.isLight ? 0.14 : 0.26),
      c.bgSoft,
    );

    return GestureDetector(
      onTap: () => context.openPlayer(),
      onVerticalDragUpdate: (d) =>
          setState(() => _lift = (_lift + d.delta.dy).clamp(-120.0, 0.0)),
      onVerticalDragEnd: _endLift,
      behavior: HitTestBehavior.opaque,
      // Margin outside the keyed box, so the rectangle the player opens
      // from is the card itself.
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
        child: AnimatedContainer(
          key: miniPlayerKey,
          duration: _lift == 0 ? SunohMotion.ui : Duration.zero,
          curve: SunohMotion.arrive,
          transform: Matrix4.translationValues(0, _lift * 0.4, 0),
          height: 56,
          decoration: squircleDecoration(
            radius: SunohRadius.card,
            color: card,
            shadows: [
              BoxShadow(
                color: Colors.black.withValues(alpha: s.isLight ? 0.10 : 0.45),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Stack(
            children: [
              Row(
                children: [
                  const SizedBox(width: 6),
                  Hero(
                    tag: kPlayerArtHeroTag,
                    createRectTween: straightRectTween,
                    curve: kPlayerArtCurve,
                    reverseCurve: kPlayerArtCurve,
                    transitionOnUserGestures: true,
                    child: SunohArt(
                      id: track.id,
                      imageUrl: s.currentApiSong?.artwork,
                      size: 44,
                      radius: SunohRadius.row,
                      shadow: false,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Titles(s: s, colors: c),
                  ),
                  // Flips its glyph and colour while a cast session is live.
                  const CastButton(size: 20, width: 44, height: 44),
                  _button(
                    s.isPlaying
                        ? PhosphorIconsFill.pause
                        : PhosphorIconsFill.play,
                    c.fg,
                    s.playPause,
                  ),
                  _button(PhosphorIconsFill.skipForward, c.fg, s.next),
                  const SizedBox(width: 4),
                ],
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 0,
                child: ValueListenableBuilder<int>(
                  valueListenable: s.positionTick,
                  builder: (_, pos, _) =>
                      _Progress(pos: pos, max: s.currentDurationSec, colors: c),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _button(IconData icon, Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox.square(
          dimension: 44,
          child: Icon(icon, size: 22, color: color),
        ),
      );
}

class _Titles extends StatelessWidget {
  const _Titles({required this.s, required this.colors});
  final AppState s;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          s.current.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: SunohType.sans(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: c.fg,
          ),
        ),
        Row(
          children: [
            if (s.isPlaying) ...[
              PlayingBars(color: c.fg, size: 10),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                s.current.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SunohType.sans(fontSize: 12.5, color: c.fgDim),
              ),
            ),
            // Compact form: the mark plus a shortened format. Flexible so a
            // long artist name and a long format line share the row.
            const SizedBox(width: 8),
            Flexible(child: QualityTag(colors: c, compact: true)),
          ],
        ),
      ],
    );
  }
}

/// The 2dp progress line along the card's bottom edge, in ink — the card is
/// already the accent's colour, so an accent line had nowhere to stand out.
class _Progress extends StatelessWidget {
  const _Progress({required this.pos, required this.max, required this.colors});
  final int pos;
  final int max;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    final f = max <= 0 ? 0.0 : (pos / max).clamp(0.0, 1.0);
    return SizedBox(
      height: 2,
      child: DecoratedBox(
        decoration: squircleDecoration(
          radius: 1,
          color: colors.fg.withValues(alpha: 0.18),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: f,
            child: DecoratedBox(
              decoration: squircleDecoration(radius: 1, color: colors.fg),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }
}
