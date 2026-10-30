// How to order the on-device songs list.
//
// A field and a direction, chosen separately, because they are separate
// questions: "by artist" and "Z to A" do not belong in one flat list of ten
// options where half are permutations of the other half. The field is a chip
// set and the direction a two-way segmented control — an option set and a
// toggle, drawn as what they are.
//
// The direction is worded per field — "Newest first" rather than
// "Descending" — since ascending means nothing until you know what is being
// sorted.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/local_sort.dart';
import '../providers/app_state_provider.dart';
import '../providers/local_library_provider.dart';
import '../widgets/ui.dart';
import 'sheet.dart';
import 'sheet_row.dart';

Future<void> showLocalSortSheet(BuildContext context) =>
    showSunohSheet<void>(context, builder: (_) => const _LocalSortSheet());

class _LocalSortSheet extends ConsumerWidget {
  const _LocalSortSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(appStateProvider).colors;
    final lib = ref.watch(localLibraryProvider);

    return SunohSheet(
      title: 'Sort songs',
      subtitle: 'Albums always play in track order',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SheetLabel(
            'Sort by',
            colors: c,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in LocalSort.values)
                  SunohChip(
                    label: option.label,
                    selected: lib.sort == option,
                    colors: c,
                    onTap: () =>
                        lib.setSort(option, ascending: lib.sortAscending),
                  ),
              ],
            ),
          ),
          SheetLabel('Order', colors: c),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SheetSegmented(
              labels: [lib.sort.descendingLabel, lib.sort.ascendingLabel],
              selected: lib.sortAscending ? 1 : 0,
              onSelect: (i) => lib.setSort(lib.sort, ascending: i == 1),
              colors: c,
            ),
          ),
        ],
      ),
    );
  }
}
