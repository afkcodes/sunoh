// The pill button the settings-style pages share — Sync, the Spotify
// importer, the folder picker, the device library's empty state.
//
// Primary is the accent with onAccent ink, for the step most people take;
// secondary is surface2 with fg ink. No outlined variant: an outline on a
// near-black page reads as disabled. The radius is always half the height,
// so a taller pill stays a pill.

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../widgets/motion.dart';
import '../widgets/ui.dart';

class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    required this.colors,
    required this.onTap,
    this.primary = false,
    this.icon,
    this.height = 40,
    this.expand = false,
  });

  final String label;
  final SunohColors colors;

  /// Null draws the pill disabled: secondary fill, muted label, no press.
  final VoidCallback? onTap;
  final bool primary;
  final IconData? icon;
  final double height;

  /// Fill the width it is given rather than hugging the label.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final lit = primary && onTap != null;
    final ink = lit ? c.onAccent : (onTap == null ? c.fgMute : c.fg);
    return Pressable(
      onTap: onTap,
      child: Container(
        height: height,
        padding: EdgeInsets.symmetric(horizontal: height * 0.45),
        decoration: squircleDecoration(
          radius: height / 2,
          color: lit ? c.accent : c.surface2,
        ),
        child: Center(
          widthFactor: expand ? null : 1,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: ink),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: SunohType.sans(
                  fontSize: height >= 44 ? 14 : 13.5,
                  fontWeight: FontWeight.w600,
                  color: ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
