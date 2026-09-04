// The scrolling lyric list, and the states it shows instead when there are
// none. Split out of `lyrics_screen.dart` when word-level sync arrived — that
// file is the sheet's chrome, this is what the sheet is for.

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api/lyrics/lyrics_source.dart';
import '../data/lyric_line.dart';
import '../theme/tokens.dart';
import '../widgets/swept_lyric_line.dart';
import 'lyrics_parts.dart';

/// Rough row height, used only to aim a jump at a line that isn't built yet.
///
/// It is a poor estimate and always was: lines wrap to two rows, the playing
/// one is drawn larger than the rest, and instrumental gaps are shorter than
/// either. Scrolling by `index * this` therefore drifts further out with every
/// line, which is what walked the playing line off the bottom of the screen.
/// The real scroll measures the line instead — see [_LyricsBodyState._centre].
const double kLyricRowHeight = 52;

/// Where the playing line sits in the viewport: a third of the way down.
///
/// Not the middle. Lyrics are read forward, so the words that have not been
/// sung yet are the ones worth the space — centring the voice spends half the
/// screen on lines already behind it.
const double _kActiveAlignment = 0.3;

/// How the handover moves, and for how long.
///
/// Deliberately without overshoot, which is what the first pass had. An
/// overshooting curve is fine on a position and wrong on a *type size*: the
/// line grew past the size it was going to settle at, and because size is
/// layout, every row underneath it bounced out and back. Two overshoots were
/// running at once — this one and the scroll's — and together they read as the
/// whole screen jumping at every line.
const Duration _kSpringIn = Duration(milliseconds: 480);
const Curve _kSpringCurve = Curves.easeOutCubic;

/// The list settles on the same curve over the same time, so the scroll and
/// the line that caused it finish together instead of one arriving under the
/// other.
const Curve _kScrollCurve = Curves.easeOutCubic;

/// How visible a line is, by how far it sits from the one playing.
///
/// A funnel rather than the two states this had before (playing, and
/// everything else): the further a line is from the voice the further back it
/// falls, so the eye is pulled to the middle without anything having to move.
///
/// Sung lines recede harder than upcoming ones at the same distance. They have
/// been read already, and dropping them faster leans the whole screen forward
/// into the words about to be sung.
double _lineAlpha(int distance, {required bool past}) {
  if (distance == 0) return 1;
  const ahead = [0.55, 0.42, 0.32, 0.24];
  const behind = [0.34, 0.24, 0.18, 0.14];
  final scale = past ? behind : ahead;
  return scale[(distance - 1).clamp(0, scale.length - 1)];
}

/// Type size: one step, and a small one.
///
/// Size is the only thing here that is *layout* — change it and every row
/// below moves. There used to be three sizes (28, 21.5, 19.5), so a single
/// line change resized four rows at once: the one taking over, the one
/// handing off, and the two crossing the near/far boundary. All of that
/// motion arrived on top of the scroll that was already running.
///
/// Two sizes four points apart resize exactly two rows, and the depth that
/// third size was buying is carried by opacity and blur instead — neither of
/// which moves anything.
double _lineSize(int distance) => distance == 0 ? 26 : 22;

/// How far out of focus a line is, by that same distance.
///
/// The depth is what makes a lyric screen read as one line being sung rather
/// than a list with one row highlighted: the words either side are legibly
/// *there* and plainly not the point. Opacity alone cannot say that — a dim
/// line is still a sharp line, and the eye keeps landing on it.
///
/// Blur is expensive and this app has been burned by it before, so the shape
/// of the cost matters. This is [ImageFiltered], which blurs one line's own
/// layer, not [BackdropFilter], which samples everything painted behind it and
/// is banned over scrolling content. Each blurred line sits behind a
/// [RepaintBoundary], so its raster survives scrolling and is only redone when
/// the line's own distance changes — a few times a song, not sixty times a
/// second.
///
/// Kept gentle. The first pass ran to 4.4 at the far end and the screen read
/// as smeared rather than deep — the words either side stopped being words.
/// The opacity funnel is already doing most of the separating; this only has
/// to add the softness that opacity cannot, so the line next to the one being
/// sung stays almost readable and only the far edges really go.
/// Nothing within one line of the voice is blurred, which is not only for
/// looks: a blurred line cannot animate its size without re-running the blur
/// every frame, and the lines either side of the handover are exactly the
/// ones that need to animate. Sharp near, soft far, and the two never overlap.
double _lineBlur(int distance) => switch (distance) {
  0 || 1 => 0,
  2 => 0.7,
  3 => 1.2,
  _ => 1.7,
};

