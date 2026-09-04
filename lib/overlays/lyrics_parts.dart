// The pieces the lyric list draws: a row's tap target, an instrumental
// marker, the answering vocal under a line, the source credit, and the states
// shown when there are no lyrics at all.
//
// Split out of `lyrics_body.dart` so that file is the list and its timing, and
// this one is what the list puts on screen.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api/lyrics/lyrics_source.dart';
import '../data/lyric_line.dart';
import '../theme/tokens.dart';

/// A whole-row tap target.
///
/// Opaque hit testing so the gaps between words are part of the target too —
/// this is a line of a song being aimed at with a thumb, not a link.
class LyricRowTap extends StatelessWidget {
  const LyricRowTap({super.key, required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: child,
  );
}

/// An instrumental stretch, drawn as three dots that fill across it.
///
/// The parsers mark these where a source said when its singing stopped, so
/// the run really is silence rather than a slowly sung line. While the
/// interlude is the current one the dots fill in turn, which is the only
/// thing on screen saying the app is still following the song — before this
/// a long break looked exactly like lyrics that had lost the plot.
class LyricInterlude extends StatelessWidget {
  const LyricInterlude({
    super.key,
    required this.colors,
    required this.clock,
    required this.startMs,
    required this.endMs,
    required this.active,
  });

  final SunohColors colors;
  final ValueListenable<int> clock;
  final int startMs;

  /// When the singing starts again. Null for a break with nothing after it,
  /// which cannot be counted down and is simply drawn at rest.
  final int? endMs;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final end = endMs;
    // At rest: three dim dots, no painter and nothing listening.
    if (!active || end == null || end <= startMs) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: _InterludeDots(
          color: colors.fg.withValues(alpha: 0.18),
          filled: 0,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: ValueListenableBuilder<int>(
        valueListenable: clock,
        builder: (context, positionMs, _) {
          final through = ((positionMs - startMs) / (end - startMs)).clamp(
            0.0,
            1.0,
          );
          return _InterludeDots(
            color: colors.fg.withValues(alpha: 0.6),
            // Rebuilt per frame but only three circles wide, and only while an
            // interlude is actually playing — which is a few seconds a song.
            filled: (through * 3).floor().clamp(0, 3),
          );
        },
      ),
    );
  }
}

class _InterludeDots extends StatelessWidget {
  const _InterludeDots({required this.color, required this.filled});

  final Color color;
  final int filled;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < 3; i++) ...[
        if (i > 0) const SizedBox(width: 7),
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: i < filled ? color : color.withValues(alpha: color.a * 0.28),
          ),
        ),
      ],
    ],
  );
}

/// A line, plus its answering vocal hung underneath where there is one.
class LyricLineText extends StatelessWidget {
  const LyricLineText({super.key, required this.line});
  final LyricLine line;

  @override
  Widget build(BuildContext context) {
    final backing = line.background;
    if (backing == null) return Text(line.text);

    final style = DefaultTextStyle.of(context).style;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(line.text),
        const SizedBox(height: 4),
        Text(
          backing.text,
          style: style.copyWith(
            fontSize: (style.fontSize ?? 22) * 0.72,
            color: style.color?.withValues(alpha: (style.color?.a ?? 1) * 0.75),
          ),
        ),
      ],
    );
  }
}

class LyricCredit extends StatelessWidget {
  const LyricCredit({super.key, required this.colors, required this.source});
  final SunohColors colors;
  final LyricsSource source;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 28),
    child: Text(
      'Lyrics from ${source.label}',
      style: SunohType.sans(fontSize: 11.5, color: colors.fgMute),
    ),
  );
}

class LyricsHint extends StatelessWidget {
  const LyricsHint({
    super.key,
    required this.colors,
    required this.label,
    this.detail,
  });
  final SunohColors colors;
  final String label;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 60, 28, 60),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: SunohType.heading(fontSize: 22, color: c.fgDim)),
            if (detail != null) ...[
              const SizedBox(height: 10),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: SunohType.sans(fontSize: 13, color: c.fgMute),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
