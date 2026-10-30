// The bar a pushed settings-style page wears: back on the left, the page's
// name centred, and the page's own actions on the right.
//
// Always solid — the page tinted 14% toward the accent, with a line under it —
// which is the prototype's settings bar. Album and artist pages fade theirs in
// over a hero; these pages have no hero, so a transparent bar would reveal
// nothing and only let rows scroll visibly under the status bar.
//
// Shared by Settings, Sync, the Spotify importer, the device library and its
// folder picker, and the category grids, so a page reached from any of them
// opens with the same chrome.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:remixicon/remixicon.dart';

import '../theme/tokens.dart';
import '../widgets/ui.dart';

class SubPageBar extends StatelessWidget {
  const SubPageBar({
    super.key,
    required this.title,
    required this.colors,
    this.actions = const <Widget>[],
  });

  final String title;
  final SunohColors colors;

  /// Right-hand controls, usually [IconBtn]s. The title stays on the screen's
  /// centre line whatever is here — [NavigationToolbar] centres the middle
  /// across the full width and only shifts it when the sides would collide.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    // The accent follows the artwork when tinting is on; the bar eases to a
    // new tint rather than snapping on every track change.
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: Color.lerp(c.bg, c.accent, 0.14)),
      duration: const Duration(milliseconds: 700),
      curve: SunohMotion.ease,
      builder: (_, tint, child) => DecoratedBox(
        decoration: BoxDecoration(
          color: tint,
          border: Border(bottom: BorderSide(color: c.line)),
        ),
        child: child,
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          8,
          MediaQuery.paddingOf(context).top,
          8,
          0,
        ),
        child: SizedBox(
          height: 56,
          child: NavigationToolbar(
            middleSpacing: 8,
            leading: IconBtn(
              icon: RemixIcons.arrow_left_s_line,
              color: c.fg,
              onTap: () => context.pop(),
            ),
            middle: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SunohType.heading(fontSize: 16, color: c.fg),
            ),
            trailing: actions.isEmpty
                ? null
                : Row(mainAxisSize: MainAxisSize.min, children: actions),
          ),
        ),
      ),
    );
  }
}
