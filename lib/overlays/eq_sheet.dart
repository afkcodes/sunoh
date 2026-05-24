// 10-band graphic equalizer sheet — opened from the tweaks panel.
// Vertical band sliders (one per ISO frequency 32 Hz..16 kHz) + a category-
// grouped preset chip list. mpv's 18-band superequalizer is the actual
// engine; we map bands 4b..13b through SunohAudioHandler.setEqBands.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/eq_presets.dart';
import '../providers/app_state_provider.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';

void showEqSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    // Open at full height — the band rack + preset wall use the whole screen
    // comfortably and partial-height felt cramped.
    useSafeArea: true,
    builder: (_) => const _EqSheet(),
  );
}

class _EqSheet extends ConsumerWidget {
  const _EqSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final accent = s.resolvedAccent;

    return DraggableScrollableSheet(
      initialChildSize: 1.0,
      minChildSize: 0.6,
      maxChildSize: 1.0,
      expand: false,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: c.bgSoft,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: c.line, width: 0.5),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: c.fgMute,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text('Equalizer',
                      style: SunohType.heading(
                          fontSize: 26, color: c.fg, letterSpacing: -0.3)),
                ),
                GestureDetector(
                  onTap: s.resetEq,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('Reset',
                        style: SunohType.sans(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: c.fgMute)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            _BandRack(colors: c, accent: accent),
            const SizedBox(height: 24),
            for (final entry in kEqPresetCategories.entries) ...[
              eyebrow(entry.key.toUpperCase(), c.fgMute, size: 10, letterSpacing: 1.4),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final id in entry.value)
                    _PresetChip(
                      preset: eqPresetById(id)!,
                      selected: s.currentEqPresetId == id,
                      colors: c,
                      accent: accent,
                      onTap: () => s.applyEqPreset(eqPresetById(id)!),
                    ),
                ],
              ),
              const SizedBox(height: 18),
            ],
          ],
        ),
      ),
    );
  }
}

/// The 10 vertical band sliders. Drag vertically on any column to adjust
/// its gain. Lightly haptic to match the design system feel.
class _BandRack extends ConsumerWidget {
  const _BandRack({required this.colors, required this.accent});
  final SunohColors colors;
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    return SizedBox(
      height: 220,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < 10; i++)
            Expanded(
              child: _BandColumn(
                index: i,
                label: SunohState.eqLabels[i],
                gain: s.eqBands[i],
                onChanged: (db) => s.setEqBand(i, db),
                colors: colors,
                accent: accent,
              ),
            ),
        ],
      ),
    );
  }
}

/// Static config helper — frequency labels matching the audio_x topology
/// the handler implements (lowshelf 31 Hz, peaking 63–8000 Hz, highshelf 16 kHz).
class SunohState {
  static const eqLabels = [
    '31', '63', '125', '250', '500', '1k', '2k', '4k', '8k', '16k',
  ];
}

class _BandColumn extends StatelessWidget {
  const _BandColumn({
    required this.index,
    required this.label,
    required this.gain,
    required this.onChanged,
    required this.colors,
    required this.accent,
  });
  final int index;
  final String label;
  final double gain;
  final ValueChanged<double> onChanged;
  final SunohColors colors;
  final Color accent;

  static const double _min = -12;
  static const double _max = 12;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final readout = gain.abs() < 0.05
        ? '0'
        : '${gain >= 0 ? '+' : ''}${gain.toStringAsFixed(0)}';
    return Column(
      children: [
        SizedBox(
          height: 18,
          child: Center(
            child: Text(
              readout,
              style: SunohType.mono(
                fontSize: 10,
                color: gain.abs() > 0.05 ? c.fg : c.fgMute,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
        Expanded(child: _VerticalSlider(
          gain: gain,
          min: _min,
          max: _max,
          onChanged: onChanged,
          colors: c,
          accent: accent,
        )),
        const SizedBox(height: 8),
        Text(label,
            style: SunohType.mono(
                fontSize: 9.5, color: c.fgMute, letterSpacing: 0.6)),
      ],
    );
  }
}

/// Custom vertical slider. Tap or drag along the track to set gain.
class _VerticalSlider extends StatelessWidget {
  const _VerticalSlider({
    required this.gain,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.colors,
    required this.accent,
  });
  final double gain;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final SunohColors colors;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;

        // gain → fraction 0..1 from bottom of column.
        // 0 dB sits in the middle.
        double gainToY(double g) {
          final t = (g - min) / (max - min); // 0 at min, 1 at max
          return (1 - t) * h;
        }

        void apply(Offset local) {
          final clamped = local.dy.clamp(0.0, h);
          final t = 1 - (clamped / h);
          final value = min + t * (max - min);
          // Snap to whole dB so the visuals feel detented.
          onChanged(value.roundToDouble());
        }

        final centerY = gainToY(0);
        final thumbY = gainToY(gain);
        // Fill rectangle between 0 dB line and current gain (positive or negative).
        final fillTop = thumbY < centerY ? thumbY : centerY;
        final fillHeight = (thumbY - centerY).abs();

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => apply(d.localPosition),
          onPanUpdate: (d) => apply(d.localPosition),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Background track.
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // 0-dB tick (subtle horizontal line).
              Positioned(
                top: centerY - 0.5,
                left: 6,
                right: 6,
                child: Container(height: 1, color: c.line),
              ),
              // Fill from center to current gain.
              Positioned(
                top: fillTop,
                child: Container(
                  width: 4,
                  height: fillHeight.clamp(0, h),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Thumb.
              Positioned(
                top: thumbY - 6,
                child: Container(
                  width: 14,
                  height: 12,
                  decoration: BoxDecoration(
                    color: c.fg,
                    borderRadius: BorderRadius.circular(3),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 6,
                          offset: const Offset(0, 2)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? accent : c.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? accent : c.line,
            width: 0.5,
          ),
        ),
        child: Text(
          preset.name,
          style: SunohType.sans(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: selected ? const Color(0xFF0B0B0D) : c.fg,
          ),
        ),
      ),
    );
  }
}
