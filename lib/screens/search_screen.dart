// Search — input + debounced live results from /music/search?type=all.
// Browse view (recent + genre tiles) takes over when the query is empty.
//
// The screen owns its scrolling rather than sitting inside the router's
// `_RootScroll`, for two reasons that turn out to be the same reason. The
// search field and the section-jump pills have to stay put while results
// move under them — pills that scroll away are a shortcut you can only use
// before you need it — and pinning anything at all requires slivers. Slivers
// then also make the results build as they are reached, where the shared
// `SingleChildScrollView` laid out every row of every section at once.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../api/dto.dart';
import '../providers/app_state_provider.dart';
import '../router/deep_links.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';
import 'search_browse.dart';
import 'search_results.dart';

/// Debounce window between the user typing and us actually firing the
/// `/music/search` request. 280 ms feels responsive for mobile typing
/// without spamming the API on every keystroke.
const _kDebounce = Duration(milliseconds: 280);

/// The pinned header's two parts. Kept as numbers because a persistent
/// header has to state its height before it builds — it cannot measure the
/// field and the pills and then report what it found.
const double _kFieldExtent = 78; // 16 + 52 + 10
const double _kPillsExtent = 44; // 36 + 8

/// A short fade below the pinned block.
///
/// Results pass underneath it, and against a flat edge that reads as rows
/// being sliced in half rather than as content going behind something. The
/// fade is part of the header's own height so nothing has to overlap.
const double _kHeaderFade = 14;

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final controller = TextEditingController();
  // Focus node owned by the screen so the back-button handler can unfocus
  // the search field. Without this, system back on a focused field punts
  // straight to "exit app" (the Search tab is at the root of its branch
  // navigator) instead of just dismissing the keyboard.
  final _searchFocus = FocusNode();
  String q = '';
  // The debounced query — what we actually feed `searchProvider`. Empty
  // string means "don't search yet" (browse view stays up).
  String _activeQuery = '';
  Timer? _debounce;
  // GlobalKeys per section heading, persisted across rebuilds so the
  // section-pills row can ensureVisible the right slot. Cleared on
  // `_clear()` to release keys for headings that no longer appear.
  final Map<String, GlobalKey> _sectionKeys = {};
  final _scroll = ScrollController();
  GlobalKey _keyForSection(String heading) =>
      _sectionKeys.putIfAbsent(heading, GlobalKey.new);

  @override
  void initState() {
    super.initState();
    // Rebuild on focus change so `PopScope.canPop` reflects the current
    // keyboard state. Cheap — just toggles canPop true/false.
    _searchFocus.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    controller.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    setState(() => q = v);
    _debounce?.cancel();
    final trimmed = v.trim();
    if (trimmed.isEmpty) {
      if (_activeQuery.isNotEmpty) setState(() => _activeQuery = '');
      return;
    }
    _debounce = Timer(_kDebounce, () {
      if (!mounted) return;
      if (trimmed == _activeQuery) return;
      setState(() => _activeQuery = trimmed);
    });
  }

  void _clear() {
    _debounce?.cancel();
    controller.clear();
    _sectionKeys.clear();
    setState(() {
      q = '';
      _activeQuery = '';
    });
  }

  /// Enter, or a tap on a recent search: run the query now rather than
  /// waiting out the debounce.
  void _submit(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) {
      ref.read(appStateProvider).pushSearchRecent(trimmed);
    }
    setState(() => _activeQuery = trimmed);
  }

  /// A recent search, picked from the browse view.
  void _useQuery(String value) {
    controller.text = value;
    setState(() => q = value);
    _submit(value);
  }

  /// Animated scroll so the section under [heading] lands roughly a
  /// third of the way down the viewport. `Scrollable.ensureVisible`
  /// walks the closest `Scrollable` ancestor — works with the router-
  /// level `_RootScroll` SingleChildScrollView wrapping this screen,
  /// no scroll-controller plumbing needed.
  void _jumpToSection(String heading) {
    final ctx = _sectionKeys[heading]?.currentContext;
    if (ctx == null) return;
    // The header is pinned over the list, and `ensureVisible` knows nothing
    // about that — it aligns within the whole viewport, so a section put near
    // the top lands underneath the field. Push the target down by exactly the
    // header's height, plus a little air, expressed as the fraction of the
    // viewport that is.
    final viewport = _scroll.hasClients
        ? _scroll.position.viewportDimension
        : 0.0;
    // Pills are the only way here, and pills mean the header is at full
    // height.
    final clear = _headerExtent(withPills: true) + 12;
    final alignment = viewport <= clear
        ? 0.25
        : (clear / viewport).clamp(0.0, 0.4);
    Scrollable.ensureVisible(
      ctx,
      alignment: alignment,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  /// Height of the pinned header: the field, plus the pills when there are
  /// enough sections to be worth jumping between.
  double _headerExtent({required bool withPills}) =>
      _kFieldExtent + (withPills ? _kPillsExtent : 0) + _kHeaderFade;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    // Listen for a deep-link query handed off by DeepLinkRouter. We can't
    // touch the provider in initState (the screen may not be the active tab
    // yet at cold-start), so consume it on every build — once consumed it
    // stays null until the next deep link arrives.
    ref.listen<String?>(pendingSearchProvider, (_, next) {
      if (next == null || next.isEmpty) return;
      final pending = ref.read(pendingSearchProvider.notifier).consume();
      if (pending == null) return;
      controller.text = pending;
      _debounce?.cancel();
      ref.read(appStateProvider).pushSearchRecent(pending);
      setState(() {
        q = pending;
        _activeQuery = pending;
      });
    });

    final hasQuery = q.trim().isNotEmpty;
    final hasFocus = _searchFocus.hasFocus;
    // The pills belong to the results, so they exist only once a search has
    // come back with more than one section to jump between.
    final sections = hasQuery && _activeQuery.isNotEmpty
        ? watchSearch(ref, _activeQuery).sections
        : const <HomeSection>[];
    final pills = sections.length > 1 ? sections : null;

    // Back-button policy on this tab:
    //   1. Keyboard up → unfocus (dismiss keyboard).
    //   2. Query typed → clear back to the browse view.
    //   3. Otherwise → let the system handle it (which exits the app since
    //      Search is at the root of its branch navigator).
    // Without this, back from a focused search field punted straight to
    // "exit app" — really annoying.
    final intercept = hasFocus || hasQuery;

    return PopScope(
      canPop: !intercept,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (hasFocus) {
          _searchFocus.unfocus();
          return;
        }
        if (hasQuery) _clear();
      },
      // The status bar inset goes on the scroll view, not on the first sliver.
      // Put it on the sliver and it scrolls away with it — leaving the pinned
      // header to pin at y=0, under the clock and the battery.
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          controller: _scroll,
          slivers: [
            SliverToBoxAdapter(
              // The title scrolls away. The field directly beneath it already
              // says what the screen is, and keeping it would cost this much
              // of every screenful of results for the rest of the session.
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Text(
                  'Search',
                  style: SunohType.heading(
                    fontSize: 28,
                    color: c.fg,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _SearchHeader(
                extent: _headerExtent(withPills: pills != null),
                colors: c,
                controller: controller,
                focus: _searchFocus,
                showClear: q.isNotEmpty,
                onChanged: _onChanged,
                onSubmitted: _submit,
                onClear: _clear,
                pills: pills,
                onJumpToSection: _jumpToSection,
              ),
            ),
            if (!hasQuery)
              SearchBrowse(colors: c, onPickRecent: _useQuery)
            else
              SearchResults(
                query: _activeQuery,
                colors: c,
                sectionKey: _keyForSection,
                onPlay: (song) =>
                    s.playApiSong(song, sourceLabel: 'SEARCH · $_activeQuery'),
              ),
            // Clears the mini player and the nav bar.
            const SliverToBoxAdapter(child: SizedBox(height: 140)),
          ],
        ),
      ),
    );
  }
}

