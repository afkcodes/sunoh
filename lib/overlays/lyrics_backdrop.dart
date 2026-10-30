// The lyrics page's colour, and the two scrims that fade the lyric list into
// it.
//
// Split out of `lyrics_screen.dart` because the two halves have to agree to
// the pixel: the scrims do not erase the list, they paint the page's own
// colour over it, so they must know exactly what colour the page is at every
// height. Keeping the gradient and the arithmetic that reproduces it in one
// file is what stops them drifting apart.
//
// The page wears the player's treatment, so moving between the two reads as
// the same room: the artwork's accent mixed 42% into the ground at the top,
// 16% at just past half way, and the bare ground from 92% down. The accent
// tweens over 700 ms when the track changes, like every artwork colour in the
// app, rather than snapping.

import 'package:flutter/material.dart';

/// The gradient's stops, as fractions of the page height, and how much accent
/// is mixed into the ground at the first two.
const double _kTopMix = 0.42;
const double _kMidMix = 0.16;
const double _kMidStop = 0.52;
const double _kEndStop = 0.92;

const Duration _kTween = Duration(milliseconds: 700);

/// The page's colour [t] of the way down (0 top, 1 bottom), for accent [tone]
/// over ground [bg].
///
/// Opaque all the way, which is what makes it reproducible: the old wash
/// faded the accent's alpha toward `Colors.transparent` — transparent black —
/// so it darkened as it thinned and no scrim painted in "accent at lower
/// alpha" ever matched it. Mixing into the ground has no such trap; a lerp
/// between the same stops the gradient uses lands on the same colour.
Color lyricsPageColourAt(Color tone, Color bg, double t) {
  final top = Color.lerp(bg, tone, _kTopMix)!;
  final mid = Color.lerp(bg, tone, _kMidMix)!;
  if (t <= _kMidStop) return Color.lerp(top, mid, t / _kMidStop)!;
  if (t <= _kEndStop) {
    return Color.lerp(mid, bg, (t - _kMidStop) / (_kEndStop - _kMidStop))!;
  }
  return bg;
}

/// The full-bleed page gradient.
class LyricsBackdrop extends StatelessWidget {
  const LyricsBackdrop({super.key, required this.tone, required this.bg});

  final Color tone;
  final Color bg;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<Color?>(
    tween: ColorTween(end: tone),
    duration: _kTween,
    curve: Curves.easeOut,
    builder: (_, value, _) {
      final t = value ?? tone;
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(bg, t, _kTopMix)!,
              Color.lerp(bg, t, _kMidMix)!,
              bg,
            ],
            stops: const [0, _kMidStop, _kEndStop],
          ),
        ),
      );
    },
  );
}

/// Softens the top and bottom of the lyric list so lines dissolve into the
/// page instead of being cut off mid-stroke at the header.
///
/// Two gradient scrims painted over the list, not a [ShaderMask] over it. The
/// mask is the tidier tool and the wrong one here: it puts a layer the height
/// of the whole list into every frame the list scrolls, which is the sort of
/// thing this GPU is worst at. A scrim is one gradient rect and no layer.
///
/// The cost of that choice is that a scrim has to *match* what it fades into
/// rather than erasing it — paint the wrong colour and the fade reads as a
/// band across the top of the list. So it is not guessed: this widget is
/// handed the page's height, works out where its own edges sit on it, and
/// asks [lyricsPageColourAt] for the colour there. Paint a colour over itself
/// and it disappears at any alpha, which is exactly what a scrim needs.
///
/// It tweens [tone] on the same duration and curve as [LyricsBackdrop], so
/// the two move in step through a track change. Only the scrims rebuild per
/// frame of that tween; the list is passed through as the builder's child.
class LyricsFadedEdges extends StatelessWidget {
  const LyricsFadedEdges({
    super.key,
    required this.tone,
    required this.bg,
    required this.pageHeight,
    required this.child,
  });

  final Color tone;
  final Color bg;

  /// Height of the box [LyricsBackdrop] is painted over.
  final double pageHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      // This widget runs to the bottom of the page, so its own top edge sits
      // its height up from there.
      final top = pageHeight <= 0
          ? 0.0
          : ((pageHeight - box.maxHeight) / pageHeight).clamp(0.0, 1.0);
      return TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: tone),
        duration: _kTween,
        curve: Curves.easeOut,
        child: child,
        builder: (_, value, list) {
          final t = value ?? tone;
          return Stack(
            children: [
              Positioned.fill(child: list!),
              // Ignoring pointers matters: a tap on a faded line still has to
              // reach the line, now that tapping one seeks to it.
              _Scrim(
                color: lyricsPageColourAt(t, bg, top),
                height: _kTopFade,
                fromTop: true,
              ),
              _Scrim(color: bg, height: _kBottomFade, fromTop: false),
            ],
          );
        },
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
