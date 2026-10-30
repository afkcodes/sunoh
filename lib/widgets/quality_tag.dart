// What the current track's audio actually is, named from mpv's own decoder.
//
// A lossless file (a local or downloaded FLAC, say) gets the hi-res mark; every
// other stream gets a plain format line, because a YouTube track with no line
// at all is indistinguishable from a broken tag. See
// AppState.currentFormatLabel.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_state_provider.dart';
import '../theme/tokens.dart';
import 'ui.dart';

class QualityTag extends ConsumerWidget {
  const QualityTag({super.key, required this.colors, this.compact = false});

  final SunohColors colors;

  /// The mini player's variant: shorter copy and smaller type.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final listenable = s.qualityListenable;
    if (listenable == null) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) {
        final format = compact
            ? s.currentFormatLabelCompact
            : s.currentFormatLabel;
        // Until mpv reports the new track's format, a blank line holds the
        // label's height: collapsing to nothing moved everything under the
        // title on every track change. The text fades in when it lands.
        final Widget tag = format == null
            ? _FormatLine(text: ' ', colors: colors, compact: compact)
            // mpv says the audio is lossless: that earns the badge.
            : s.currentIsLossless
            ? _HiResMark(label: format, colors: colors, compact: compact)
            : _FormatLine(text: format, colors: colors, compact: compact);
        return AnimatedSwitcher(
          duration: SunohMotion.ui,
          switchInCurve: SunohMotion.ease,
          layoutBuilder: (current, previous) => Stack(
            alignment: AlignmentDirectional.centerStart,
            children: [...previous, ?current],
          ),
          // Keyed on which kind of tag, not its text: mpv revises the
          // bitrate as a track plays, and a fade on every revision made the
          // line breathe.
          child: KeyedSubtree(
            key: ValueKey(format == null ? 0 : (s.currentIsLossless ? 2 : 1)),
            child: tag,
          ),
        );
      },
    );
  }
}

/// The plain format line, for streams with no hi-res claim to make.
///
/// No chip and no border — a lossy stream is the ordinary case, and dressing
/// it up would make "AAC" look like an award. Just the facts, in the same
/// monospace the numbers under the hi-res mark use so the two read as one
/// family.
class _FormatLine extends StatelessWidget {
  const _FormatLine({
    required this.text,
    required this.colors,
    required this.compact,
  });

  final String text;
  final SunohColors colors;
  final bool compact;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: SunohType.mono(
      fontSize: compact ? 9 : 10,
      fontWeight: FontWeight.w600,
      color: colors.fgMute,
    ),
  );
}

/// The hi-res badge: a wordmark, with what is actually being decoded set
/// underneath it.
///
/// Drawn rather than shipped as an image. The obvious asset for this is the
/// Japan Audio Society's Hi-Res Audio mark, which is what every hardware
/// vendor uses — but it is a certification mark, and putting it on a stream
/// nobody certified claims something this app is not entitled to claim. A
/// badge of our own says the same thing and only for itself.
///
/// Nothing here is tinted. The accent shifts with the artwork, and a badge
/// stating a fact about the file has no business changing colour because the
/// cover did — it would read as decoration rather than as information. The
/// whole mark is built from the foreground colour instead, which is legible
/// against every background the player puts behind it.
class _HiResMark extends StatelessWidget {
  const _HiResMark({
    required this.label,
    required this.colors,
    required this.compact,
  });

  final String label;
  final SunohColors colors;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final wordmark = DecoratedBox(
      decoration: squircleDecoration(
        radius: compact ? 4 : 5,
        // Brightest along the top edge, so the chip reads as catching light
        // rather than as a flat swatch.
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c.fg.withValues(alpha: 0.20), c.fg.withValues(alpha: 0.05)],
        ),
        borderColor: c.fg.withValues(alpha: 0.32),
        borderWidth: 0.8,
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 4 : 6,
          vertical: compact ? 1.5 : 3,
        ),
        child: Text(
          'HI-RES',
          style: SunohType.mono(
            fontSize: compact ? 7.5 : 9,
            fontWeight: FontWeight.w700,
            color: c.fg,
            // Wide enough that six characters read as a mark rather than as a
            // word someone typed.
            letterSpacing: compact ? 0.9 : 1.3,
          ),
        ),
      ),
    );

    // The mini player's tag rides on the artist's own line, beside it. There
    // is no second line down there, so the numbers sit next to the wordmark in
    // their shortened form rather than under it — `HI-RES 24/96`.
    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          wordmark,
          if (label.isNotEmpty) ...[
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SunohType.mono(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: c.fgMute,
                ),
              ),
            ),
          ],
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        wordmark,
        const SizedBox(height: 5),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: SunohType.mono(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: c.fgDim,
          ),
        ),
      ],
    );
  }
}
