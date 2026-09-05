// 10-band graphic equalizer sheet — opened from the tweaks panel.
//
// Gains go to SunohAudioHandler.setEqBands, which builds the mpv filter chain
// in `audio/eq_filters.dart`. Not mpv's superequalizer, despite what an older
// comment here claimed — that is explicitly disabled.
//
// ## Why the layout is shaped like this
//
// The sheet used to be a `DraggableScrollableSheet` wrapping a `ListView`, with
// the band rack as one of its children. Dragging a band therefore scrolled the
// sheet away instead of moving the band: three widgets wanted the same downward
// swipe and the sliders were the innermost and weakest.
//
// The fix is structural rather than a cleverer gesture. The rack no longer sits
// inside anything that scrolls — the sheet is a fixed column of a header, a
// rack that does not move, and a preset list that scrolls on its own below. A
// drag on a band cannot reach a scrollable because there is no longer one above
// it. The sheet still drags to dismiss from its header and its preset list,
// because that is what a bottom sheet should do; the rack is carved out of
// that by the recogniser in `eq_slider.dart`, which takes a drag beginning on
// a band before the sheet can claim it.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_state_provider.dart';
import '../theme/tokens.dart';
import 'eq_presets_wall.dart';
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

/// Height of the slider travel.
///
/// Fixed rather than flexible: it is the dimension a listener aims at, and a
/// rack that stretched to fill the screen would make the same drag mean
/// different amounts of gain on different phones.
const double _kTrackHeight = 196;

/// Width of the dB gutter, and of the matching blank under it.
const double _kScaleWidth = 26;

void showEqSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    // Drags to dismiss from anywhere except the rack. That exception is won
    // per pointer by the recogniser in `eq_slider.dart`, which claims a drag
    // starting on a band before the sheet can have it.
    enableDrag: true,
    // Material's default is a 250 ms decelerate both ways, which opens
    // sluggishly and closes softly. Closing is shortened and eased out so it
    // leaves at speed and settles at the end.
    sheetAnimationStyle: const AnimationStyle(
      duration: Duration(milliseconds: 300),
      curve: Curves.fastEaseInToSlowEaseOut,
      reverseDuration: Duration(milliseconds: 220),
      reverseCurve: Curves.easeOutCubic,
    ),
    builder: (_) => const _EqSheet(),
  );
}

class _EqSheet extends ConsumerWidget {
  const _EqSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(appStateProvider).colors;
    // Deliberately *not* `resolvedAccent`. The accent follows the current
    // album's artwork, and an equaliser that changed colour with every track
    // read as decoration rather than instrumentation — the same reason the
    // HI-RES badge stopped using it. Emphasis here comes from the foreground
    // token, which is stable whatever is playing.
    final highlight = c.fg;

    return Padding(
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.bgSoft,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: c.line, width: 0.5),
        ),
        child: Column(
          children: [
            _Handle(colors: c),
            _Header(colors: c, accent: highlight),
            _Rack(colors: c, accent: highlight),
            const SizedBox(height: 10),
            Divider(height: 1, thickness: 0.5, color: c.line),
            // The only scrolling region, and the only part that needs help to
            // move the sheet — a drag anywhere else is already the sheet's.
            Expanded(
              child: EqPresetsWall(colors: c, accent: highlight),
            ),
          ],
        ),
      ),
    );
  }
}

/// The grab handle. Purely an affordance — the sheet's own drag does the work.
class _Handle extends StatelessWidget {
  const _Handle({required this.colors});
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: colors.fgMute,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.colors, required this.accent});
  final SunohColors colors;
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = colors;
    final on = s.eqEnabled;
    final active = s.eqBands.where((g) => g.abs() > 0.05).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 14, 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Equalizer',
                  style: SunohType.heading(
                    fontSize: 24,
                    color: on ? c.fg : c.fgDim,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                // Says what "off" actually means, because the distinction
                // matters to whoever went looking for this switch: bypassing
                // is not a flat curve, it is no filter in the chain at all, so
                // a lossless stream reaches the output untouched.
                Text(
                  on
                      ? (active == 0
                            ? 'Flat — nothing being changed'
                            : '$active ${active == 1 ? 'band' : 'bands'} shaping')
                      : 'Bypassed — audio passes through untouched',
                  style: SunohType.sans(
                    fontSize: 11,
                    color: on ? c.fgMute : accent,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: on,
            onChanged: s.setEqEnabled,
            activeThumbColor: c.bg,
            activeTrackColor: accent,
            inactiveThumbColor: c.fgMute,
            inactiveTrackColor: c.surface,
            trackOutlineColor: WidgetStatePropertyAll(c.line),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}

/// The rack: a dB gutter, ten sliders, and their readouts.
///
/// Deliberately not scrollable and deliberately fixed height — that is the
/// whole point, see the file header.
class _Rack extends ConsumerWidget {
  const _Rack({required this.colors, required this.accent});
  final SunohColors colors;
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = colors;
    final on = s.eqEnabled;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
      child: AnimatedOpacity(
        // Dimmed rather than hidden when off: the curve is still the
        // listener's, and seeing it is how they decide whether to switch back
        // on. Collapsing the rack would also make the sheet jump.
        opacity: on ? 1 : 0.4,
        duration: const Duration(milliseconds: 180),
        child: Column(
          children: [
            SizedBox(
              height: _kTrackHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Scale(colors: c),
                  for (var i = 0; i < kEqLabels.length; i++)
                    Expanded(
                      child: EqBandSlider(
                        gain: s.eqBands[i],
                        min: _kMinGain,
                        max: _kMaxGain,
                        enabled: on,
                        onChanged: (db) => s.setEqBand(i, db),
                        colors: c,
                        accent: accent,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                // Blank matching the gutter, so labels stay under their bands.
                const SizedBox(width: _kScaleWidth),
                for (var i = 0; i < kEqLabels.length; i++)
                  Expanded(
                    child: _BandLabel(
                      gain: s.eqBands[i],
                      label: kEqLabels[i],
                      colors: c,
                      accent: accent,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BandLabel extends StatelessWidget {
  const _BandLabel({
    required this.gain,
    required this.label,
    required this.colors,
    required this.accent,
  });

  final double gain;
  final String label;
  final SunohColors colors;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final touched = gain.abs() > 0.05;
    return Column(
      children: [
        Text(
          touched ? '${gain > 0 ? '+' : ''}${gain.toStringAsFixed(0)}' : '0',
          textAlign: TextAlign.center,
          style: SunohType.mono(
            fontSize: 9.5,
            color: touched ? accent : colors.fgMute,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          textAlign: TextAlign.center,
          style: SunohType.mono(
            fontSize: 9,
            color: colors.fgMute,
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }
}

/// The dB gutter down the left of the rack.
///
/// Without it the sliders are ten bars with no units: you can see one is higher
/// than another but not by how much, and +12 dB is a very different promise
/// from +3.
class _Scale extends StatelessWidget {
  const _Scale({required this.colors});
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    TextStyle style(bool strong) => SunohType.mono(
      fontSize: 8.5,
      color: strong ? colors.fgDim : colors.fgMute,
    );
    return SizedBox(
      width: _kScaleWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('+12', style: style(false)),
          Text('0', style: style(true)),
          Text('−12', style: style(false)),
        ],
      ),
    );
  }
}
