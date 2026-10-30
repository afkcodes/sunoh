// The expanded player's scrubber: the track's real waveform as a row of
// bars, the played part in ink and the rest dimmed, with the times
// underneath.
//
// The shape comes from the engine (`AudioRepo.waveform`, see
// audio/waveform_peaks.dart): mpv decodes the file on a worker thread and
// reports a ~2000-bin loudness envelope, which is folded here into one bar
// per slice. A stream still downloading arrives in growing snapshots; the
// part not yet analysed stays on the floor.
// Until the analysis lands — on every track change, and for an HLS stream
// wherever it has not played yet — the bars sit as a flat line and then grow into the
// song's shape. Nothing is invented: a track that cannot be analysed (a cast
// session, say) keeps the flat line and still seeks.
//
// PERF: one CustomPainter, repainted by the 1 Hz position tick through a
// ValueListenableBuilder. Bars are folded once per envelope, in the feed's
// listener, never in build or paint. The analyser itself runs for the whole
// session (audio/waveform_peaks.dart), so the shape is ready when the player
// opens rather than starting from there.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../audio/waveform_peaks.dart' show TrackWaveform;
import '../theme/tokens.dart';

const int _kBars = 57;
const double _kHeight = 34;

/// Height of a bar with nothing to show yet, and the floor under every bar so
/// silence still reads as part of the track.
const double _kFloor = 0.12;

class WaveformScrubber extends StatefulWidget {
  const WaveformScrubber({
    super.key,
    required this.trackId,
    required this.waveform,
    required this.position,
    required this.duration,
    required this.onSeek,
    required this.colors,
  });

  /// The song on screen: a waveform is drawn only when it belongs to it.
  final String trackId;

  /// The engine's waveform for the loaded track, or null when there is no
  /// engine (the demo catalogue).
  final ValueListenable<TrackWaveform?>? waveform;
  final ValueNotifier<int> position;
  final int duration;
  final ValueChanged<int> onSeek;
  final SunohColors colors;

  @override
  State<WaveformScrubber> createState() => _WaveformScrubberState();
}

class _WaveformScrubberState extends State<WaveformScrubber>
    with SingleTickerProviderStateMixin {
  Float32List? _shown;
  List<double> _from = List.filled(_kBars, _kFloor);
  List<double> _to = List.filled(_kBars, _kFloor);
  late List<double> _bars = _to;

  // The grow from one shape to the next.
  late final AnimationController _grow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  )..addListener(_step);

  @override
  void initState() {
    super.initState();
    widget.waveform?.addListener(_sync);
    // Drawn as it is, not grown in: the player's entrance already brings the
    // scrubber in, and growing it from a flat line on every open read as a
    // flicker under that fade.
    _sync(animate: false);
  }

  @override
  void didUpdateWidget(WaveformScrubber old) {
    super.didUpdateWidget(old);
    if (old.waveform != widget.waveform) {
      old.waveform?.removeListener(_sync);
      widget.waveform?.addListener(_sync);
    }
    _sync();
  }

  @override
  void dispose() {
    widget.waveform?.removeListener(_sync);
    _grow.dispose();
    super.dispose();
  }

  /// Draws the feed's waveform when it is this song's, else the flat line
  /// until it is.
  void _sync({bool animate = true}) {
    final w = widget.waveform?.value;
    _show(
      w != null && w.songId == widget.trackId ? w.peaks : null,
      animate: animate,
    );
  }

  void _show(Float32List? peaks, {bool animate = true}) {
    if (identical(peaks, _shown)) return;
    _shown = peaks;
    _from = _bars;
    _to = peaks == null ? List.filled(_kBars, _kFloor) : _fold(peaks);
    if (!animate) {
      _bars = _to;
      return;
    }
    // The first shape grows in; later snapshots of a stream still being
    // analysed only refine it, so they settle quickly.
    final first = _from.every((v) => v == _kFloor);
    _grow.duration = Duration(milliseconds: first ? 600 : 240);
    _grow.forward(from: 0);
  }

  void _step() {
    final t = SunohMotion.arrive.transform(_grow.value);
    setState(() {
      _bars = List.generate(_kBars, (i) => lerpDouble(_from[i], _to[i], t)!);
    });
  }

  /// One bar per slice of the envelope: the slice's average loudness,
  /// stretched between the track's quietest and loudest slices.
  ///
  /// Stretched rather than scaled to the top so the intro, the drop and the
  /// outro read where the eye expects even on a loud master. A slice the
  /// analyser has not reached (NaN bins only) sits on the floor until it is.
  static List<double> _fold(Float32List peaks) {
    final per = peaks.length / _kBars;
    final raw = List.generate(_kBars, (i) {
      final from = (i * per).floor();
      final to = math.min(
        peaks.length,
        math.max(from + 1, ((i + 1) * per).floor()),
      );
      var sum = 0.0;
      var n = 0;
      for (var j = from; j < to; j++) {
        final v = peaks[j];
        if (v.isNaN) continue;
        sum += v;
        n++;
      }
      return n == 0 ? double.nan : sum / n;
    });
    final known = raw.where((v) => !v.isNaN);
    if (known.isEmpty) return List.filled(_kBars, _kFloor);
    final lo = known.reduce(math.min);
    final hi = known.reduce(math.max);
    if (hi <= 0 || hi - lo < 1e-4) {
      return [for (final v in raw) v.isNaN ? _kFloor : 0.6];
    }
    return [
      for (final v in raw)
        v.isNaN ? _kFloor : _kFloor + (1 - _kFloor) * ((v - lo) / (hi - lo)),
    ];
  }

  void _seekTo(Offset local, double width) {
    if (widget.duration <= 0) return;
    final f = (local.dx / width).clamp(0.0, 1.0);
    widget.onSeek((f * widget.duration).round());
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final timeStyle = SunohType.mono(fontSize: 12, color: c.fgDim);
    return LayoutBuilder(
      builder: (context, box) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => _seekTo(d.localPosition, box.maxWidth),
        onHorizontalDragUpdate: (d) => _seekTo(d.localPosition, box.maxWidth),
        child: ValueListenableBuilder<int>(
          valueListenable: widget.position,
          builder: (_, pos, _) {
            final dur = widget.duration;
            final frac = dur <= 0 ? 0.0 : (pos / dur).clamp(0.0, 1.0);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: _kHeight,
                  child: CustomPaint(
                    painter: _WavePainter(
                      bars: _bars,
                      progress: frac,
                      played: c.fg,
                      rest: c.fg.withValues(alpha: 0.25),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_fmt(pos), style: timeStyle),
                    Text(
                      '-${_fmt((dur - pos).clamp(0, dur))}',
                      style: timeStyle,
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  static String _fmt(int s) =>
      '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

class _WavePainter extends CustomPainter {
  _WavePainter({
    required this.bars,
    required this.progress,
    required this.played,
    required this.rest,
  });

  final List<double> bars;
  final double progress;
  final Color played;
  final Color rest;

  @override
  void paint(Canvas canvas, Size size) {
    final pitch = size.width / bars.length;
    final w = pitch * 0.57;
    final cut = progress * bars.length;
    final on = Paint()..color = played;
    final off = Paint()..color = rest;
    for (var i = 0; i < bars.length; i++) {
      final h = bars[i] * size.height;
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(i * pitch, (size.height - h) / 2, w, h),
        Radius.circular(w / 2),
      );
      canvas.drawRRect(r, i < cut ? on : off);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.progress != progress ||
      !identical(old.bars, bars) ||
      old.played != played ||
      old.rest != rest;
}
