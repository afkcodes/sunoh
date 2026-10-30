// The frame every detail page shares: a scroll host with a pinned bar, and
// the big title the hero-less list pages use instead of a hero. The hero,
// the actions row and its play disc are in detail_hero.dart.
//
// Album, playlist, show, artist and the library's own lists all
// used to carry a private copy of the same sticky header and hero, and the
// copies had drifted — different thresholds, different fades, a back button
// that was hidden on some and not on others. One frame means one behaviour:
// the bar is transparent over the hero and turns solid, tinted with the
// page's colour, once the hero has scrolled under it.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:remixicon/remixicon.dart';

import '../theme/tokens.dart';
import '../widgets/motion.dart';
import '../widgets/ui.dart';

/// Scroll offset past which the bar turns solid and shows its title. Read off
/// the prototype: it is where a 236 cover's bottom edge passes under the bar.
const double kDetailSolidAt = 230;

/// Height of the bar's row, below the status-bar inset.
const double kDetailBarHeight = 56;

/// Colour changes taken from artwork cross-fade over this long rather than
/// snapping, so a palette that resolves late reads as the page settling.
const Duration kArtColourTween = Duration(milliseconds: 700);

// Past this nothing in a hero moves any more: the cover has faded out by 320
// and the artist photo is off-screen by 400. Capping the notifier here stops
// the hero rebuilding on every frame of a long scroll down a track list.
const double _kParallaxRange = 420;

/// One icon in the bar's right-hand slot.
class BarAction {
  const BarAction(this.icon, this.onTap, {this.size = 22});
  final IconData icon;
  final VoidCallback onTap;
  final double size;
}

/// A [ValueListenable] that never changes — the bar on a loading or error
/// page, which has nothing to scroll.
class FixedFlag implements ValueListenable<bool> {
  const FixedFlag(this.value);
  @override
  final bool value;
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}

/// Scroll host for a detail page. [builder] returns the page's slivers and is
/// handed the clamped scroll offset, which the heroes use for parallax.
class DetailPage extends StatefulWidget {
  const DetailPage({
    super.key,
    required this.colors,
    required this.colour,
    required this.title,
    required this.builder,
    this.actions = const [],
    this.overMedia = false,
    this.solidAt = kDetailSolidAt,
    this.controller,
  });

  final SunohColors colors;

  /// The page's own colour — its cover's palette accent, already themed.
  final Color colour;
  final String title;
  final List<Widget> Function(ValueListenable<double> scroll) builder;
  final List<BarAction> actions;

  /// True when the hero is a photo running up under the bar (the artist page),
  /// so the bar's icons take media ink until it turns solid.
  final bool overMedia;
  final double solidAt;

