// The app's tab strip: a row of chips, the active one filled with the ink
// colour.
//
// It used to set the active tab as a 22px heading with the others small and
// muted beside it. That made the strip the loudest thing on Home, louder than
// the feed it switches, and the width of a heading changed as you tapped along
// so the row jumped. Chips hold their size, and the filled one says which tab
// is open without needing an underline.
//
// Extracted from the Home screen so the device library uses the same control
// rather than a lookalike. Two tab strips that drift apart is the exact
// failure `docs/ENGINEERING.md` section 3.5 is about.

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'ui.dart';

class SunohTabs extends StatelessWidget {
  const SunohTabs({
    super.key,
    required this.tabs,
    required this.active,
    required this.onChange,
    required this.colors,
    this.padding = const EdgeInsets.fromLTRB(20, 10, 20, 12),
  });

  final List<String> tabs;
  final String active;
  final ValueChanged<String> onChange;
  final SunohColors colors;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            SunohChip(
              label: tabs[i],
              selected: tabs[i] == active,
              colors: colors,
              onTap: () => onChange(tabs[i]),
            ),
          ],
        ],
      ),
    );
  }
}
