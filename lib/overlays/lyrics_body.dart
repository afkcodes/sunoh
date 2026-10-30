// The scrolling lyric list, and the states it shows instead when there are
// none. Split out of `lyrics_screen.dart` when word-level sync arrived — that
// file is the page's chrome, this is what the page is for.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api/lyrics/lyrics_source.dart';
import '../data/lyric_line.dart';
import '../theme/tokens.dart';
import '../widgets/swept_lyric_line.dart';
import 'lyrics_parts.dart';

/// Rough row height, used only to aim a jump at a line that isn't built yet.
///
/// It is a poor estimate and always was: lines wrap to two rows and
/// instrumental gaps are shorter than either. Scrolling by `index * this` therefore drifts further out with every
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
/// Deliberately without overshoot, which is what the first pass had: it was
/// running at once with the scroll's, and together they read as the whole
/// screen jumping at every line. The handover is colour only now — nothing
/// about it is layout — but an overshooting colour just flashes.
const Duration _kSpringIn = Duration(milliseconds: 480);
const Curve _kSpringCurve = Curves.easeOutCubic;

/// The list settles on the same curve over the same time, so the scroll and
/// the line that caused it finish together instead of one arriving under the
/// other.
const Curve _kScrollCurve = Curves.easeOutCubic;

/// One size for every line, large: the redesign sets lyrics as headings, the
/// line being sung in ink and every other line in fgMute.
///
/// One size because size is layout. This used to step the playing line up
/// from its neighbours (and once ran three sizes), so every handover resized
/// rows and moved everything under them on top of the scroll already running.
/// A distance funnel of opacities and a blur on far lines carried the depth
/// then; two inks carry it now, which is the prototype's look and costs no
/// filter layers at all.
const double _kLineSize = 26;

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
    final synced = widget.synced;
    // The two inks, made once per line change rather than once per row.
    final lit = SunohType.heading(
      fontSize: _kLineSize,
      height: 1.3,
      color: c.fg,
    );
    final receded = lit.copyWith(color: c.fgMute);
    // Running under the navigation bar now, so the last line and the credit
    // have to clear it as well as the bottom fade.
    final bottom = 80 + MediaQuery.paddingOf(context).bottom;

    return ValueListenableBuilder<int>(
      valueListenable: _active,
      builder: (context, idx, _) => ListView.builder(
        controller: widget.controller,
        padding: EdgeInsets.fromLTRB(24, 20, 24, bottom),
        // One past the lines for the credit at the end.
        itemCount: lines.length + (source == null ? 0 : 1),
        itemBuilder: (context, i) {
          if (i == lines.length) return LyricCredit(colors: c, source: source!);

          final line = lines[i];
          final key = _keyFor(i);
          final active = i == idx;

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

          // The line itself: swept when it is the one being sung and its
          // source gave word timings, plain text otherwise. Both sit inside
          // the same style wrapper below, so swapping between them changes
          // what is painted and not how it is set.
          final child = active && line.isWordSynced
              ? SweptLyricLine(line: line, clock: widget.clock)
              : LyricLineText(line: line);

          // Unsynced lyrics have no line being sung, so they read as plain
          // text in ink rather than as a page of receded lines.
          //
          // The colour animates, because this is the transition anyone
          // actually watches. One widget across the whole handover — it is
          // not rebuilt when the line takes over, only re-parented — so it
          // animates *through* the swap in both directions instead of the
          // outgoing line snapping back.
          return LyricRowTap(
            key: key,
            onTap: () => widget.onSeek(line.timeMs),
            child: AnimatedDefaultTextStyle(
              duration: _kSpringIn,
              curve: _kSpringCurve,
              style: active || !synced ? lit : receded,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: child,
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
