// How to order the on-device songs list.
//
// A field and a direction, chosen separately, because they are separate
// questions: "by artist" and "Z to A" do not belong in one flat list of ten
// options where half are permutations of the other half.
//
// The direction is worded per field — "Newest first" rather than
// "Descending" — since ascending means nothing until you know what is being
// sorted.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../api/local_sort.dart';
import '../providers/app_state_provider.dart';
import '../providers/local_library_provider.dart';
import '../theme/tokens.dart';
import 'sheet.dart';

Future<void> showLocalSortSheet(BuildContext context) =>
    showSunohSheet<void>(context, builder: (_) => const _LocalSortSheet());

class _LocalSortSheet extends ConsumerWidget {
  const _LocalSortSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(appStateProvider).colors;
    final lib = ref.watch(localLibraryProvider);

    return SunohSheet(
      icon: SolarIconsOutline.sort,
      title: 'Sort songs',
      subtitle: 'Albums always play in track order',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final option in LocalSort.values)
            _Row(
              label: option.label,
              selected: lib.sort == option,
              colors: c,
              onTap: () => lib.setSort(option, ascending: lib.sortAscending),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Text(
              'ORDER',
              style: SunohType.sans(
                fontSize: 11,
                color: c.fgMute,
                letterSpacing: 1.4,
              ),
            ),
          ),
          _Row(
            label: lib.sort.descendingLabel,
            selected: !lib.sortAscending,
            colors: c,
            onTap: () => lib.setSort(lib.sort, ascending: false),
          ),
          _Row(
            label: lib.sort.ascendingLabel,
            selected: lib.sortAscending,
            colors: c,
            onTap: () => lib.setSort(lib.sort, ascending: true),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.selected,
    required this.colors,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final SunohColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: SunohType.sans(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? c.fg : c.fgDim,
                ),
              ),
            ),
            if (selected)
              Icon(SolarIconsBold.checkCircle, size: 17, color: c.accent),
          ],
        ),
      ),
    );
  }
}
