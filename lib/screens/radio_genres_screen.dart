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

import '../providers/app_state_provider.dart';
import '../providers/radio_provider.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';
import 'radio_tab.dart' show GenreTile, GenreTileVariant;

// Tile design + per-genre color/icon mapping live in `radio_tab.dart`
// (`GenreTile`, `genreColorFor`, `genreIconFor`) so the same genre
// always wears the same look whether it's rendered in the preview
// strip on the Radio tab or the full grid here.

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
                    padding: const EdgeInsets.fromLTRB(32, 32, 32, 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: s.resolvedAccent.withValues(alpha: 0.16),
                          ),
                          alignment: Alignment.center,
                          child: Icon(SolarIconsOutline.wifiRouterRound,
                              color: s.resolvedAccent, size: 24),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Couldn’t load genres',
                          style: SunohType.heading(
                              fontSize: 15,
                              color: c.fg,
                              letterSpacing: -0.2),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Check your connection and try again.',
                          textAlign: TextAlign.center,
                          style: SunohType.sans(
                              fontSize: 12.5, color: c.fgMute),
                        ),
                        const SizedBox(height: 16),
                        GestureDetector(
                          onTap: () =>
                              ref.invalidate(radioGenresProvider),
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            decoration: squircleDecoration(
                              radius: 999,
                              color: s.resolvedAccent
                                  .withValues(alpha: 0.14),
                              borderColor: s.resolvedAccent
                                  .withValues(alpha: 0.32),
                            ),
                            child: Text(
                              'Try again',
                              style: SunohType.sans(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: s.resolvedAccent,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (genres) => GridView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 140),
                  // 4:3 tiles in two columns — chunky enough for the
                  // bold heading + corner glyph to read, taller than
                  // the old wide-pill aspect so each tile feels like
                  // its own card rather than a row in a list.
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 4 / 3,
                  ),
                  itemCount: genres.length,
                  itemBuilder: (context, i) => GenreTile(
                    facet: genres[i],
                    variant: GenreTileVariant.card,
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

