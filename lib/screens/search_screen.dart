// Search — input + debounced live results from /music/search?type=all.
// Browse view (recent + trending + browse-all tiles) takes over when the
// query is empty.
//
// The screen owns its scrolling rather than sitting inside the router's
// `_RootScroll`, for two reasons that turn out to be the same reason. The
// title, the field and the section-jump chips have to stay put while results
// move under them — chips that scroll away are a shortcut you can only use
// before you need it — and pinning anything at all requires slivers. Slivers
// then also make the results build as they are reached, where the shared
// `SingleChildScrollView` laid out every row of every section at once.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dto.dart';
import '../providers/app_state_provider.dart';
import '../router/deep_links.dart';
import '../widgets/ui.dart';
import 'search_browse.dart';
import 'search_header.dart';
import 'search_outcome.dart';
import 'search_results.dart';

/// Debounce window between the user typing and us actually firing the
/// `/music/search` request. 280 ms feels responsive for mobile typing
/// without spamming the API on every keystroke.
const _kDebounce = Duration(milliseconds: 280);

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
    // Chips are the only way here, and chips mean the header is at full
    // height.
    final clear = SearchHeader.extentFor(withChips: true) + 12;
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
            SliverPersistentHeader(
              pinned: true,
              delegate: SearchHeader(
                extent: SearchHeader.extentFor(withChips: pills != null),
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
                // A new State per query, so each query's results enter anew.
                key: ValueKey(_activeQuery),
                query: _activeQuery,
                colors: c,
                sectionKey: _keyForSection,
                onPlay: (song) =>
                    s.playApiSong(song, sourceLabel: 'SEARCH · $_activeQuery'),
              ),
            // Clears the mini player and the nav bar.
            SliverToBoxAdapter(
              child: SizedBox(height: shellClearance(context)),
            ),
          ],
        ),
      ),
    );
  }
}