  /// Supplied by a page that also needs to watch its own scroll position (the
  /// podcast show, which loads more episodes near the end). Not disposed here.
  final ScrollController? controller;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  late final ScrollController _ctrl = widget.controller ?? ScrollController();
  final ValueNotifier<double> _scroll = ValueNotifier<double>(0);
  final ValueNotifier<bool> _solid = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onScroll);
    if (widget.controller == null) _ctrl.dispose();
    _scroll.dispose();
    _solid.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_ctrl.hasClients) return;
    final o = _ctrl.offset;
    final v = o.clamp(0.0, _kParallaxRange);
    if ((v - _scroll.value).abs() >= 0.5) _scroll.value = v;
    _solid.value = o > widget.solidAt;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    return ColoredBox(
      color: c.bg,
      // Tight constraints all the way down: a loose parent (a route
      // transition) once let the Stack size itself to the scroll view's
      // unbounded height, which rendered as rows repeating forever.
      child: SizedBox.expand(
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomScrollView(
                controller: _ctrl,
                slivers: [
                  ...widget.builder(_scroll),
                  // Clears the mini player and the tab bar.
                  SliverToBoxAdapter(
                    child: SizedBox(height: shellClearance(context)),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: DetailBar(
                colors: c,
                colour: widget.colour,
                title: widget.title,
                solid: _solid,
                actions: widget.actions,
                overMedia: widget.overMedia,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The pinned bar: back, a centred title that rises in once the page has
/// scrolled, and up to two actions. Transparent over the hero; solid — the
/// page colour at 14% over the ground, with a bottom line — once [solid].
class DetailBar extends StatelessWidget {
  const DetailBar({
    super.key,
    required this.colors,
    required this.colour,
    required this.title,
    required this.solid,
    this.actions = const [],
    this.overMedia = false,
  });

  final SunohColors colors;
  final Color colour;
  final String title;
  final ValueListenable<bool> solid;
  final List<BarAction> actions;
  final bool overMedia;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final inset = MediaQuery.paddingOf(context).top;
    final fill = Color.lerp(c.bg, colour, 0.14)!;
    return ValueListenableBuilder<bool>(
      valueListenable: solid,
      builder: (context, on, _) => SizedBox(
        height: inset + kDetailBarHeight,
        child: Stack(
          children: [
            // The fill ignores pointers so a drag that starts on the bar
            // still scrolls the page, as it would on a sticky header.
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedContainer(
                  duration: SunohMotion.ui,
                  curve: SunohMotion.ease,
                  decoration: BoxDecoration(
                    color: on ? fill : fill.withValues(alpha: 0),
                    border: Border(
                      bottom: BorderSide(
                        color: on ? c.line : c.line.withValues(alpha: 0),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(8, inset, 8, 0),
              child: TweenAnimationBuilder<Color?>(
                tween: ColorTween(
                  end: overMedia && !on ? SunohMedia.ink : c.fg,
                ),
                duration: SunohMotion.ui,
                builder: (context, ink, _) => _row(context, ink ?? c.fg, on),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, Color ink, bool on) {
    return SizedBox(
      height: kDetailBarHeight,
      child: Row(
        children: [
          IconBtn(
            icon: RemixIcons.arrow_left_s_line,
            color: ink,
            onTap: () => context.pop(),
          ),
          // Balance a two-action right side so the title stays centred.
          if (actions.length > 1) const SizedBox(width: 40),
          Expanded(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: on ? 1 : 0,
                duration: SunohMotion.ui,
                child: AnimatedSlide(
                  // ~6px on a 16px title line.
                  offset: on ? Offset.zero : const Offset(0, 0.3),
                  duration: SunohMotion.ui,
                  curve: SunohMotion.ease,
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: SunohType.heading(fontSize: 16, color: ink),
                  ),
                ),
              ),
            ),
          ),
          for (final a in actions)
            IconBtn(icon: a.icon, color: ink, size: a.size, onTap: a.onTap),
          if (actions.isEmpty) const SizedBox(width: 40),
        ],
      ),
    );
  }
}

/// A page's own title, for the list pages that have no hero (Recently
/// played, Downloads, a "See all"). The bar's title takes over once it has
/// scrolled away.
class PageTitle extends StatelessWidget {
  const PageTitle({
    super.key,
    required this.colors,
    required this.title,
    this.meta,
    this.trailing,
  });

  final SunohColors colors;
  final String title;
  final String? meta;
  final Widget? trailing;

  /// Scroll offset at which the big title has gone under the bar.
  static const double solidAt = 40;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.paddingOf(context).top;
    final m = meta ?? '';
    return Padding(
      padding: EdgeInsets.fromLTRB(16, inset + kDetailBarHeight, 16, 14),
      child: FadeSlideIn(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: SunohType.heading(fontSize: 26, color: colors.fg),
                  ),
                  if (m.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      m,
                      style: SunohType.mono(fontSize: 13, color: colors.fgDim),
                    ),
                  ],
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// A list item that plays the page entrance once and is then kept alive, so
/// scrolling it out of a lazy list and back does not replay the fade.
class Entrance extends StatefulWidget {
  const Entrance({super.key, required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FadeSlideIn(index: widget.index, child: widget.child);
  }
}

/// Free text under a list — an album's description, a show's notes.
class DetailNote extends StatelessWidget {
  const DetailNote({super.key, required this.colors, required this.text});
  final SunohColors colors;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 30, 16, 0),
      child: Text(
        text,
        style: SunohType.sans(fontSize: 13, color: colors.fgDim, height: 1.5),
      ),
    );
  }
}

/// " · "-joined meta line from whichever parts are present.
String joinMeta(Iterable<String?> parts) => parts
    .where((p) => p != null && p.trim().isNotEmpty)
    .map((p) => p!.trim())
    .join(' · ');

/// "1 h 5 min" / "42 min" — a list's running time.
String hoursMinutes(int seconds) {
  final m = (seconds / 60).round();
  return m >= 60 ? '${m ~/ 60} h ${m % 60} min' : '$m min';
}
