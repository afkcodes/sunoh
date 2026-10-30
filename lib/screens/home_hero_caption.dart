// What is printed on a Home hero card: the scrim that darkens its lower
// part, the language pill and the caption with its open/play button.
//
// Split out of home_hero.dart, which keeps the cards' layout and motion; this
// is the layer that sits still on top of the drifting art.

import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:remixicon/remixicon.dart';

import '../api/dto.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';
import 'feed_row.dart';

/// Darkens the lower part of the card, where the caption sits, and leaves the
/// top of the sleeve untouched.
class HeroCardScrim extends StatelessWidget {
  const HeroCardScrim({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          stops: const [0, 0.36, 0.7],
          colors: [
            SunohMedia.scrim.withValues(alpha: 0.92),
            SunohMedia.scrim.withValues(alpha: 0.6),
            SunohMedia.scrim.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}

/// The item's language, when the feed carries one, as a pill top-left.
class HeroCardPill extends StatelessWidget {
  const HeroCardPill({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      alignment: Alignment.center,
      decoration: squircleDecoration(
        radius: 12,
        color: SunohMedia.scrim.withValues(alpha: 0.72),
      ),
      child: Text(
        text,
        style: SunohType.sans(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: SunohMedia.ink,
        ),
      ),
    );
  }
}

/// Type, title and subtitle on the left; on the right a button in the card's
/// colour saying what a tap does — a song plays, anything else opens. The
/// card itself is the target.
class HeroCardCaption extends StatelessWidget {
  const HeroCardCaption({super.key, required this.item, required this.tone});
  final FeedItem item;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final subtitle = item.displaySubtitle ?? '';
    final kind = labelFor(item.type);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (kind.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: eyebrow(
                    kind,
                    Color.lerp(tone, SunohMedia.ink, 0.45)!,
                    size: 10.5,
                    letterSpacing: 0.84,
                    maxLines: 1,
                  ),
                ),
              Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: SunohType.heading(
                  fontSize: 25,
                  color: SunohMedia.ink,
                  height: 1.08,
                ),
              ),
              if (subtitle.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SunohType.sans(
                      fontSize: 13,
                      color: SunohMedia.inkDim,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
          child: Icon(
            item.type == 'song'
                ? PhosphorIconsFill.play
                : RemixIcons.arrow_right_line,
            size: 20,
            color: inkOn(tone),
          ),
        ),
      ],
    );
  }
}