/// The pinned block: the search field, and the jump pills when results have
/// come back with more than one section.
///
/// Its height changes when the pills appear, which a persistent header is
/// allowed to do as long as [shouldRebuild] says so — otherwise the list keeps
/// reserving the old extent and the first section hides underneath.
class _SearchHeader extends SliverPersistentHeaderDelegate {
  _SearchHeader({
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

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapped) {
    final c = colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Opaque, because results scroll underneath: anything translucent
        // here would show them sliding behind the field.
        ColoredBox(
          color: c.bg,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                child: Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: squircleDecoration(
                    radius: 14,
                    color: c.surface,
                    borderColor: c.line,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        SolarIconsOutline.magnifier,
                        size: 19,
                        color: c.fgMute,
                      ),
                      const SizedBox(width: 12),
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
                            hintText: 'Artists, songs, podcasts, audiobooks…',
                            hintStyle: SunohType.sans(
                              fontSize: 15,
                              color: c.fgMute,
                            ),
                          ),
                        ),
                      ),
                      if (showClear)
                        GestureDetector(
                          onTap: onClear,
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: c.fg.withValues(alpha: 0.08),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              SolarIconsOutline.closeCircle,
                              size: 14,
                              color: c.fg,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (pills != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SectionPills(
                    sections: pills!,
                    colors: c,
                    onTap: onJumpToSection,
                  ),
                ),
            ],
          ),
        ),
        // Drawn by the header rather than laid over the list, so it travels
        // with the header and adds nothing to the scrolling content. Sits
        // outside the opaque box above — it has to fade into something.
        SizedBox(
          height: _kHeaderFade,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [c.bg, c.bg.withValues(alpha: 0)],
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  bool shouldRebuild(_SearchHeader old) =>
      old.extent != extent ||
      old.colors != colors ||
      old.showClear != showClear ||
      old.pills != pills;
}
