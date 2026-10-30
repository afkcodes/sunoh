// The detail pages' loading state: the page's own shape, breathing.
//
// Split out of detail_screens.dart (443 lines), which wires responses to
// pages; this is what stands in for a page until its response lands.

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../widgets/cover_hero.dart';
import '../widgets/ui.dart';
import 'detail_chrome.dart';
import 'detail_hero.dart';

/// Placeholder track rows: enough to run off the bottom of a phone, as the
/// real list would. Title and subtitle widths vary so the rows read as a list
/// of songs rather than a striped block.
const List<(double, double)> _kRows = [
  (180, 110),
  (140, 90),
  (205, 120),
  (160, 100),
  (190, 84),
  (130, 112),
  (170, 96),
  (150, 104),
];

/// A cover (or, [round], the artist's photo block), the title lines, the
/// actions row and the track rows under it, so the page does not change
/// shape when the response lands. The songs arrive last, so their rows are
/// the part of the page most often seen as a skeleton.
class DetailLoading extends StatelessWidget {
  const DetailLoading({
    super.key,
    required this.colors,
    this.round = false,
    this.hero,
  });
  final SunohColors colors;
  final bool round;

  /// The tapped cover, shown where the page's cover will be so it can fly in
  /// before the page has loaded. Outside the pulse: it is the real art.
  final CoverHeroRef? hero;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final top = MediaQuery.paddingOf(context).top + kDetailBarHeight + 8;
    return ColoredBox(
      color: c.bg,
      child: Stack(
        children: [
          Pulse(
            // Never scrolls: it only lets the rows run past the bottom edge
            // without an overflow.
            child: SingleChildScrollView(
              primary: false,
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ..._cover(top),
                  const _Titles(),
                  const _Actions(),
                  const SizedBox(height: 8),
                  for (final (title, sub) in _kRows)
                    _TrackRow(title: title, subtitle: sub),
                ],
              ),
            ),
          ),
          if (hero != null && !round)
            Positioned(
              top: top,
              left: 0,
              right: 0,
              child: Center(
                child: DetailCover(
                  id: hero!.id,
                  imageUrl: hero!.imageUrl,
                  hero: hero,
                ),
              ),
            ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: DetailBar(
              colors: c,
              colour: c.bg,
              title: '',
              solid: const FixedFlag(false),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _cover(double top) => [
    if (round)
      const SkeletonBar(height: 360, width: double.infinity, radius: 0)
    else ...[
      SizedBox(height: top),
      // Held clear while the real cover sits on top of it.
      if (hero == null)
        const Center(
          child: SkeletonBar(
            height: DetailCover.size,
            width: DetailCover.size,
            radius: SunohRadius.cover,
          ),
        )
      else
        const SizedBox(height: DetailCover.size),
    ],
  ];
}

class _Titles extends StatelessWidget {
  const _Titles();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.fromLTRB(16, 22, 16, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SkeletonBar(height: 26, width: 200),
        SizedBox(height: 12),
        SkeletonBar(height: 14, width: 130),
        SizedBox(height: 8),
        SkeletonBar(height: 12, width: 180),
      ],
    ),
  );
}

/// DetailActions' shape: icons on the left, shuffle and the 56 play disc on
/// the right, at the same padding.
class _Actions extends StatelessWidget {
  const _Actions();

  static Widget _icon() => const SizedBox.square(
    dimension: 40,
    child: Center(child: SkeletonBar(height: 24, width: 24, radius: 12)),
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 12, 16, 0),
    child: Row(
      spacing: 4,
      children: [
        _icon(),
        _icon(),
        const Spacer(),
        _icon(),
        const SkeletonBar(height: 56, width: 56, radius: 28),
      ],
    ),
  );
}

/// DetailTrackRow's shape: 48 art, title over subtitle, a duration.
class _TrackRow extends StatelessWidget {
  const _TrackRow({required this.title, required this.subtitle});
  final double title;
  final double subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Row(
      children: [
        const SkeletonBar(height: 48, width: 48, radius: SunohRadius.row),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBar(height: 14, width: title),
              const SizedBox(height: 7),
              SkeletonBar(height: 12, width: subtitle),
            ],
          ),
        ),
        const SkeletonBar(height: 12, width: 30),
      ],
    ),
  );
}
