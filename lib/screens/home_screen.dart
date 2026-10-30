// Home — a greeting over the colour of whatever is playing, the Music /
// Podcasts chips, and the feed of whichever tab is open.
//
// The header is pinned. It starts transparent so the wash behind the top of
// the page shows through it, and turns solid — the page ground tinted a
// tenth toward the playing colour, with a hairline under it — once the feed
// has scrolled 40dp under it. A transparent bar over moving rows reads as
// the rows' text colliding with the greeting; a solid one from the start
// would cut the wash off at the chips.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remixicon/remixicon.dart';

import '../overlays/support_sheet.dart';
import '../providers/app_state_provider.dart';
import '../providers/palette_provider.dart';
import '../providers/update_provider.dart';
import '../router/router.dart';
import '../theme/tokens.dart';
import '../widgets/art_wash.dart';
import '../widgets/top_tabs.dart';
import '../widgets/ui.dart';
import '../widgets/update_sheet.dart';
// Tab implementations: Music (the /music/home feed) and Podcasts (backed by
// /podcasts/home via `podcastHomeProvider`, since v1.5.5).
import 'home_feed.dart';
import 'podcasts_tab.dart';

/// Scroll past which the header turns solid.
const double _kSolidAfter = 40;

/// Height of the wash at the top of the page.
const double _kWashHeight = 340;

const List<String> _kTabs = ['Music', 'Podcasts'];

/// Good morning / afternoon / evening / night, by the device's clock.
String _greeting(int hour) => hour < 5
    ? 'Good night'
    : hour < 12
    ? 'Good morning'
    : hour < 17
    ? 'Good afternoon'
    : 'Good evening';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  // Track which version we've already prompted for this app launch so
  // re-entering Home doesn't fire the dialog twice (e.g. user taps
  // Later, navigates away, comes back — should NOT re-prompt until
  // next launch).
  String? _promptedVersion;

  final _scroll = ScrollController();

  /// Whether the feed has scrolled under the header. A notifier rather than
  /// state: it flips twice per trip up and down the page, and only the
  /// header's ground listens to it.
  final _solid = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    final solid = _scroll.offset > _kSolidAfter;
    if (solid != _solid.value) _solid.value = solid;
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _solid.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;

    // Watch the update provider. When a non-null UpdateInfo lands AND
    // we haven't prompted for this exact version yet THIS session,
    // schedule the dialog for the next frame. (Can't show during
    // build — flutter forbids opening routes synchronously from a
    // widget's build method.)
    final updateInfo = ref.watch(availableUpdateProvider).asData?.value;
    if (updateInfo != null && _promptedVersion != updateInfo.version) {
      _promptedVersion = updateInfo.version;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showUpdateSheet(context, updateInfo);
      });
    }

    // Home owns its scrolling rather than sitting inside the shared
    // _RootScroll, because that is a SingleChildScrollView and a
    // SingleChildScrollView builds every one of its children. The music feed
    // is over twenty sections, each with its own strip of artwork, so a single
    // appStateProvider notification — the tint shifting back as you return
    // from an album, say — rebuilt all of them at once. As slivers only the
    // sections actually on screen get built. Slivers are also what lets the
    // header pin.
    //
    // A tab switch swaps the sliver below the header for a new one, and the
    // new tab's blocks play their own entrance — the fade the whole body used
    // to run on a switch would only have doubled it.
    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _ScrollingWash(scroll: _scroll),
        ),
        CustomScrollView(
          controller: _scroll,
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: _HomeHeader(
                inset: MediaQuery.paddingOf(context).top,
                greeting: _greeting(DateTime.now().hour),
                colors: c,
                tab: s.topTab,
                onTab: s.setTopTab,
                solid: _solid,
              ),
            ),
            switch (s.topTab) {
              'Podcasts' => SliverToBoxAdapter(child: PodcastsTab(colors: c)),
              _ => MusicTab(colors: c),
            },
            // Clears the mini player and nav bar, which the shell paints over
            // the last 156 logical pixels plus the system inset (shellClearance).
            SliverToBoxAdapter(
              child: SizedBox(height: shellClearance(context)),
            ),
          ],
        ),
      ],
    );
  }
}

