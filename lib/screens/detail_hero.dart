// The album-style hero and the actions row under it.
//
// Album, playlist, show, episode and the library's own playlists
// all open the same way: a wash of the page's colour running up under the
// bar, a centred cover that drifts and fades as the list slides over it, a
// left-aligned title block, then the page's icons with shuffle and the big
// play disc on the right.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:remixicon/remixicon.dart';

import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/cover_hero.dart';
import '../widgets/motion.dart';
import '../widgets/ui.dart';
import 'detail_chrome.dart';

/// The album-style hero: a wash of the page colour that runs up under the
/// bar, a centred cover with parallax, then a left-aligned title, byline and
/// meta line.
class DetailHero extends StatelessWidget {
  const DetailHero({
    super.key,
    required this.colors,
    required this.colour,
    required this.scroll,
    required this.cover,
    required this.title,
    this.byline,
    this.bylineArt,
    this.meta,
  });

  final SunohColors colors;
  final Color colour;
  final ValueListenable<double> scroll;
  final Widget cover;
  final String title;
  final String? byline;

  /// Shown as a 22 circle before the byline — the artist's own picture.
  final String? bylineArt;
  final String? meta;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final inset = MediaQuery.paddingOf(context).top;
    final by = byline ?? '';
    final art = bylineArt ?? '';
    final m = meta ?? '';
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: colour),
      duration: kArtColourTween,
      curve: SunohMotion.ease,
      builder: (context, tint, child) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(c.bg, tint, 0.32)!,
              Color.lerp(c.bg, tint, 0.10)!,
              c.bg,
            ],
            stops: const [0, 0.7, 1],
          ),
        ),
        child: child,
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, inset + kDetailBarHeight + 8, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: _CoverParallax(scroll: scroll, child: cover),
            ),
            const SizedBox(height: 22),
            FadeSlideIn(
              child: Text(
                title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: SunohType.heading(
                  fontSize: 28,
                  color: c.fg,
                  height: 1.15,
                ),
              ),
            ),
            if (by.isNotEmpty) ...[
              const SizedBox(height: 8),
              FadeSlideIn(
                index: 1,
                child: Row(
                  children: [
                    if (art.isNotEmpty) ...[
                      SunohArt(
                        id: by,
                        imageUrl: art,
                        size: 22,
                        radius: 999,
                        shadow: false,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        by,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SunohType.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: c.fg,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (m.isNotEmpty) ...[
              const SizedBox(height: 4),
              FadeSlideIn(
                index: 2,
                child: Text(
                  m,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: SunohType.mono(fontSize: 13, color: c.fgDim),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The hero cover drifts down, shrinks toward its bottom edge and fades as
/// the page scrolls, so the list appears to slide up over it.
class _CoverParallax extends StatelessWidget {
  const _CoverParallax({required this.scroll, required this.child});
  final ValueListenable<double> scroll;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: scroll,
      child: child,
      builder: (context, o, child) {
        final s = math.max(0.72, 1 - o / 700);
        return Opacity(
          opacity: math.max(0.0, 1 - o / 320),
          child: Transform(
            alignment: Alignment.bottomCenter,
            transform: Matrix4.translationValues(0, o * 0.35, 0)
              ..multiply(Matrix4.diagonal3Values(s, s, 1)),
            child: child,
          ),
        );
      },
    );
  }
}

/// The 236 hero cover with its long drop shadow. [child] replaces the artwork
/// for pages that have none of their own (Liked Songs, an empty playlist).
class DetailCover extends StatelessWidget {
  const DetailCover({
    super.key,
    required this.id,
    this.imageUrl,
    this.child,
    this.round = false,
    this.hero,
  });
  final String id;
  final String? imageUrl;
  final Widget? child;

  /// The cover this page was opened from: this cover flies to and from it,
  /// and shows its art until its own has decoded.
  final CoverHeroRef? hero;

  /// A circle, for an artist.
  final bool round;

  static const double size = 236;

  @override
  Widget build(BuildContext context) {
    // Heavy on the dark ground, where it reads as depth; on the light one
    // the same shadow is a grey smear, so it is a fraction of it there.
    final light = Theme.of(context).brightness == Brightness.light;
    return DecoratedBox(
      decoration: squircleDecoration(
        radius: round ? 999 : SunohRadius.cover,
        shadows: [
          BoxShadow(
            color: SunohMedia.scrim.withValues(alpha: light ? 0.18 : 0.55),
            blurRadius: 50,
            offset: const Offset(0, 22),
          ),
        ],
      ),
      child:
          child ??
          CoverHero(
            tag: hero?.tag,
            preview: hero,
            id: id,
            imageUrl: imageUrl,
            size: size,
            radius: round ? 999 : SunohRadius.cover,
          ),
    );
  }
}

/// The actions row under a hero: the page's own icons on the left, shuffle
/// and the big play button on the right.
class DetailActions extends StatelessWidget {
  const DetailActions({
    super.key,
    required this.colors,
    required this.colour,
    required this.playing,
    this.leading = const [],
    this.onPlay,
    this.onShuffle,
    this.shuffle = true,
    this.padding = const EdgeInsets.fromLTRB(10, 12, 16, 0),
  });

  final SunohColors colors;
  final Color colour;
  final bool playing;
  final List<Widget> leading;
  final VoidCallback? onPlay;

  /// Null greys the shuffle out (an empty list); [shuffle] false leaves it
  /// off altogether, for pages where shuffling makes no sense (a show's
  /// episodes, a single episode).
  final VoidCallback? onShuffle;
  final bool shuffle;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        spacing: 4,
        children: [
          ...leading,
          const Spacer(),
          if (shuffle)
            IconBtn(
              icon: RemixIcons.shuffle_line,
              color: onShuffle == null ? colors.fgMute : colors.fg,
              onTap: onShuffle,
            ),
          BigPlayButton(
            colors: colors,
            colour: colour,
            playing: playing,
            onTap: onPlay,
          ),
        ],
      ),
    );
  }
}

/// The 56 play disc, filled with the page's colour. Greys out when there is
/// nothing to play.
class BigPlayButton extends StatelessWidget {
  const BigPlayButton({
    super.key,
    required this.colors,
    required this.colour,
    required this.playing,
    this.onTap,
  });

  final SunohColors colors;
  final Color colour;
  final bool playing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Pressable(
      scale: 0.93,
      onTap: onTap,
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: enabled ? colour : colors.surface2),
        duration: kArtColourTween,
        curve: SunohMotion.ease,
        builder: (context, fill, _) => Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
          child: Icon(
            playing ? PhosphorIconsFill.pause : PhosphorIconsFill.play,
            size: 24,
            color: enabled ? inkOn(fill ?? colour) : colors.fgMute,
          ),
        ),
      ),
    );
  }
}
