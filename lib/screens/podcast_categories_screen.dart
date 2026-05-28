// Browse all PodcastIndex categories. Cards are accent-tinted squircle
// pills with a category glyph + name; the per-glyph mapping below
// gives News a microphone, Comedy a smiley, Sports a basketball, etc.
// — so the page reads as graphic-rich, not "112 tinted rectangles".

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';

import '../api/dto.dart';
import '../providers/app_state_provider.dart';
import '../providers/podcast_provider.dart';
import '../router/router.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';

/// 12-color curated palette used by [PodcastCategoryCard]. Each
/// category picks one deterministically by `category.id % 12`, so the
/// same category always wears the same color across renders. Hues are
/// saturated enough to read clearly on the near-black bg without
/// crossing into neon. Sanctioned hex literals (per the design-system
/// rule about not hardcoding colors outside the token layer — this is
/// a category-art palette, the same kind of exception we make for the
/// generated album-art palettes).
const _categoryPalette = <Color>[
  Color(0xFFE05656), // 0  · red — News, true crime
  Color(0xFFE07A3C), // 1  · orange — Comedy
  Color(0xFFD9A93C), // 2  · amber — Business
  Color(0xFF6FBF73), // 3  · green — Health
  Color(0xFF3FB7C7), // 4  · teal — Education
  Color(0xFF4A8FE0), // 5  · blue — Technology
  Color(0xFF8466DC), // 6  · violet — Philosophy / Society
  Color(0xFFCB5BB6), // 7  · pink — Arts
  Color(0xFFC36F4F), // 8  · brick — Religion, history
  Color(0xFF4F9F8F), // 9  · sea — Travel, nature
  Color(0xFFB36FB9), // 10 · mauve — Music, film
  Color(0xFF6FAB4F), // 11 · olive — Food, hobbies
];

class PodcastCategoriesScreen extends ConsumerWidget {
  const PodcastCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final accent = s.resolvedAccent;
    final async = ref.watch(podcastCategoriesProvider);
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
                      onTap: () => context.pop()),
                  const SizedBox(width: 6),
                  Text('Categories',
                      style: SunohType.heading(
                          fontSize: 24,
                          color: c.fg,
                          letterSpacing: -0.3)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              child: Text(
                  'Pick a category to discover podcasts in it.',
                  style:
                      SunohType.sans(fontSize: 13, color: c.fgMute)),
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
                    child: Text('Couldn’t load categories.\n$e',
                        textAlign: TextAlign.center,
                        style: SunohType.sans(
                            fontSize: 13, color: c.fgMute)),
                  ),
                ),
                data: (cats) => GridView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 140),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    // Same aspect ratio as the channel tile (180w / 64h),
                    // so the wide-gradient card fits cleanly with its
                    // title block + rotated icon on the right.
                    childAspectRatio: 180 / 64,
                  ),
                  itemCount: cats.length,
                  itemBuilder: (context, i) => PodcastCategoryCard(
                    category: cats[i],
                    colors: c,
                    accent: accent,
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

/// Wide rectangular category card — mirrors `_ChannelTile` (the music
/// home's Saavn "Browse" channel tiles): per-card gradient with title
/// in heading typography on the left, topic glyph rotated + tucked
/// off the right edge for dimensionality.
///
/// Each category gets a distinct seed color from `_categoryPalette`,
/// picked deterministically by `category.id % palette.length`. The
/// user's accent stays out of this — every category having the same
/// hue (just brightness variations on the accent) defeated the
/// purpose of having a Categories surface.
class PodcastCategoryCard extends StatelessWidget {
  const PodcastCategoryCard({
    super.key,
    required this.category,
    required this.colors,
    required this.accent,
  });
  final PodcastCategory category;
  final SunohColors colors;
  /// Kept for API compatibility (the preview strip on the Podcasts
  /// tab passes the user accent in), but no longer used for tinting —
  /// see [_categoryPalette] above.
  final Color accent;
  @override
  Widget build(BuildContext context) {
    final c = colors;
    final icon = _iconFor(category.name);
    final seed =
        _categoryPalette[category.id % _categoryPalette.length];
    return GestureDetector(
      onTap: () => context.openPodcastCategory(
          category.id.toString(),
          name: category.name),
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
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      category.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SunohType.heading(
                        fontSize: 13.5,
                        color: Colors.white,
                        letterSpacing: -0.1,
                        height: 1.15,
                      ),
                    ),
                  ),
                ),
              ),
              // Rotated topic glyph in a tinted square — mirrors the
              // channel tile's "artwork off the right edge" affordance,
              // but with a glyph instead since categories have no art.
              Transform.rotate(
                angle: 0.20,
                child: Transform.translate(
                  offset: const Offset(6, 4),
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon, color: Colors.white, size: 26),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Maps category names to a topical Solar icon. Falls back to a
  /// neutral tag glyph for anything not in the table.
  static IconData _iconFor(String name) {
    final n = name.toLowerCase();
    if (n.contains('news')) return SolarIconsBold.notebookMinimalistic;
    if (n.contains('comedy')) return SolarIconsBold.emojiFunnyCircle;
    if (n.contains('sport')) return SolarIconsBold.basketball;
    if (n.contains('tech')) return SolarIconsBold.cpu;
    if (n.contains('music')) return SolarIconsBold.musicNote;
    if (n.contains('film') || n.contains('tv') || n.contains('cinema')) {
      return SolarIconsBold.tv;
    }
    if (n.contains('education') || n.contains('learn')) {
      return SolarIconsBold.book;
    }
    if (n.contains('history')) return SolarIconsBold.book2;
    if (n.contains('busin') ||
        n.contains('career') ||
        n.contains('econom')) {
      return SolarIconsBold.caseMinimalistic;
    }
    if (n.contains('health') ||
        n.contains('fitness') ||
        n.contains('medic')) {
      return SolarIconsBold.dumbbellLargeMinimalistic;
    }
    if (n.contains('food') || n.contains('cook')) {
      return SolarIconsBold.cup;
    }
    if (n.contains('art') ||
        n.contains('design') ||
        n.contains('visual')) {
      return SolarIconsBold.paintRoller;
    }
    if (n.contains('travel')) return SolarIconsBold.planet;
    if (n.contains('religion') ||
        n.contains('spirit') ||
        n.contains('christ') ||
        n.contains('islam') ||
        n.contains('buddh') ||
        n.contains('hindu')) {
      return SolarIconsBold.starsLine;
    }
    if (n.contains('kids') || n.contains('famil') || n.contains('parent')) {
      return SolarIconsBold.usersGroupTwoRounded;
    }
    if (n.contains('crime') || n.contains('true')) {
      return SolarIconsBold.bag2;
    }
    if (n.contains('science') || n.contains('astro') || n.contains('biol')) {
      return SolarIconsBold.testTubeMinimalistic;
    }
    if (n.contains('philo') || n.contains('soc') || n.contains('cult')) {
      return SolarIconsBold.usersGroupRounded;
    }
    if (n.contains('govern') || n.contains('polit')) {
      return SolarIconsBold.buildings_3;
    }
    if (n.contains('game') || n.contains('video') || n.contains('hobb')) {
      return SolarIconsBold.gameboy;
    }
    return SolarIconsBold.tagHorizontal;
  }
}
