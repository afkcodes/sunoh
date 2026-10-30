// The artist page's hero — the photo with the name set over it — and the
// Follow pill under it.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api/dto.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/motion.dart';
import '../widgets/ui.dart';

/// 360 of photo running up under the status bar, drifting slower than the
/// page, with the name set large at its foot.
class ArtistHero extends StatelessWidget {
  const ArtistHero({
    super.key,
    required this.colors,
    required this.artist,
    required this.scroll,
    this.imageUrl,
    this.stats,
  });

  final SunohColors colors;
  final FeedItem artist;
  final ValueListenable<double> scroll;
  final String? imageUrl;
  final String? stats;

  static const double _height = 360;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final light = Theme.of(context).brightness == Brightness.light;
    final name = artist.title;
    // Long names step down rather than wrap into three lines.
    final size = name.length > 22
        ? 34.0
        : name.length > 14
        ? 40.0
        : 46.0;
    final line = stats ?? '';
    Color scrim(double a) => SunohMedia.scrim.withValues(alpha: a);
    return SizedBox(
      height: _height,
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: _height * 1.1,
            child: ValueListenableBuilder<double>(
              valueListenable: scroll,
              child: SunohArt(
                id: artist.id,
                imageUrl: imageUrl,
                width: double.infinity,
                height: _height * 1.1,
                radius: 0,
                shadow: false,
              ),
              builder: (context, o, child) =>
                  Transform.translate(offset: Offset(0, o * 0.4), child: child),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  // The name is media ink, so the photo stays scrimmed under
                  // it. On the dark ground the foot fades into the page; on
                  // the light one that fade would put light ink on a light
                  // band, so the scrim holds until the last few pixels.
                  colors: light
                      ? [
                          scrim(0.7),
                          scrim(0.35),
                          scrim(0),
                          scrim(0.1),
                          scrim(0.7),
                          scrim(0.82),
                          c.bg,
                        ]
                      : [
                          scrim(0.7),
                          scrim(0.35),
                          scrim(0),
                          scrim(0.1),
                          scrim(0.7),
                          c.bg,
                        ],
                  stops: light
                      ? const [0, 0.2, 0.38, 0.5, 0.8, 0.96, 1]
                      : const [0, 0.2, 0.38, 0.5, 0.8, 1],
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FadeSlideIn(
                  child: Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: SunohType.heading(
                      fontSize: size,
                      color: SunohMedia.ink,
                      height: 1.0,
                      letterSpacing: -1.8 * size / 46,
                    ),
                  ),
                ),
                if (line.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  FadeSlideIn(
                    index: 1,
                    child: Text(
                      line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SunohType.sans(
                        fontSize: 13.5,
                        color: SunohMedia.inkDim,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Follow is the one outlined pill in the app: a hairline ring while not
/// following, the ink fill once you are.
class FollowPill extends StatelessWidget {
  const FollowPill({
    super.key,
    required this.colors,
    required this.following,
    required this.onTap,
  });
  final SunohColors colors;
  final bool following;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: SunohMotion.ease,
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: squircleDecoration(
          radius: 17,
          color: following ? c.fg : c.fg.withValues(alpha: 0),
          borderColor: following ? null : c.fgMute,
          borderWidth: 1,
        ),
        child: Text(
          following ? 'Following' : 'Follow',
          style: SunohType.sans(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: following ? c.bg : c.fg,
          ),
        ),
      ),
    );
  }
}