/// The wash, behind the scroll view and moved with it.
///
/// It sits under the header as well as the hero, which no single sliver can
/// do once the header is the pinned first one: the header paints over the
/// slivers after it, and a sliver can only reach up under it by overflowing.
/// A translation per scroll frame is one layer moving; the gradient itself is
/// behind a repaint boundary and is not redrawn.
class _ScrollingWash extends StatelessWidget {
  const _ScrollingWash({required this.scroll});
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: scroll,
      builder: (_, child) => Transform.translate(
        offset: Offset(0, scroll.hasClients ? -scroll.offset : 0),
        child: child,
      ),
      child: const RepaintBoundary(child: PlayingArtWash(height: _kWashHeight)),
    );
  }
}

/// Status-bar inset, the greeting row, then the tab chips.
///
/// A persistent header has to state its height before it builds, so the two
/// rows are numbers here and the build below lays them out at exactly those
/// heights — the chips are 32 high with 4 above and 12 below.
class _HomeHeader extends SliverPersistentHeaderDelegate {
  _HomeHeader({
    required this.inset,
    required this.greeting,
    required this.colors,
    required this.tab,
    required this.onTab,
    required this.solid,
  });

  final double inset;
  final String greeting;
  final SunohColors colors;
  final String tab;
  final ValueChanged<String> onTab;
  final ValueNotifier<bool> solid;

  static const double _rowHeight = 56;
  static const double _tabsHeight = 48;

  double get _extent => inset + _rowHeight + _tabsHeight;

  @override
  double get minExtent => _extent;

  @override
  double get maxExtent => _extent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    final c = colors;
    return _HeaderGround(
      solid: solid,
      colors: c,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: inset),
          SizedBox(
            height: _rowHeight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      greeting,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SunohType.heading(fontSize: 26, color: c.fg),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Support sits beside Settings, not a scroll away inside
                  // it. A cup: in a music app a heart reads as Liked songs.
                  IconBtn(
                    icon: RemixIcons.cup_line,
                    color: c.fg,
                    onTap: () => showSupportSheet(context),
                  ),
                  const SizedBox(width: 8),
                  IconBtn(
                    icon: RemixIcons.settings_3_line,
                    color: c.fg,
                    onTap: () => context.openSettings(),
                  ),
                ],
              ),
            ),
          ),
          SunohTabs(
            tabs: _kTabs,
            active: tab,
            onChange: onTab,
            colors: c,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_HomeHeader old) =>
      old.inset != inset ||
      old.greeting != greeting ||
      old.colors != colors ||
      old.tab != tab ||
      old.solid != solid;
}

/// The header's ground: nothing at the top of the page, then the page colour
/// tinted toward what is playing, with a hairline beneath, once [solid].
///
/// The tint selects only the three things it depends on, so the position
/// tick and every unrelated app-state change pass it by. The hairline is a
/// zero-blur shadow rather than a border, so it hangs below the header
/// instead of taking a pixel from the rows inside it.
class _HeaderGround extends ConsumerWidget {
  const _HeaderGround({
    required this.solid,
    required this.colors,
    required this.child,
  });

  final ValueNotifier<bool> solid;
  final SunohColors colors;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (url, isLight, fallback) = ref.watch(
      appStateProvider.select(
        (s) => (s.currentApiSong?.artwork ?? '', s.isLight, s.resolvedAccent),
      ),
    );
    final palette = url.isEmpty
        ? null
        : ref.watch(artPaletteProvider(url)).value;
    final raw = palette?.accent ?? fallback;
    final tone = isLight ? lightAccentFor(raw) : raw;
    final ground = Color.lerp(colors.bg, tone, 0.10)!;
    return Stack(
      fit: StackFit.expand,
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: solid,
          builder: (_, on, _) => AnimatedOpacity(
            opacity: on ? 1 : 0,
            duration: SunohMotion.ui,
            curve: SunohMotion.ease,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: ground,
                boxShadow: [
                  BoxShadow(color: colors.line, offset: const Offset(0, 1)),
                ],
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