class LyricsBody extends StatefulWidget {
  const LyricsBody({
    super.key,
    required this.colors,
    required this.lines,
    required this.synced,
    required this.controller,
    required this.clock,
    required this.onSeek,
    this.source,
  });

  final SunohColors colors;
  final List<LyricLine> lines;

  /// False for lyrics we spread over the duration ourselves. Nothing is
  /// highlighted in that case — pretending to know the beat is worse than
  /// plain text.
  final bool synced;
  final ScrollController controller;

  /// Playback position in milliseconds; see `lib/audio/lyrics_clock.dart`.
  final ValueListenable<int> clock;

  /// Jump playback to a line's own stamp. Tapping a lyric is the fastest way
  /// back to a part of a song there is — faster than finding it on a scrubber
  /// that shows no words at all.
  final void Function(int timeMs) onSeek;

  /// Named under the last line, so a bad match has something to blame.
  final LyricsSource? source;

  @override
  State<LyricsBody> createState() => _LyricsBodyState();
}

class _LyricsBodyState extends State<LyricsBody> {
  /// Which line is playing. Derived from the clock, but changing only when the
  /// line does — a few dozen times a song rather than sixty times a second.
  ///
  /// The list is rebuilt off *this*, never off the clock. The clock now ticks
  /// every frame so the sweep can follow a syllable, and a list rebuilt at
  /// that rate would cost the whole frame budget to redraw text that has not
  /// changed. The one widget that genuinely changes every frame is the swept
  /// line, and it repaints itself straight off the clock without rebuilding.
  final ValueNotifier<int> _active = ValueNotifier<int>(-1);

  @override
  void initState() {
    super.initState();
    widget.clock.addListener(_onTick);
    _onTick();
  }

  @override
  void didUpdateWidget(LyricsBody old) {
    super.didUpdateWidget(old);
    if (old.clock != widget.clock) {
      old.clock.removeListener(_onTick);
      widget.clock.addListener(_onTick);
    }
    if (old.lines != widget.lines) _onTick();
  }

  @override
  void dispose() {
    widget.clock.removeListener(_onTick);
    _active.dispose();
    super.dispose();
  }

  /// One key per row, so the playing line can be found on screen and scrolled
  /// to by its actual position rather than by a guess at how tall the rows
  /// above it are.
  final Map<int, GlobalKey> _rowKeys = <int, GlobalKey>{};

  GlobalKey _keyFor(int index) => _rowKeys.putIfAbsent(index, GlobalKey.new);

  void _onTick() {
    if (!widget.synced) return;
    final idx = _activeIndex(widget.lines, widget.clock.value);
    if (idx == _active.value) return;
    _active.value = idx;
    _centre(idx);
  }

  /// Puts line [idx] in the middle of the viewport.
  ///
  /// Run after the frame, because the line only has a size once the list has
  /// rebuilt around the new index — and its size is the whole point: a wrapped
  /// line is twice the height of a plain one, and the gaps are shorter than
  /// both, so no arithmetic over indices can place it.
  void _centre(int idx) {
    if (idx < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      const duration = _kSpringIn;
      const curve = _kScrollCurve;

      final context = _rowKeys[idx]?.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          alignment: _kActiveAlignment,
          duration: duration,
          curve: curve,
        );
        return;
      }

