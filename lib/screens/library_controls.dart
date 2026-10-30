// The controls above the Library list: the title row with its actions, and
// the sort row. Split from library_screen.dart, which owns the state they
// change; these only draw it and report taps.

import 'package:flutter/material.dart';
import 'package:remixicon/remixicon.dart';

import '../router/router.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';

/// "Your library" with search, Spotify import and new playlist beside it.
class LibraryTitleRow extends StatelessWidget {
  const LibraryTitleRow({
    super.key,
    required this.colors,
    required this.onNewPlaylist,
    required this.onSearch,
  });
  final SunohColors colors;
  final VoidCallback onNewPlaylist;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Your library',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SunohType.heading(fontSize: 26, color: c.fg),
              ),
            ),
            IconBtn(icon: RemixIcons.search_line, color: c.fg, onTap: onSearch),
            const SizedBox(width: 8),
            IconBtn(
              icon: RemixIcons.download_cloud_2_line,
              color: c.fg,
              onTap: () => context.openSpotifyImport(),
            ),
            const SizedBox(width: 8),
            IconBtn(
              icon: RemixIcons.add_line,
              color: c.fg,
              onTap: onNewPlaylist,
            ),
          ],
        ),
      ),
    );
  }
}

/// Sort on the left (tap to flip between the two orders), and one button on
/// the right that offers whichever view is not showing.
class LibrarySortRow extends StatelessWidget {
  const LibrarySortRow({
    super.key,
    required this.sort,
    required this.grid,
    required this.colors,
    required this.onSort,
    required this.onGrid,
  });
  final String sort;
  final bool grid;
  final SunohColors colors;
  final VoidCallback onSort;
  final VoidCallback onGrid;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 10, 4),
      child: Row(
        children: [
          GestureDetector(
            onTap: onSort,
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              height: 36,
              child: Row(
                children: [
                  Icon(RemixIcons.arrow_up_down_line, size: 16, color: c.fg),
                  const SizedBox(width: 6),
                  Text(
                    sort,
                    style: SunohType.sans(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: c.fg,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          IconBtn(
            icon: grid ? RemixIcons.list_unordered : RemixIcons.apps_2_line,
            color: c.fg,
            size: 18,
            onTap: onGrid,
          ),
        ],
      ),
    );
  }
}
