// Search's pinned header: the title, the inverted field, and the chips that
// jump to a section of results.
//
// Split out of search_screen.dart, which was over the size limit, along the
// seam it already had: the screen owns the query and the scrolling, this
// owns how the block that stays put is drawn and how tall it is.

import 'package:flutter/material.dart';
import 'package:remixicon/remixicon.dart';

import '../api/dto.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';

/// The pinned header's parts. Kept as numbers because a persistent header
/// has to state its height before it builds — it cannot measure the field
/// and the chips and then report what it found — and the build below lays
/// each part out at exactly these heights. Change one without the other and
/// the sliver's geometry assertion fires.
const double _kTitleExtent = 56;
const double _kFieldHeight = 46;
const double _kFieldExtent = _kFieldHeight + 12; // the field, 12 below
const double _kPillsExtent = 2 + SectionPills.height + 12; // 2 above, 12 below

/// The pinned block: the title, the field, and the jump chips when results
/// have come back with more than one section.
///
/// Its height changes when the chips appear, which a persistent header is
/// allowed to do as long as [shouldRebuild] says so — otherwise the list keeps
/// reserving the old extent and the first section hides underneath. Opaque,
/// with a hard edge as the prototype draws it: results pass under the page
/// colour rather than behind a fade.
class SearchHeader extends SliverPersistentHeaderDelegate {
  SearchHeader({
    required this.extent,
    required this.colors,
    required this.controller,
    required this.focus,
    required this.showClear,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
    required this.pills,
    required this.onJumpToSection,
  });

  final double extent;
  final SunohColors colors;
  final TextEditingController controller;
  final FocusNode focus;
  final bool showClear;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;
  final List<HomeSection>? pills;
  final void Function(String heading) onJumpToSection;

  /// Height of the header: the title and the field, plus the chips when
  /// there are enough sections to be worth jumping between.
  static double extentFor({required bool withChips}) =>
      _kTitleExtent + _kFieldExtent + (withChips ? _kPillsExtent : 0);

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapped) {
    final c = colors;
    return SizedBox(
      height: extent,
      child: ColoredBox(
        color: c.bg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: _kTitleExtent,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Search',
                    maxLines: 1,
                    style: SunohType.heading(fontSize: 26, color: c.fg),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _SearchField(
                colors: c,
                controller: controller,
                focus: focus,
                showClear: showClear,
                onChanged: onChanged,
                onSubmitted: onSubmitted,
                onClear: onClear,
              ),
            ),
            if (pills != null)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 12),
                child: SectionPills(
                  sections: pills!,
                  colors: c,
                  onTap: onJumpToSection,
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(SearchHeader old) =>
      old.extent != extent ||
      old.colors != colors ||
      old.showClear != showClear ||
      old.pills != pills;
}

/// The field, ghosted: a faint surface fill lettered in ink, like every other
/// surface on the page. An inverted ink block was tried and read as a white
/// slab louder than anything it searched. The clear button keeps its slot
/// when hidden, so the text does not shift as the first letter is typed.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.colors,
    required this.controller,
    required this.focus,
    required this.showClear,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  final SunohColors colors;
  final TextEditingController controller;
  final FocusNode focus;
  final bool showClear;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Container(
      height: _kFieldHeight,
      decoration: squircleDecoration(
        radius: SunohRadius.card,
        color: c.surface2,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Icon(RemixIcons.search_line, size: 20, color: c.fgDim),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focus,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              cursorColor: c.accent,
              textInputAction: TextInputAction.search,
              style: SunohType.sans(fontSize: 15.5, color: c.fg),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Artists, songs, podcasts…',
                hintStyle: SunohType.sans(fontSize: 15.5, color: c.fgMute),
              ),
            ),
          ),
          SizedBox(
            width: 44,
            height: _kFieldHeight,
            child: showClear
                ? GestureDetector(
                    onTap: onClear,
                    behavior: HitTestBehavior.opaque,
                    child: Icon(
                      RemixIcons.close_circle_line,
                      size: 18,
                      color: c.fgDim,
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

class SectionPills extends StatelessWidget {
  const SectionPills({
    super.key,
    required this.sections,
    required this.colors,
    required this.onTap,
  });
  final List<HomeSection> sections;
  final SunohColors colors;
  final void Function(String heading) onTap;

  /// A chip's height. The pinned header counts on it.
  static const double height = 32;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: sections.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final s = sections[i];
          return SunohChip(
            label: _shortLabel(s.heading),
            selected: false,
            colors: c,
            onTap: () => onTap(s.heading),
          );
        },
      ),
    );
  }

  /// Compact display label for a section heading. Most headings come
  /// straight from the upstream API ("Songs", "Artists") and read
  /// fine; the longer / casing-inconsistent ones get normalised.
  static String _shortLabel(String heading) {
    final h = heading.trim();
    final lower = h.toLowerCase();
    if (lower.contains('top result') || lower == 'topquery') return 'Top';
    if (lower.contains('podcast')) return 'Podcasts';
    return h.isEmpty ? '—' : h[0].toUpperCase() + h.substring(1);
  }
}