      // Not built, so it is far enough away that the list never laid it out —
      // a seek, or the sheet opening mid-song. Nothing on screen can be
      // measured, so aim with the estimate and let the next line correct it.
      final position = widget.controller.hasClients
          ? widget.controller.position
          : null;
      if (position == null) return;
      final target = (idx * kLyricRowHeight - position.viewportDimension / 2)
          .clamp(0.0, position.maxScrollExtent);
      widget.controller.animateTo(target, duration: duration, curve: curve);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final lines = widget.lines;
    final source = widget.source;

    return ValueListenableBuilder<int>(
      valueListenable: _active,
      builder: (context, idx, _) => ListView.builder(
        controller: widget.controller,
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 80),
        // One past the lines for the credit at the end.
        itemCount: lines.length + (source == null ? 0 : 1),
        itemBuilder: (context, i) {
          if (i == lines.length) return LyricCredit(colors: c, source: source!);

          final line = lines[i];
          final key = _keyFor(i);
          final active = i == idx;
          final past = i < idx;
          final distance = (i - idx).abs();

          // An instrumental stretch. Marked rather than left blank, and while
          // it is the current one it counts itself down — otherwise a long
          // interlude is indistinguishable from lyrics that have stopped
          // tracking.
          if (line.text.trim().isEmpty) {
            return LyricInterlude(
              key: key,
              colors: c,
              clock: widget.clock,
              startMs: line.timeMs,
              endMs: i + 1 < lines.length ? lines[i + 1].timeMs : null,
              active: active,
            );
          }

          final style =
              SunohType.heading(
                fontSize: _lineSize(distance),
                height: 1.3,
                letterSpacing: -0.3,
              ).copyWith(
                color: c.fg.withValues(alpha: _lineAlpha(distance, past: past)),
              );

          // The line itself: swept when it is the one being sung and its
          // source gave word timings, plain text otherwise. Both sit inside
          // the same style wrapper below, so swapping between them changes
          // what is painted and not how big it is.
          final child = active && line.isWordSynced
              ? SweptLyricLine(line: line, clock: widget.clock)
              : LyricLineText(line: line);

          final blur = _lineBlur(distance);
          if (blur == 0) {
            // Near the voice: the size and colour animate, because this is
            // the transition anyone actually watches. One widget across the
            // whole handover — it is not rebuilt when the line takes over,
            // only re-parented — so it animates *through* the swap in both
            // directions instead of the outgoing line snapping back.
            return LyricRowTap(
              key: key,
              onTap: () => widget.onSeek(line.timeMs),
              child: AnimatedDefaultTextStyle(
                duration: _kSpringIn,
                curve: _kSpringCurve,
                style: style,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: child,
                ),
              ),
            );
          }

          // Far from the voice: blurred, and deliberately *not* animated.
          // An ImageFiltered wrapping an animating subtree re-runs the blur
          // on every frame of that animation, for every line at once — which
          // is the spike that made a line change feel like a stutter. Static,
          // it rasterises once behind the RepaintBoundary and is reused until
          // this line's own blur step changes.
          return LyricRowTap(
            key: key,
            onTap: () => widget.onSeek(line.timeMs),
            child: RepaintBoundary(
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(
                  sigmaX: blur,
                  sigmaY: blur,
                  // Without this the blur samples transparent black outside
                  // the line's own bounds and the words come out rimmed in
                  // shadow instead of softening into the page.
                  tileMode: TileMode.decal,
                ),
                child: DefaultTextStyle(
                  style: style,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: child,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static int _activeIndex(List<LyricLine> lines, int positionMs) {
    var idx = -1;
    for (var k = 0; k < lines.length; k++) {
      if (lines[k].timeMs <= positionMs) {
        idx = k;
      } else {
        break;
      }
    }
    return idx;
  }
}
