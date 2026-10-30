// The player's full-bleed artwork, and the scrim that makes text readable on
// top of it.
//
// ## Why the sleeve stopped being a square
//
// The cover used to sit in a fixed square well with the screen's own colour
// around it, and the artwork was a picture *of* the record rather than the
// surface you were looking at. Filling the screen with it is the difference
// between a page about a song and a page that is the song — the same move
// Apple Music and Spotify both make on their now-playing screens.
//
// `BoxFit.cover`, and it is a considered choice rather than the default.
// `fitWidth` was tried: it shows the whole sleeve with nothing cropped, and it
// ends the upscale, but a square cover then fills only the top 45% of the
// screen and the 10% between its bottom edge and the title reads as a hole.
// Fading that edge into the background did not rescue it. Covering the screen
// is the look this player is for, and the cost — losing roughly half the
// sleeve's width, and drawing a 1200px source at 2780px tall — is the price of
// it. If it is revisited, the thing to change is the layout below, not the fit.
//
// ## There is no blurred copy behind it, and there never should have been
//
// One shipped here, to fill the letterbox a non-square cover would leave. It
// could not: the layer in front is `BoxFit.cover`, which fills its box for
// every source aspect there is, so the fill was behind an opaque image on
// every frame it was ever drawn. What it did do was re-rasterise a sigma-40
// full-screen blur on each frame of the drag-to-dismiss, which is what made
// this screen feel heavy. `ColoredBox` is the honest version of "something to
// land on".
//
// ## The scrim is two gradients, not one
//
// A single top-to-bottom fade dark enough to read against turns the artwork to
// mud. Two do the job with less: a short one at the top so the header's
// controls have something to sit on, and a stronger one rising from the bottom
// where the title, scrubber and transport actually live. Between them the
// cover is left alone, which is the part worth seeing.
//
// "Between them" is the whole trick and it was not true at first. The bottom
// gradient ran to a final stop of 1 — the top of the screen — so it was still
// laying about half its darkness across the middle of the cover. Nothing there
// needed a scrim; the effect was just haze, and it read as the artwork being
// blurry rather than as a gradient. It now ends well short of the header, and
// what darkness it does spend is spent lower down where the controls are.

import 'package:flutter/material.dart';

import '../widgets/album_art.dart';

/// Cover brightness at which dimming starts, and where it reaches full
/// strength.
///
/// Measured off two screenshots of this player rather than guessed. A dark
/// poster (Dhurandhar) fills the screen at 0.16 mean luminance; a white one
/// (a wedding-album sleeve) reaches 0.37 overall and 0.75 across the upper
/// band, which is near-white behind white header text. The window sits above
/// every cover that already looked right, so nothing that was fine gets
/// touched.
const double _kDimFrom = 0.42;
const double _kDimTo = 0.75;

/// Most the cover is ever dimmed by.
///
/// Stops short of the point where a bright sleeve reads as a grey one — the
/// aim is to bring a white cover down to roughly where a dark cover already
/// sits, not to make every cover look the same.
const double _kMaxDim = 0.38;

/// How far up the cover is nudged, as a fraction of the screen's height.
///
/// `BoxFit.cover` centres its crop, and the lower third of that crop sits
/// under the scrim where nobody can see it. Raising the cover spends the
/// visible area on the middle of the sleeve instead.
///
/// Bounded by the bottom scrim: a square cover scaled to cover a tall screen
/// has no vertical overflow left to slide, so this exposes a strip at the
/// bottom. That strip is [background] under the solid first stop of the bottom
/// gradient — invisible only while the lift stays well inside it. Past roughly
/// 0.1 it shows as a band of flat colour.
const double _kArtLift = 0.045;

class ImmersiveBackdrop extends StatelessWidget {
  const ImmersiveBackdrop({
    super.key,
    required this.id,
    required this.imageUrl,
    required this.background,
    required this.tint,
    required this.artBrightness,
  });

  /// Track id, so the painted placeholder is stable while the image loads.
  final String id;
  final String? imageUrl;

  /// The screen's own background, which the bottom scrim resolves to.
  final Color background;

  /// Palette colour for this track, used to warm the scrim rather than fading
  /// to flat black.
  final Color tint;

  /// How bright the cover is overall, 0 to 1, from `ArtPalette.brightness`.
  ///
  /// Null while the palette is still resolving, which is treated as "do not
  /// dim": a wash that appears a beat after the artwork is worse than one that
  /// never arrives.
  final double? artBrightness;

