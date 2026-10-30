// The equalizer's rack: ten bands in one box, drawn the way the prototype
// draws them — a zero line, a faint track per band, one smooth accent curve
// through the gains with the area between it and zero washed in, and a small
// rounded handle on each band. Value and frequency labels sit underneath.
//
// Split out of `eq_sheet.dart`, which is about where things go; this is what
// the rack is.
//
// Everything above the labels is painted by one CustomPainter rather than
// built as widgets per band. A curve drawn through ten points is one path
// anyway, and painting the handles with it means a preset morphing from one
// curve to the next repaints a single layer for the length of the morph —
// nothing is rebuilt, and nothing below the rack is touched. The band
// sliders on top are bare hit targets (`eq_slider.dart`).

import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_state_provider.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';
import 'eq_slider.dart';

/// Frequency labels, matching the band centres in `audio/eq_filters.dart`.
const List<String> kEqLabels = [
  '31',
  '63',
  '125',
  '250',
  '500',
  '1k',
  '2k',
  '4k',
  '8k',
  '16k',
];

const double _kMinGain = -12;
const double _kMaxGain = 12;

/// The prototype's rack: a 224 fader field over a 38 label strip.
///
/// Fixed rather than flexible: it is the dimension a listener aims at, and a
/// rack that stretched to fill the screen would make the same drag mean
/// different amounts of gain on different phones.
const double _kFieldHeight = 224;
const double _kLabelsHeight = 38;

/// Signed whole-dB readouts, −12 to +12, built once rather than formatted per
/// band per build. The minus is the typographic one, as in the prototype; a
/// hyphen sits visibly higher and shorter than the plus beside it.
final List<String> _kGainLabels = List.unmodifiable([
  for (var g = -12; g <= 12; g++) g > 0 ? '+$g' : (g < 0 ? '−${-g}' : '0'),
]);

String _gainLabel(double gain) =>
    _kGainLabels[gain.round().clamp(-12, 12) + 12];

class EqRack extends ConsumerStatefulWidget {
  const EqRack({super.key});

  @override
  ConsumerState<EqRack> createState() => _EqRackState();
}

