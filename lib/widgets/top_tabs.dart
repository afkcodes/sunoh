// The app's tab strip: active tab as a large heading, the rest small and
// muted, an accent underline beneath the active one.
//
// Extracted from the Home screen so the device library uses the same control
// rather than a lookalike. Two tab strips that drift apart is the exact
// failure `docs/ENGINEERING.md` section 3.5 is about.

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class SunohTabs extends StatelessWidget {
  const SunohTabs({
    super.key,
    required this.tabs,
    required this.active,
    required this.onChange,
    required this.colors,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 14),
    this.divider = true,
  });

  final List<String> tabs;
  final String active;
  final ValueChanged<String> onChange;
  final SunohColors colors;
  final EdgeInsets padding;

  /// The hairline under the strip. Home sits it against the feed; a screen
  /// with its own header may not want it.
  final bool divider;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: divider
          ? BoxDecoration(
              border: Border(
                bottom: BorderSide(color: colors.line, width: 0.5),
              ),
            )
          : null,
      child: Row(
        children: [
          for (final t in tabs)
            Padding(
              padding: const EdgeInsets.only(right: 22),
              child: GestureDetector(
                onTap: () => onChange(t),
                child: SunohTabLabel(
                  label: t,
                  active: t == active,
                  colors: colors,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class SunohTabLabel extends StatelessWidget {
  const SunohTabLabel({
    super.key,
    required this.label,
    required this.active,
    required this.colors,
  });
  final String label;
  final bool active;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: active
              ? SunohType.heading(
                  fontSize: 22,
                  color: colors.fg,
                  letterSpacing: -0.2,
                )
              : SunohType.sans(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: colors.fgMute,
                ),
        ),
        const SizedBox(height: 4),
        Container(
          height: 1.5,
          width: 28,
          color: active ? colors.accent : Colors.transparent,
        ),
      ],
    );
  }
}