  /// Wash alpha for this cover: nothing below [_kDimFrom], ramping to
  /// [_kMaxDim] by [_kDimTo].
  double get _dim {
    final b = artBrightness;
    if (b == null || b <= _kDimFrom) return 0;
    final t = ((b - _kDimFrom) / (_kDimTo - _kDimFrom)).clamp(0.0, 1.0);
    return _kMaxDim * t;
  }

  @override
  Widget build(BuildContext context) {
    // The whole backdrop rasterises once and is then just moved: the player
    // drag translates this subtree every frame, and without the boundary the
    // artwork and both gradients repaint on each one.
    return RepaintBoundary(
      // Explicit, because `Stack` will not do it. It defaults to
      // `Clip.hardEdge`, but `RenderStack` only applies that when
      // `_hasVisualOverflow` is set, and that flag is computed during *layout*
      // from positioned children whose rects fall outside — a child that lays
      // out full-size and merely paints itself offset never sets it. A lift on
      // the artwork once did exactly that, and drew above both scrims: nothing
      // showed at rest, because the band sat off the top of the screen, and a
      // hard unscrimmed seam appeared the moment the player was dragged down.
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Something for the artwork to land on before it decodes, and behind
            // its corners. Not a blurred copy of the cover — see the header.
            ColoredBox(color: background),
            // Lifted so the crop favours the middle of the sleeve — see
            // [_kArtLift]. This is the paint-time translation the ClipRect
            // above exists for.
            FractionalTranslation(
              translation: const Offset(0, -_kArtLift),
              child: SunohArt(
                id: id,
                imageUrl: imageUrl,
                width: double.infinity,
                height: double.infinity,
                radius: 0,
                shadow: false,
              ),
            ),
            // A flat wash over the whole cover, and only over a bright one.
            //
            // The two scrims below are positional — they darken where text sits.
            // Neither helps with the middle of a white sleeve, which carries no
            // text and was still throwing enough light to make the header hard
            // to read and the screen tiring. This is the one layer that treats
            // the artwork as a light source rather than as a backdrop for
            // something.
            //
            // Zero for a dark cover, so the case that already looked right pays
            // nothing — not even a composited transparent layer.
            if (_dim > 0)
              IgnorePointer(
                child: ColoredBox(color: background.withValues(alpha: _dim)),
              ),
            // Both scrims ignore pointers: everything interactive lives above
            // them, and a full-screen DecoratedBox would otherwise eat taps meant
            // for the transport.
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      // Every stop is the same hue at a different alpha. Mixing in
                      // `Colors.transparent` would fade through *black* and muddy
                      // the artwork — the same trap the old radial wash documented.
                      background.withValues(alpha: 0.78),
                      background.withValues(alpha: 0.58),
                      background.withValues(alpha: 0.20),
                      background.withValues(alpha: 0),
                    ],
                    // Sized to the header rather than picked by eye. The status
                    // bar, the chevron, the "PLAYING FROM" eyebrow and the
                    // source title occupy roughly the top 9% of the screen, so
                    // the scrim holds most of its weight to 0.07 and still has
                    // ~0.48 at 0.09 — enough to read white text off the bright
                    // part of a poster. It is then done by 0.26, because past
                    // the header there is nothing to make legible, and darkness
                    // spent below it is the haze this gradient pair was just
                    // corrected for.
                    stops: const [0, 0.07, 0.15, 0.26],
                  ),
                ),
              ),
            ),
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      background,
                      background.withValues(alpha: 0.94),
                      // A breath of the track's own colour where the fade lifts
                      // off the artwork, so the two meet in the same family
                      // instead of the scrim reading as a grey sheet laid on top.
                      Color.lerp(
                        background,
                        tint,
                        0.12,
                      )!.withValues(alpha: 0.50),
                      background.withValues(alpha: 0),
                    ],
                    // Reads bottom-up, and 0.42 is not a round number by
                    // accident: the track title's top edge measures 0.41 of the
                    // screen height up from the bottom on both test devices
                    // (2.20 and 2.22 aspect). Holding near-solid to just past
                    // that puts the whole title block on flat colour instead of
                    // halfway down a ramp, which is where it sat before and why
                    // it read as floating on the artwork.
                    //
                    // The tail still has to end well short of the header — see
                    // the note above about haze — so it is spent faster rather
                    // than reaching further.
                    stops: const [0, 0.42, 0.58, 0.76],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
