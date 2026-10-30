// The Library's inline filter: replaces the title row while open. Same ghost
// style as the Search tab's field (search_header.dart) so the two read as one
// control, but it only narrows the user's own library, so it has no submit.

import 'package:flutter/material.dart';
import 'package:remixicon/remixicon.dart';

import '../theme/tokens.dart';
import '../widgets/ui.dart';

class LibrarySearchRow extends StatelessWidget {
  const LibrarySearchRow({
    super.key,
    required this.colors,
    required this.controller,
    required this.focus,
    required this.onChanged,
    required this.onClose,
  });
  final SunohColors colors;
  final TextEditingController controller;
  final FocusNode focus;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
        child: DecoratedBox(
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
                  autofocus: true,
                  onChanged: onChanged,
                  cursorColor: c.accent,
                  textInputAction: TextInputAction.search,
                  style: SunohType.sans(fontSize: 15.5, color: c.fg),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: 'Search your library',
                    hintStyle: SunohType.sans(fontSize: 15.5, color: c.fgMute),
                  ),
                ),
              ),
              // Always present: clearing the text and closing the field are
              // the same gesture here, so one button covers both.
              GestureDetector(
                onTap: onClose,
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 44,
                  height: double.infinity,
                  child: Icon(
                    RemixIcons.close_circle_line,
                    size: 18,
                    color: c.fgDim,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
