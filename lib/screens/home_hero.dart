// The home feed's first section, drawn as a row of large square artwork
// cards.
//
// The first section always had a "featured" treatment, but it was the same
// cover-and-caption tile as every row below it, only bigger, so the page had
// no point of arrival. These cards put the title on the artwork, snap one at
// a time, and leave the next one peeking past the right edge so the row says
// it scrolls without a hint.
//
// Square, because the artwork is. A landscape card (the prototype's) was
// tried and dropped: it cropped the lettering off most sleeves and put the
// title over half a word. 280dp leaves the next card peeking past the right
// edge on any phone. The artwork is a fifth larger than the card and drifts
// a little against the swipe; the drift stays inside that margin, so no edge
// ever shows. The scrim is dark in both themes for the same
// reason the text on it uses `SunohMedia`: a sleeve is as likely to be dark
// on the light palette as on the dark one.
//
// PERF: the drift is a `Transform` driven by the row's scroll controller
// through an `AnimatedBuilder`, so a swipe repaints only the artwork layer of
// the cards on screen. Each card sits in its own `RepaintBoundary`, and the
// page dots listen to a `ValueNotifier` that changes once per card, not once
// per frame.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dto.dart';
import '../providers/app_state_provider.dart';
import '../providers/palette_provider.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/cover_hero.dart';
import '../widgets/motion.dart';
import '../widgets/ui.dart';
import 'feed_motion.dart';
import 'feed_row.dart';
import 'feed_tiles.dart';
import 'home_hero_caption.dart';

/// Side of a card.
const double _kSide = 280;
const double _kGutter = 16;
const double _kGap = 10;

/// Artwork size as a share of the card's, in both directions so a square
/// sleeve stays square.
const double _kOverscan = 1.2;

/// How far the artwork drifts against the swipe, as a share of the distance
/// its card travels: one card's travel moves it 28dp, exactly the overscan
/// margin on each side.
const double _kDrift = _kSide * (_kOverscan - 1) / 2 / (_kSide + _kGap);

/// The size a card's art is drawn (and decoded) at: what a page opened from
/// the card draws the flying cover at until its own art has decoded.
const double kHeroArtSize = _kSide * _kOverscan;

class HomeHero extends StatefulWidget {
  const HomeHero({
    super.key,
    required this.items,
    required this.colors,
    required this.onTap,
    this.heroScope,
  });

  final List<FeedItem> items;
  final SunohColors colors;
  final ValueChanged<FeedItem> onTap;

  /// Where these cards are, for the tag their covers fly under
  /// (`feedHeroTag`). Null: nothing flies.
  final String? heroScope;

  @override
  State<HomeHero> createState() => _HomeHeroState();
}

class _HomeHeroState extends State<HomeHero> {
  final ScrollController _scroll = ScrollController();
  final ValueNotifier<int> _page = ValueNotifier(0);
  static const double _step = _kSide + _kGap;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    final page = (_scroll.offset / _step).round();
    if (page != _page.value) _page.value = page;
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    return Column(
      children: [
        SizedBox(
          height: _kSide,
          child: ListView.builder(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            physics: const SnapPhysics(extent: _step),
            // The last card's trailing gap plus this is the 16dp end gutter.
            padding: const EdgeInsets.only(
              left: _kGutter,
              right: _kGutter - _kGap,
            ),
            itemExtent: _step,
            itemCount: items.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.only(right: _kGap),
              child: _HeroCard(
                item: items[i],
                index: i,
                width: _kSide,
                step: _step,
                scroll: _scroll,
                heroTag: feedHeroTag(widget.heroScope, items, items[i]),
                onTap: () => widget.onTap(items[i]),
              ),
            ),
          ),
        ),
        if (items.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _Dots(
              count: items.length,
              page: _page,
              colors: widget.colors,
            ),
          ),
      ],
    );
  }
}

class _HeroCard extends ConsumerWidget {
  const _HeroCard({
    required this.item,
    required this.index,
    required this.width,
    required this.step,
    required this.scroll,
    required this.onTap,
    this.heroTag,
  });

  final FeedItem item;
  final int index;
  final double width;
  final double step;
  final ScrollController scroll;
  final VoidCallback onTap;
  final String? heroTag;

  /// How far, in cards, the row has travelled past this one. Zero until the
  /// controller is attached — `offset` throws before that.
  double _travel() => scroll.hasClients ? scroll.offset / step - index : 0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = item.artwork ?? '';
    final isLight = ref.watch(appStateProvider.select((s) => s.isLight));
    final raw = url.isEmpty
        ? null
        : ref.watch(artPaletteProvider(url)).value?.accent;
    // The card's own colour, themed like every artwork accent. Media ink
    // until the palette lands, which is the right ink on the scrim anyway.
    final tone = raw == null
        ? SunohMedia.ink
        : (isLight ? lightAccentFor(raw) : raw);
    final tag = labelFor(item.language ?? '');
    return Pressable(
      onTap: onTap,
      child: RepaintBoundary(
        child: squircleClip(
          radius: SunohRadius.card,
          child: SizedBox(
            width: width,
            height: width,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // The card's cover flies into the page it opens like any
                // other; the flight opens the drifting crop out to the whole
                // sleeve on the way.
                CoverHero(
                  tag: heroTag,
                  id: item.id,
                  imageUrl: item.artwork,
                  size: width,
                  radius: SunohRadius.card,
                  zoom: _kOverscan,
                  child: AnimatedBuilder(
                    animation: scroll,
                    builder: (_, child) => Transform.translate(
                      offset: Offset(_travel() * step * _kDrift, 0),
                      child: child,
                    ),
                    child: OverflowBox(
                      minWidth: width * _kOverscan,
                      maxWidth: width * _kOverscan,
                      minHeight: width * _kOverscan,
                      maxHeight: width * _kOverscan,
                      child: SunohArt(
                        id: item.id,
                        imageUrl: item.artwork,
                        size: width * _kOverscan,
                        radius: 0,
                        shadow: false,
                      ),
                    ),
                  ),
                ),
                const HeroCardScrim(),
                if (tag.isNotEmpty)
                  Positioned(left: 12, top: 12, child: HeroCardPill(text: tag)),
                Positioned(
                  left: 16,
                  right: 14,
                  bottom: 14,
                  // Tweened, so a palette arriving late eases in rather than
                  // snapping the button from ink to colour.
                  child: TweenAnimationBuilder<Color?>(
                    tween: ColorTween(end: tone),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOut,
                    builder: (_, t, _) =>
                        HeroCardCaption(item: item, tone: t ?? tone),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.page, required this.colors});
  final int count;
  final ValueNotifier<int> page;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: page,
      builder: (_, current, _) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: SunohMotion.arrive,
              margin: const EdgeInsets.symmetric(horizontal: 2.5),
              width: i == current ? 18 : 6,
              height: 3,
              decoration: squircleDecoration(
                radius: 1.5,
                color: i == current ? colors.fg : colors.fgMute,
              ),
            ),
        ],
      ),
    );
  }
}