class _EqRackState extends ConsumerState<EqRack>
    with SingleTickerProviderStateMixin {
  /// Runs when a preset is applied, carrying the curve from where it was to
  /// the preset's shape. A drag does not run it: a handle that eased after
  /// the finger would feel like it was being dragged through syrup.
  late final AnimationController _morph = AnimationController(
    vsync: this,
    duration: SunohMotion.screen,
    value: 1,
  );

  late List<double> _from = ref.read(appStateProvider).eqBands;
  late List<double> _to = _from;

  @override
  void dispose() {
    _morph.dispose();
    super.dispose();
  }

  void _retarget(List<double> next) {
    // A preset id is set by applying a preset (or resetting to flat) and
    // cleared by touching a band, which is exactly the line between "show
    // the change" and "follow the finger".
    final animate = ref.read(appStateProvider).currentEqPresetId != null;
    if (!animate) {
      _from = next;
      _to = next;
      _morph.value = 1;
      return;
    }
    // Start from wherever the curve is drawn now, so tapping presets in quick
    // succession bends the line on from mid-flight instead of jumping back.
    final t = SunohMotion.arrive.transform(_morph.value);
    _from = [
      for (var i = 0; i < next.length; i++) lerpDouble(_from[i], _to[i], t)!,
    ];
    _to = next;
    _morph.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<List<double>>(
      appStateProvider.select((s) => s.eqBands),
      (_, next) => _retarget(next),
    );
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final on = s.eqEnabled;

    return Container(
      height: _kFieldHeight + _kLabelsHeight,
      decoration: squircleDecoration(
        radius: SunohRadius.card,
        color: c.surface2,
      ),
      child: Column(
        children: [
          SizedBox(
            height: _kFieldHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Off dims the curve and greys the handles rather than hiding
                // them: the curve is still the listener's, and seeing it is
                // how they decide whether to switch back on.
                RepaintBoundary(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: on ? 1 : 0),
                    duration: SunohMotion.ui,
                    curve: SunohMotion.ease,
                    builder: (_, k, _) => CustomPaint(
                      painter: _RackPainter(
                        from: _from,
                        to: _to,
                        morph: _morph,
                        on: k,
                        accent: c.accent,
                        line: c.line,
                        handle: Color.lerp(c.fgMute, c.fg, k)!,
                        // The rack's own ground, opaque: the ring round a
                        // handle has to hide the curve passing under it, and
                        // surface2 alone is a translucent veil.
                        ground: Color.alphaBlend(c.surface2, c.bgSoft),
                      ),
                    ),
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < kEqLabels.length; i++)
                      Expanded(
                        child: EqBandSlider(
                          gain: s.eqBands[i],
                          min: _kMinGain,
                          max: _kMaxGain,
                          enabled: on,
                          onChanged: (db) => s.setEqBand(i, db),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(
            height: _kLabelsHeight,
            child: Row(
              children: [
                for (var i = 0; i < kEqLabels.length; i++)
                  Expanded(
                    child: _BandLabel(
                      value: _gainLabel(s.eqBands[i]),
                      frequency: kEqLabels[i],
                      colors: c,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BandLabel extends StatelessWidget {
  const _BandLabel({
    required this.value,
    required this.frequency,
    required this.colors,
  });

  final String value;
  final String frequency;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Text(
        value,
        style: SunohType.mono(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: colors.fgDim,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        frequency,
        style: SunohType.sans(fontSize: 10, color: colors.fgMute),
      ),
    ],
  );
}

/// Zero line, band tracks, the curve and its wash, and the handles.
class _RackPainter extends CustomPainter {
  _RackPainter({
    required this.from,
    required this.to,
    required this.morph,
    required this.on,
    required this.accent,
    required this.line,
    required this.handle,
    required this.ground,
  }) : super(repaint: morph);

  final List<double> from;
  final List<double> to;
  final Animation<double> morph;

  /// 1 on, 0 bypassed; in between while the switch animates.
  final double on;
  final Color accent;
  final Color line;
  final Color handle;
  final Color ground;

  @override
  void paint(Canvas canvas, Size size) {
    final n = to.length;
    if (n == 0) return;
    final w = size.width;
    final h = size.height;
    final band = w / n;
    final zeroY = eqGainToY(0, h, _kMinGain, _kMaxGain);
    final rule = Paint()..color = line;

    canvas.drawRect(Rect.fromLTWH(0, zeroY - 0.5, w, 1), rule);
    for (var i = 0; i < n; i++) {
      final x = band * (i + 0.5);
      canvas.drawRect(
        Rect.fromLTWH(x - 0.5, kEqTravelInset, 1, h - 2 * kEqTravelInset),
        rule,
      );
    }

    final t = SunohMotion.arrive.transform(morph.value);
    final points = [
      for (var i = 0; i < n; i++)
        Offset(
          band * (i + 0.5),
          eqGainToY(lerpDouble(from[i], to[i], t)!, h, _kMinGain, _kMaxGain),
        ),
    ];

    // Flat out to both edges from the end bands, and between bands a cubic
    // with both control points at the midpoint's x: the tangent is level at
    // every band, so the curve never overshoots a peak it did not reach.
    final curve = Path()
      ..moveTo(0, points.first.dy)
      ..lineTo(points.first.dx, points.first.dy);
    for (var i = 1; i < n; i++) {
      final p = points[i - 1];
      final q = points[i];
      final mx = (p.dx + q.dx) / 2;
      curve.cubicTo(mx, p.dy, mx, q.dy, q.dx, q.dy);
    }
    curve.lineTo(w, points.last.dy);

    final wash = Path.from(curve)
      ..lineTo(w, zeroY)
      ..lineTo(0, zeroY)
      ..close();
    // Bypassed, the prototype drops the whole curve to 30%.
    final strength = 0.3 + 0.7 * on;
    canvas.drawPath(
      wash,
      Paint()..color = accent.withValues(alpha: 0.14 * strength),
    );
    canvas.drawPath(
      curve,
      Paint()
        ..color = accent.withValues(alpha: strength)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );

    // A 20×10 handle inside a 3 px ring of the rack's own ground, so the
    // curve and track stop short of it instead of running through it.
    final ringPaint = Paint()..color = ground;
    final handlePaint = Paint()..color = handle;
    for (final p in points) {
      canvas.drawPath(
        squircleBorder(
          SunohRadius.xs + 3,
        ).getOuterPath(Rect.fromCenter(center: p, width: 26, height: 16)),
        ringPaint,
      );
      canvas.drawPath(
        squircleBorder(
          SunohRadius.xs,
        ).getOuterPath(Rect.fromCenter(center: p, width: 20, height: 10)),
        handlePaint,
      );
    }
  }

  @override
  bool shouldRepaint(_RackPainter old) =>
      !identical(old.from, from) ||
      !identical(old.to, to) ||
      old.on != on ||
      old.accent != accent ||
      old.line != line ||
      old.handle != handle ||
      old.ground != ground;
}
