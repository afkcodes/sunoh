// The expanded player's controls, each handed what it draws: the play disc,
// the like button, the shuffle/repeat toggles, the output-device button and
// the lyric teaser.
//
// None of them reads app state; expanded_player.dart wires them. That keeps
// the 1 Hz position tick and the like/toggle rebuilds confined to the small
// widgets that change.

import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:remixicon/remixicon.dart';

import '../theme/tokens.dart';
import '../widgets/motion.dart';

/// The play/pause disc: the page's ink with the glyph cut out of it in the
/// ground colour, so it is the same button on every cover and inverts with
/// the palette on its own. A tap scales it in and swaps the glyph.
class PlayButton extends StatelessWidget {
  const PlayButton({
    super.key,
    required this.playing,
    required this.ink,
    required this.onInk,
    required this.onTap,
  });
  final bool playing;
  final Color ink;
  final Color onInk;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.93,
      child: Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(color: ink, shape: BoxShape.circle),
        child: AnimatedSwitcher(
          duration: SunohMotion.press,
          transitionBuilder: (child, anim) =>
              ScaleTransition(scale: anim, child: child),
          child: Icon(
            playing ? PhosphorIconsFill.pause : PhosphorIconsFill.play,
            key: ValueKey(playing),
            size: 34,
            color: onInk,
          ),
        ),
      ),
    );
  }
}

/// Shuffle or repeat: muted when off, the accent with a small dot under it
/// when on, so the state reads by shape as well as colour.
class PlayerToggle extends StatelessWidget {
  const PlayerToggle({
    super.key,
    required this.icon,
    required this.on,
    required this.colors,
    required this.onTap,
  });
  final IconData icon;
  final bool on;
  final SunohColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final col = on ? colors.accent : colors.fgDim;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox.square(
        dimension: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(icon, size: 22, color: col),
            Positioned(
              bottom: 6,
              child: AnimatedScale(
                scale: on ? 1 : 0,
                duration: SunohMotion.ui,
                curve: SunohMotion.arrive,
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(color: col, shape: BoxShape.circle),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Like, with a small burst of the accent when it is switched on.
class LikeButton extends StatefulWidget {
  const LikeButton({
    super.key,
    required this.liked,
    required this.colors,
    required this.onTap,
  });
  final bool liked;
  final SunohColors colors;
  final VoidCallback onTap;

  @override
  State<LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends State<LikeButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  // .6 → 1.25 → 1: the heart pops past its size and settles.
  static final _pop = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.6, end: 1.25), weight: 45),
    TweenSequenceItem(tween: Tween(begin: 1.25, end: 1), weight: 55),
  ]);

  @override
  void didUpdateWidget(LikeButton old) {
    super.didUpdateWidget(old);
    if (widget.liked && !old.liked) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox.square(
        dimension: 44,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => CustomPaint(
            painter: _c.isAnimating ? _Burst(_c.value, c.accent) : null,
            child: Transform.scale(
              scale: _c.isAnimating ? _pop.transform(_c.value) : 1,
              child: Icon(
                widget.liked ? RemixIcons.heart_3_fill : RemixIcons.heart_3_line,
                size: 26,
                color: widget.liked ? c.accent : c.fg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Eight dots flung out from the centre, fading as they go.
class _Burst extends CustomPainter {
  _Burst(this.t, this.color);
  final double t;
  final Color color;

  static const _dirs = [
    Offset(1, 0),
    Offset(.707, .707),
    Offset(0, 1),
    Offset(-.707, .707),
    Offset(-1, 0),
    Offset(-.707, -.707),
    Offset(0, -1),
    Offset(.707, -.707),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final e = Curves.easeOutCubic.transform(t);
    final paint = Paint()..color = color.withValues(alpha: 1 - t);
    final centre = size.center(Offset.zero);
    for (final d in _dirs) {
      canvas.drawCircle(centre + d * (8 + 18 * e), 2.6 * (1 - 0.6 * e), paint);
    }
  }

  @override
  bool shouldRepaint(_Burst old) => old.t != t || old.color != color;
}

/// Where the sound is going: "This phone", or the cast device's name. Opens
/// the device picker.
class DeviceButton extends StatelessWidget {
  const DeviceButton({
    super.key,
    required this.label,
    required this.casting,
    required this.colors,
    required this.onTap,
  });
  final String label;
  final bool casting;
  final SunohColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 40,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              casting
                  ? RemixIcons.cast_fill
                  : RemixIcons.cast_line,
              size: 18,
              color: colors.accent,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: SunohType.sans(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: colors.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One-line teaser pulled from the synced lyric matching the current position.
class LyricsTeaser extends StatelessWidget {
  const LyricsTeaser({
    super.key,
    required this.line,
    required this.accent,
    required this.onTap,
  });
  final String line;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Text(
        line,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: SunohType.sans(
          fontSize: 13,
          color: accent,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
