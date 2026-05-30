// Browse every radio genre. Grid of `_GenreCard`s, count badge,
// accent-tinted seed palette so the wall doesn't read as a uniform
// block. Identical structure to PodcastCategoriesScreen — different
// data source.
//
// Tapping a genre opens `radio_genre_screen.dart` with the stations
// filtered to that genre.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';

import '../api/dto.dart';
import '../providers/app_state_provider.dart';
import '../providers/radio_provider.dart';
import '../router/router.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';
import 'radio_tab.dart' show titleCase;

/// 12-color curated palette — same set used by
/// `podcast_categories_screen.dart`. Each genre picks one
/// deterministically by `value.hashCode % 12`, so the same genre always
/// wears the same color across renders. Sanctioned hex literals (per
/// the design-system rule about palettes being an exception to the
/// token-only color rule).
const _genrePalette = <Color>[
  Color(0xFFE05656),
  Color(0xFFE07A3C),
  Color(0xFFD9A93C),
  Color(0xFF6FBF73),
  Color(0xFF3FB7C7),
  Color(0xFF4A8FE0),
  Color(0xFF8466DC),
  Color(0xFFCB5BB6),
  Color(0xFFC36F4F),
  Color(0xFF4F9F8F),
  Color(0xFFB36FB9),
  Color(0xFF6FAB4F),
];

class RadioGenresScreen extends ConsumerWidget {
  const RadioGenresScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final async = ref.watch(radioGenresProvider);
    return ColoredBox(
      color: c.bg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  IconBtn(
                    icon: SolarIconsOutline.altArrowLeft,
                    color: c.fg,
                    size: 22,
                    onTap: () => context.pop(),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Genres',
                    style: SunohType.heading(
                      fontSize: 24,
                      color: c.fg,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              child: Text(
                'Pick a genre to discover live stations.',
                style: SunohType.sans(fontSize: 13, color: c.fgMute),
              ),
            ),
            Expanded(
              child: async.when(
                loading: () => Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: c.fgDim),
                  ),
                ),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Couldn’t load genres.\n$e',
                      textAlign: TextAlign.center,
                      style:
                          SunohType.sans(fontSize: 13, color: c.fgMute),
                    ),
                  ),
                ),
                data: (genres) => GridView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 140),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 180 / 64,
                  ),
                  itemCount: genres.length,
                  itemBuilder: (context, i) => _GenreCard(
                    facet: genres[i],
                    colors: c,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GenreCard extends StatelessWidget {
  const _GenreCard({required this.facet, required this.colors});
  final RadioFacet facet;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final seed = _genrePalette[facet.value.hashCode.abs() % _genrePalette.length];
    return GestureDetector(
      onTap: () => context.openRadioGenre(facet.value),
      behavior: HitTestBehavior.opaque,
      child: squircleClip(
        radius: 10,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Color.lerp(c.bg, seed, 0.62)!,
                Color.lerp(c.bg, seed, 0.22)!,
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  titleCase(facet.value),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SunohType.heading(
                    fontSize: 14,
                    color: Colors.white,
                    letterSpacing: -0.1,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${facet.count} stations',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SunohType.sans(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.75),
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
