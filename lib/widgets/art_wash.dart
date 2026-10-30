// A soft band of colour at the top of a page, taken from artwork.
//
// The reskin's one atmospheric move outside the player: the top of Home
// carries the colour of whatever is playing, and a detail page carries the
// colour of its own cover. It fades to nothing well before the content gets
// dense, so text never sits on a tinted ground it was not checked against.
//
// One gradient and nothing else — no blur, no image. The colour change is
// tweened rather than snapped, so skipping a track reads as the room changing
// light rather than as a flash.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_state_provider.dart';
import '../providers/palette_provider.dart';
import '../theme/tokens.dart';

class ArtWash extends StatelessWidget {
  const ArtWash({
    super.key,
    required this.color,
    required this.isLight,
    this.height = 360,
  });

  final Color color;
  final bool isLight;
  final double height;

  @override
  Widget build(BuildContext context) {
    // Half the strength on light: the same alpha over a pale page reads as a
    // stain rather than a glow.
    final strength = isLight ? 0.12 : 0.24;
    return IgnorePointer(
      child: SizedBox(
        height: height,
        child: TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: color),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOut,
          builder: (_, tone, _) {
            final t = tone ?? color;
            return DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0, 0.45, 1],
                  colors: [
                    t.withValues(alpha: strength),
                    t.withValues(alpha: strength * 0.35),
                    t.withValues(alpha: 0),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// [ArtWash] in the colour of the track that is playing.
///
/// Selects only the three things the colour depends on, so the 1 Hz position
/// tick and every unrelated AppState change pass it by. A record compares by
/// value, which is what makes the select skip identical results.
class PlayingArtWash extends ConsumerWidget {
  const PlayingArtWash({super.key, this.height = 360});
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (url, isLight, fallback) = ref.watch(
      appStateProvider.select(
        (s) => (s.currentApiSong?.artwork ?? '', s.isLight, s.resolvedAccent),
      ),
    );
    final palette = url.isEmpty
        ? null
        : ref.watch(artPaletteProvider(url)).value;
    final raw = palette?.accent ?? fallback;
    return ArtWash(
      color: isLight ? lightAccentFor(raw) : raw,
      isLight: isLight,
      height: height,
    );
  }
}
