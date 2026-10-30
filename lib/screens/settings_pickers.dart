// The settings rows that pick a value rather than go somewhere: a chip set,
// a slider, and the accent swatches. Each sits in the same ruled frame as the
// rows in settings_rows.dart.

part of 'settings_screen.dart';

class _RadioRow<T> extends StatelessWidget {
  const _RadioRow({
    required this.label,
    required this.value,
    required this.options,
    required this.onChange,
    required this.colors,
  });
  final String label;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChange;
  final SunohColors colors;

  /// Past three chips the row no longer fits beside a label on a phone — the
  /// label ellipsises to "Stream q…" and the chips run to the screen edge.
  /// Rather than have callers remember, the row stacks itself and gives the
  /// chips their own line, wrapping if they must. Three-option rows (theme,
  /// density) keep the compact inline form.
  bool get _stacked => options.length > 3;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: SunohType.sans(fontSize: 15, color: colors.fg),
    );
    final chips = Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final e in options.entries)
          SunohChip(
            label: e.value,
            selected: e.key == value,
            colors: colors,
            onTap: () => onChange(e.key),
          ),
      ],
    );

    return _RowFrame(
      colors: colors,
      child: _stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [text, const SizedBox(height: 10), chips],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(child: text),
                const SizedBox(width: 12),
                chips,
              ],
            ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.suffix,
    required this.onChange,
    required this.colors,
  });
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String suffix;
  final ValueChanged<double> onChange;
  final SunohColors colors;
  @override
  Widget build(BuildContext context) {
    final c = colors;
    return _RowFrame(
      colors: c,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: SunohType.sans(fontSize: 15, color: c.fg)),
              Text(suffix, style: SunohType.mono(fontSize: 13, color: c.fgDim)),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: c.accent,
              inactiveTrackColor: c.surface2,
              thumbColor: c.fg,
              overlayColor: c.accent.withValues(alpha: 0.12),
              trackHeight: 3,
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChange,
            ),
          ),
        ],
      ),
    );
  }
}

/// Compound row: "Accent" label + the 12-swatch grid, as one row of the
/// Appearance group.
class _AccentRow extends StatelessWidget {
  const _AccentRow({
    required this.s,
    required this.colors,
    required this.scale,
  });
  final AppState s;
  final SunohColors colors;
  final double scale;
  @override
  Widget build(BuildContext context) {
    final c = colors;
    return _RowFrame(
      colors: c,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Accent', style: SunohType.sans(fontSize: 15, color: c.fg)),
          SizedBox(height: 14 * scale),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              for (final col in kAccentOptions)
                Pressable(
                  onTap: () => s.setAccent(col),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: col,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: s.accent == col && !s.tintFromArt
                            ? c.fg
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
