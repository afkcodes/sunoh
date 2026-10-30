// The three tabs' navigators, with the selected one faded in on a switch.
//
// `StatefulShellRoute.indexedStack` swaps tabs in a single frame, which made
// a tab change the one cut in an app where everything else moves. This keeps
// the same model — every branch stays alive and keeps its scroll position and
// stack — and only fades the newly selected branch in over 220 ms. Inactive
// branches are Offstage with tickers off, exactly as the indexed stack had
// them, so nothing hidden keeps animating or painting.

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class BranchFade extends StatefulWidget {
  const BranchFade({super.key, required this.index, required this.children});
  final int index;
  final List<Widget> children;

  @override
  State<BranchFade> createState() => _BranchFadeState();
}

class _BranchFadeState extends State<BranchFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: SunohMotion.tab,
    value: 1,
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _c,
    curve: SunohMotion.ease,
  );

  @override
  void didUpdateWidget(BranchFade old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          Offstage(
            offstage: i != widget.index,
            child: TickerMode(
              enabled: i == widget.index,
              child: i == widget.index
                  ? FadeTransition(opacity: _fade, child: widget.children[i])
                  : widget.children[i],
            ),
          ),
      ],
    );
  }
}
