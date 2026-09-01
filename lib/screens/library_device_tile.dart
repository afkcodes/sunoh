// The Library tab's entry point into the on-device music library.

import 'package:flutter/material.dart';
import 'package:solar_icons/solar_icons.dart';

import '../theme/tokens.dart';
import '../widgets/ui.dart';

class DeviceTile extends StatelessWidget {
  const DeviceTile({
    super.key,
    required this.colors,
    required this.subtitle,
    required this.onTap,
  });
  final SunohColors colors;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        decoration: squircleDecoration(
          radius: 14,
          color: colors.surface,
          borderColor: colors.line,
        ),
        child: Row(
          children: [
            Icon(SolarIconsOutline.smartphone, size: 19, color: colors.fgDim),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'On this device',
                    style: SunohType.sans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.fg,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: SunohType.sans(fontSize: 12, color: colors.fgMute),
                  ),
                ],
              ),
            ),
            Icon(
              SolarIconsOutline.altArrowRight,
              size: 16,
              color: colors.fgMute,
            ),
          ],
        ),
      ),
    );
  }
}
