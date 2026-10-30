// 10-band graphic equalizer sheet — opened from the player.
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
// inside anything that scrolls — the sheet is a fixed column of a header, the
// preset chips (which scroll on their own), the rack, and its two rows. The
// order is the prototype's: presets above the rack, so a tapped chip and the
// curve it bends sit next to each other. Only the chips scroll; with
// thirty-four of them a single scrolling page would have pushed the rack off
// the bottom of the screen, and put it back inside a scrollable besides.
//
// The sheet still drags to dismiss from its header and its rows, because that
// is what a bottom sheet should do; the rack is carved out of that by the
// recogniser in `eq_slider.dart`, which takes a drag beginning on a band
// before the sheet can claim it.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remixicon/remixicon.dart';

import '../audio/eq_presets.dart';
import '../providers/app_state_provider.dart';
import '../theme/tokens.dart';
import '../widgets/motion.dart';
import '../widgets/ui.dart';
import 'eq_presets_wall.dart';
import 'eq_rack.dart';
import 'sheet.dart';

/// How far below the status bar the sheet starts: the player's header row
/// stays visible above it, as in the prototype, so the equalizer reads as a
/// layer over the song rather than a new page.
const double _kTopGap = 52;

/// Below this the fixed layout would leave the chips no room: the header,
/// rack and rows take about 500 between them.
const double _kMinFixedHeight = 620;

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
    sheetAnimationStyle: kSheetMotion,
    builder: (_) => const _EqSheet(),
  );
}

class _EqSheet extends ConsumerWidget {
  const _EqSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(appStateProvider).colors;
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Padding(
      // `useSafeArea` has already taken the status bar off the top.
      padding: const EdgeInsets.only(top: _kTopGap),
      child: DecoratedBox(
        // Full height and attached to the bottom edge, top corners only —
        // the same sheet every other one in the app now is.
        decoration: ShapeDecoration(
          color: c.bgSoft,
          shape: squircleTopBorder(SunohRadius.sheet),
        ),
        child: Padding(
          padding: EdgeInsets.only(top: 8, bottom: bottom + 12),
          child: LayoutBuilder(
            builder: (context, box) {
              final top = [SheetHandle(colors: c), _Header(colors: c)];
              final bottom = [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 20, 16, 0),
                  child: EqRack(),
                ),
                _Rows(colors: c),
              ];
              // Too short to hold the rack, its rows and any chips at once —
              // landscape, mostly. Everything scrolls together then, and the
              // band recogniser's eager win is what keeps the rack usable.
              if (box.maxHeight < _kMinFixedHeight) {
                return ListView(
                  children: [
                    ...top,
                    EqPresetsWall(colors: c, embedded: true),
                    ...bottom,
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...top,
                  // The only scrolling region — see the file header.
                  Expanded(child: EqPresetsWall(colors: c)),
                  ...bottom,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.colors});
  final SunohColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = colors;
    final on = s.eqEnabled;
    final active = s.eqBands.where((g) => g.abs() > 0.05).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Equalizer',
                  style: SunohType.heading(fontSize: 22, color: c.fg),
                ),
                const SizedBox(height: 2),
                // Says what "off" actually means, because the distinction
                // matters to whoever went looking for this switch: bypassing
                // is not a flat curve, it is no filter in the chain at all, so
                // a lossless file reaches the output untouched.
                Text(
                  on
                      ? (active == 0
                            ? 'Flat — nothing being changed'
                            : '$active ${active == 1 ? 'band' : 'bands'} shaping')
                      : 'Bypassed — audio passes through untouched',
                  style: SunohType.sans(fontSize: 12.5, color: c.fgDim),
                ),
              ],
            ),
          ),
          // The settings switch: accent track, onAccent thumb, no outline.
          // The accent here is the palette's, which follows the artwork when
          // tint-from-art is on — the prototype colours the whole equalizer
          // with the song, curve included.
          Switch(
            value: on,
            onChanged: s.setEqEnabled,
            activeTrackColor: c.accent,
            activeThumbColor: c.onAccent,
            inactiveTrackColor: c.surface2,
            inactiveThumbColor: c.fgDim,
            trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}

/// The settings-style rows under the rack: what the current preset is for,
/// and the way back to flat.
class _Rows extends ConsumerWidget {
  const _Rows({required this.colors});
  final SunohColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final id = s.currentEqPresetId;
    final preset = id == null ? null : eqPresetById(id);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        children: [
          // The descriptions were written with the presets and are the one
          // thing a chip cannot carry, so the selected one's lives here.
          _SetRow(
            label: preset?.name ?? 'Custom',
            helper: preset?.description ?? 'Custom curve — no preset selected.',
            colors: colors,
          ),
          _SetRow(label: 'Reset to flat', onTap: s.resetEq, colors: colors),
        ],
      ),
    );
  }
}

/// A settings row: label, optional helper, a divider under it, and a chevron
/// when it does something.
class _SetRow extends StatelessWidget {
  const _SetRow({
    required this.label,
    required this.colors,
    this.helper,
    this.onTap,
  });

  final String label;
  final String? helper;
  final VoidCallback? onTap;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Pressable(
      scale: 0.99,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.line)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: SunohType.sans(fontSize: 15, color: c.fg)),
                  if (helper != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      helper!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SunohType.sans(
                        fontSize: 12.5,
                        color: c.fgMute,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onTap != null)
              Icon(RemixIcons.arrow_right_s_line, size: 16, color: c.fgMute),
          ],
        ),
      ),
    );
  }
}
