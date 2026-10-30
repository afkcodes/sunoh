// The preset chips between the equalizer's header and its rack.
//
// Split out of `eq_sheet.dart` to keep that file focused on the layout problem
// it exists to solve (see its header). This is the sheet's only scrolling
// region, and deliberately contains nothing draggable.
//
// ## Why chips, again
//
// There are thirty-four presets. For a while each was a card drawing its own
// curve, because as name-only chips the only way to learn what "Midrange
// Magic" did was to apply it and listen. The redesign returns them to chips —
// the prototype's preset row — because that problem is now solved where the
// listener is already looking: the rack directly below morphs to a preset's
// curve the moment its chip is tapped, which shows the shape faster than a
// thumbnail did and at a size that can actually be read. The selected
// preset's description sits under the rack.
//
// The categories stay, as eyebrows over each group, so Bass Boost is found
// under Focus rather than somewhere in a wall of thirty-four.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/eq_presets.dart';
import '../providers/app_state_provider.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';
import 'sheet_row.dart';

/// The categories with their presets resolved once, rather than looked up by
/// id for every chip on every build.
final List<(String, List<EqPreset>)> _kGroups = [
  for (final e in kEqPresetCategories.entries)
    (e.key, [for (final id in e.value) eqPresetById(id)!]),
];

class EqPresetsWall extends ConsumerWidget {
  const EqPresetsWall({super.key, required this.colors, this.embedded = false});

  final SunohColors colors;

  /// Laid out flat inside a parent's scroll view rather than scrolling on its
  /// own — the sheet's short-screen layout.
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only the selection repaints the chips; a band drag elsewhere in the
    // sheet does not rebuild thirty-four of them per detent.
    final selected = ref.watch(
      appStateProvider.select((s) => s.currentEqPresetId),
    );
    final s = ref.read(appStateProvider);
    final c = colors;

    Widget group(int i) {
      final (name, presets) = _kGroups[i];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SheetLabel(
            name,
            colors: c,
            padding: EdgeInsets.fromLTRB(16, i == 0 ? 2 : 16, 16, 8),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in presets)
                  SunohChip(
                    label: preset.name,
                    selected: selected == preset.id,
                    colors: c,
                    onTap: () => s.applyEqPreset(preset),
                  ),
              ],
            ),
          ),
        ],
      );
    }

    if (embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (var i = 0; i < _kGroups.length; i++) group(i)],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 4),
      itemCount: _kGroups.length,
      itemBuilder: (_, i) => group(i),
    );
  }
}
