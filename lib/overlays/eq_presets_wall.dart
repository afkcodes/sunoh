// The preset wall below the equalizer rack.
//
// Split out of `eq_sheet.dart` to keep that file focused on the layout problem
// it exists to solve (see its header). This is the sheet's only scrolling
// region, and deliberately contains nothing draggable.
//
// ## Why cards with curves instead of a wall of pills
//
// There are thirty-four presets. As name-only chips they were thirty-four
// identical lozenges, and the only way to find out what "Midrange Magic" did
// was to apply it and listen — so choosing meant walking the whole list by ear.
//
// Each card now draws the preset's own curve, which is the one thing that
// actually distinguishes them and is already sitting in the data. Bass Boost
// visibly falls from left to right, Treble Boost visibly climbs, and the
// reference presets are visibly almost flat. The names still read; the shape
// just gets there first.
//
// The descriptions were also already written and never shown anywhere. The
// selected one now appears under the heading, which gives the row of shapes a
// sentence of context without putting a paragraph on every card.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/eq_presets.dart';
import '../providers/app_state_provider.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';

/// Card metrics. The curve needs enough width to read as a shape rather than a
/// zigzag, and enough height that ±12 dB is visibly different from ±3.
const double _kCardWidth = 104;
const double _kCurveHeight = 44;
const double _kRowHeight = 78;

class EqPresetsWall extends ConsumerWidget {
  const EqPresetsWall({super.key, required this.colors, required this.accent});

  final SunohColors colors;
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = colors;
    final selected = s.currentEqPresetId;
    final current = selected == null ? null : eqPresetById(selected);

    return ListView(
      padding: const EdgeInsets.only(top: 14, bottom: 28),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(
                child: eyebrow(
                  'PRESETS',
                  c.fgMute,
                  size: 10,
                  letterSpacing: 1.4,
                ),
              ),
              GestureDetector(
                onTap: s.resetEq,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: Text(
                    'Reset',
                    style: SunohType.sans(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: c.fgDim,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // The selected preset's own words. Sized for two lines so the rows
        // below do not shift as the selection moves between a short
        // description and a long one.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
          child: SizedBox(
            height: 32,
            child: Text(
              current?.description ?? 'Custom curve — no preset selected.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: SunohType.sans(
                fontSize: 11.5,
                color: current == null ? c.fgMute : c.fgDim,
                height: 1.35,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (final entry in kEqPresetCategories.entries) ...[
          Padding(
            padding: const EdgeInsets.only(left: 20),
            child: eyebrow(
              entry.key.toUpperCase(),
              c.fgMute,
              size: 9,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: _kRowHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: entry.value.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final preset = eqPresetById(entry.value[i])!;
                return _PresetCard(
                  preset: preset,
                  selected: selected == preset.id,
                  colors: c,
                  accent: accent,
                  onTap: () => s.applyEqPreset(preset),
                );
              },
            ),
          ),
          const SizedBox(height: 18),
        ],
      ],
    );
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.preset,
    required this.selected,
    required this.colors,
    required this.accent,
    required this.onTap,
  });

  final EqPreset preset;
  final bool selected;
  final SunohColors colors;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: _kCardWidth,
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: squircleDecoration(
          radius: 14,
          color: selected ? accent.withValues(alpha: 0.16) : c.surface,
          borderColor: selected ? accent : c.line,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: _kCurveHeight,
              width: double.infinity,
              child: CustomPaint(
                painter: _CurvePainter(
                  gains: preset.gains,
                  color: selected ? accent : c.fgDim,
                  baseline: c.line,
                ),
              ),
            ),
            const Spacer(),
            Text(
              preset.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SunohType.sans(
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? c.fg : c.fgDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Draws a preset's ten gains as one curve.
///
/// Smoothed rather than a polyline: the bands are samples of a response that is
/// continuous in reality, and straight segments between them read as ten
/// separate decisions instead of one shape.
class _CurvePainter extends CustomPainter {
  const _CurvePainter({
    required this.gains,
    required this.color,
    required this.baseline,
  });

  final List<double> gains;
  final Color color;
  final Color baseline;

  /// The rack's range, so a card's curve means the same thing as the sliders.
  static const double _range = 12;

  @override
  void paint(Canvas canvas, Size size) {
    if (gains.isEmpty) return;
    final midY = size.height / 2;

    // 0 dB reference, so a curve can be read as above or below flat rather
    // than just "some shape".
    canvas.drawLine(
      Offset(0, midY),
      Offset(size.width, midY),
      Paint()
        ..color = baseline
        ..strokeWidth = 1,
    );

    final dx = size.width / (gains.length - 1);
    // Inset so a +12 curve does not sit half-clipped on the top edge.
    final amplitude = (size.height / 2) - 3;
    Offset pointAt(int i) => Offset(
      dx * i,
      midY - (gains[i].clamp(-_range, _range) / _range) * amplitude,
    );

    final path = Path()..moveTo(pointAt(0).dx, pointAt(0).dy);
    for (var i = 0; i < gains.length - 1; i++) {
      final p = pointAt(i);
      final q = pointAt(i + 1);
      // Horizontal control points put the tangent flat at each band centre,
      // which keeps the curve from overshooting past a peak it never reached.
      path.cubicTo(p.dx + dx / 2, p.dy, q.dx - dx / 2, q.dy, q.dx, q.dy);
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CurvePainter old) =>
      old.color != color || old.baseline != baseline || old.gains != gains;
}
