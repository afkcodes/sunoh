// Bottom navigation — Home / Search / Library. Driven by the router shell's
// branch index.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remixicon/remixicon.dart';

import '../providers/app_state_provider.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';

class BottomNav extends ConsumerWidget {
  const BottomNav({super.key, required this.currentIndex, required this.onTap});

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(appStateProvider).colors;
    // Tuple: (label, activeIcon, inactiveIcon). Active uses Remix fill,
    // inactive uses outline — bottom nav lights up when selected.
    final items = <(String, IconData, IconData)>[
      ('Home', RemixIcons.home_5_fill, RemixIcons.home_5_line),
      ('Search', RemixIcons.search_fill, RemixIcons.search_line),
      ('Library', RemixIcons.music_2_fill, RemixIcons.music_2_line),
    ];
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: 6 + bottomInset, top: 6),
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

/// One destination: a short bar above the icon marks the open tab, so the
/// selection reads from the shape as well as the colour.
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
      child: SizedBox(
        width: 84,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: SunohMotion.ui,
              curve: SunohMotion.arrive,
              width: active ? 18 : 0,
              height: 2,
              decoration: squircleDecoration(radius: 1, color: colors.fg),
            ),
            const SizedBox(height: 7),
            AnimatedScale(
              scale: active ? 1.06 : 1,
              duration: SunohMotion.ui,
              curve: SunohMotion.arrive,
              child: Icon(icon, size: 24, color: col),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: SunohType.sans(
                fontSize: 11,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                color: col,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
