// Browse all PodcastIndex categories as the prototype's browse grid: two
// columns of 96-tall tiles (see CategoryTile). Each category wears a colour
// from the table below and a topic glyph from the name map — News a
// notebook, Comedy a smiley, Sports a basketball — so the page reads as
// graphic-rich, not "112 tinted rectangles".

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remixicon/remixicon.dart';

import '../api/dto.dart';
import '../providers/app_state_provider.dart';
import '../providers/podcast_provider.dart';
import '../router/router.dart';
import '../theme/tokens.dart';
import '../widgets/motion.dart';
import 'category_tile.dart';
import 'sub_page_bar.dart';

/// 12-color curated palette used by [PodcastCategoryCard]. Each
/// category picks one deterministically by `category.id % 12`, so the
/// same category always wears the same color across renders. Hues are
/// saturated enough to hold their own under the tile's dark scrim without
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SubPageBar(title: 'Categories', colors: c),
          FadeSlideIn(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              child: Text(
                'Pick a category to discover podcasts in it.',
                style: SunohType.sans(fontSize: 14, color: c.fgDim),
              ),
            ),
          ),
          Expanded(
            child: async.when(
              loading: () => Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: c.fgDim,
                  ),
                ),
              ),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Couldn’t load categories.\n$e',
                    textAlign: TextAlign.center,
                    style: SunohType.sans(fontSize: 13, color: c.fgMute),
                  ),
                ),
              ),
              // The grid arrives as one block: staggering its tiles would
              // replay their entrance each time a scroll brings them back.
              data: (cats) => FadeSlideIn(
                index: 1,
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 140),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    mainAxisExtent: 96,
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
          ),
        ],
      ),
    );
  }
}

/// One category as a browse tile ([CategoryTile]), sized by whatever holds
/// it: the 96-tall grid here, the Podcasts tab's 64-tall preview rows there.
///
/// Each category gets a distinct colour from `_categoryPalette`, picked
/// deterministically by `category.id % palette.length`. The user's accent
/// stays out of this — every category having the same hue (just brightness
/// variations on the accent) defeated the purpose of having a Categories
/// surface.
class PodcastCategoryCard extends StatelessWidget {
  const PodcastCategoryCard({
    super.key,
    required this.category,
    required this.colors,
    required this.accent,
  });
  final PodcastCategory category;

  /// Kept for API compatibility with the Podcasts tab, which passes both in.
  /// The tile draws in its category colour and the media ink in either theme,
  /// so neither the app palette nor the accent reaches it.
  final SunohColors colors;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return CategoryTile(
      title: category.name,
      color: _categoryPalette[category.id % _categoryPalette.length],
      icon: _iconFor(category.name),
      onTap: () => context.openPodcastCategory(
        category.id.toString(),
        name: category.name,
      ),
    );
  }

  /// Maps category names to a topical Remix icon. Falls back to a
  /// neutral tag glyph for anything not in the table.
  static IconData _iconFor(String name) {
    final n = name.toLowerCase();
    if (n.contains('news')) return RemixIcons.book_2_fill;
    if (n.contains('comedy')) return RemixIcons.emotion_laugh_fill;
    if (n.contains('sport')) return RemixIcons.basketball_fill;
    if (n.contains('tech')) return RemixIcons.cpu_fill;
    if (n.contains('music')) return RemixIcons.music_fill;
    if (n.contains('film') || n.contains('tv') || n.contains('cinema')) {
      return RemixIcons.tv_2_fill;
    }
    if (n.contains('education') || n.contains('learn')) {
      return RemixIcons.book_fill;
    }
    if (n.contains('history')) return RemixIcons.book_open_fill;
    if (n.contains('busin') || n.contains('career') || n.contains('econom')) {
      return RemixIcons.briefcase_4_fill;
    }
    if (n.contains('health') || n.contains('fitness') || n.contains('medic')) {
      return RemixIcons.boxing_fill;
    }
    if (n.contains('food') || n.contains('cook')) {
      return RemixIcons.trophy_fill;
    }
    if (n.contains('art') || n.contains('design') || n.contains('visual')) {
      return RemixIcons.paint_fill;
    }
    if (n.contains('travel')) return RemixIcons.planet_fill;
    if (n.contains('religion') ||
        n.contains('spirit') ||
        n.contains('christ') ||
        n.contains('islam') ||
        n.contains('buddh') ||
        n.contains('hindu')) {
      return RemixIcons.sparkling_2_fill;
    }
    if (n.contains('kids') || n.contains('famil') || n.contains('parent')) {
      return RemixIcons.group_fill;
    }
    if (n.contains('crime') || n.contains('true')) {
      return RemixIcons.shopping_bag_3_fill;
    }
    if (n.contains('science') || n.contains('astro') || n.contains('biol')) {
      return RemixIcons.test_tube_fill;
    }
    if (n.contains('philo') || n.contains('soc') || n.contains('cult')) {
      return RemixIcons.team_fill;
    }
    if (n.contains('govern') || n.contains('polit')) {
      return RemixIcons.building_2_fill;
    }
    if (n.contains('game') || n.contains('video') || n.contains('hobb')) {
      return RemixIcons.gamepad_fill;
    }
    return RemixIcons.price_tag_3_fill;
  }
}
