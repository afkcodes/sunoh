// Bottom navigation — Home / Search / Library. Driven by the router shell's
// branch index.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../providers/app_state_provider.dart';
import '../theme/tokens.dart';

class BottomNav extends ConsumerWidget {
  const BottomNav({super.key, required this.currentIndex, required this.onTap});

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(appStateProvider).colors;
    // Tuple: (label, activeIcon, inactiveIcon). Active uses Solar bold,
    // inactive uses outline — bottom nav lights up when selected.
    final items = <(String, IconData, IconData)>[
      ('Home', SolarIconsBold.homeAngle_2, SolarIconsOutline.homeAngle_2),
      ('Search', SolarIconsBold.magnifier, SolarIconsOutline.magnifier),
      ('Library', SolarIconsBold.musicLibrary, SolarIconsBold.musicLibrary),
    ];
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: 10 + bottomInset, top: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (var i = 0; i < items.length; i++)
            _NavItem(
              label: items[i].$1,
              icon: i == currentIndex ? items[i].$2 : items[i].$3,
              active: i == currentIndex,
              colors: c,
              onTap: () => onTap(i),
            ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.active,
    required this.colors,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool active;
  final SunohColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final col = active ? colors.fg : colors.fgMute;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: col),
            const SizedBox(height: 3),
            Text(
              label,
              style: SunohType.sans(
                fontSize: 10,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                color: col,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
