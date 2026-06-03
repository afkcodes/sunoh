// Browse all audiobook genres. Same shell + gradient-card pattern as
// PodcastCategoriesScreen so the "Browse" surfaces across tabs read as
// one product. Genre → glyph map below gives Mystery a magnifier,
// Fantasy a star, Romance a heart, etc. — the page reads as
// graphic-rich, not "N tinted rectangles".

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';

import '../api/dto.dart';
import '../providers/app_state_provider.dart';
import '../providers/audiobook_provider.dart';
import '../router/router.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';

/// Same 12-color curated palette PodcastCategoriesScreen uses — each
/// category picks deterministically by `id % 12`, so the same genre
/// always wears the same color across renders.
const _genrePalette = <Color>[
  Color(0xFFE05656), Color(0xFFE07A3C), Color(0xFFD9A93C),
  Color(0xFF6FBF73), Color(0xFF3FB7C7), Color(0xFF4A8FE0),
  Color(0xFF8466DC), Color(0xFFCB5BB6), Color(0xFFC36F4F),
  Color(0xFF4F9F8F), Color(0xFFB36FB9), Color(0xFF6FAB4F),
];

class AudiobookCategoriesScreen extends ConsumerWidget {
  const AudiobookCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final async = ref.watch(audiobookCategoriesProvider);
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
                  Text('Genres',
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
                'Pick a genre to discover audiobooks in it.',
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
                      style: SunohType.sans(
                          fontSize: 13, color: c.fgMute),
                    ),
                  ),
                ),
                data: (cats) => GridView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 140),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 180 / 64,
                  ),
                  itemCount: cats.length,
                  itemBuilder: (context, i) => AudiobookCategoryCard(
                    category: cats[i],
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

/// Wide gradient card — mirrors PodcastCategoryCard so the visual
/// vocabulary matches across "Browse" surfaces. Title on the left,
/// rotated topic glyph tucked off the right edge.
class AudiobookCategoryCard extends StatelessWidget {
  const AudiobookCategoryCard({
    super.key,
    required this.category,
    required this.colors,
  });
  final AudiobookCategory category;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final icon = _iconFor(category.name);
    final seed = _genrePalette[category.id % _genrePalette.length];
    return GestureDetector(
      onTap: () => context.openAudiobookCategory(
        category.id,
        name: category.name,
      ),
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
                    child: Icon(icon,
                        color: Colors.white.withValues(alpha: 0.92),
                        size: 30),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// Map a genre name → Solar glyph. Falls back to a generic book icon
  /// for anything unmapped. Adds visual variety to the Browse grid
  /// without us having to source per-genre artwork.
  IconData _iconFor(String name) {
    final n = name.toLowerCase();
    if (n.contains('mystery') || n.contains('crime') || n.contains('detective')) {
      return SolarIconsOutline.magnifier;
    }
    if (n.contains('thriller') || n.contains('suspense')) {
      return SolarIconsOutline.bolt;
    }
    if (n.contains('horror')) return SolarIconsOutline.ghost;
    if (n.contains('romance') || n.contains('love')) {
      return SolarIconsOutline.heart;
    }
    if (n.contains('fantasy')) return SolarIconsOutline.starFall;
    if (n.contains('sci') || n.contains('science fiction')) {
      return SolarIconsOutline.rocket;
    }
    if (n.contains('history') || n.contains('historical')) {
      return SolarIconsOutline.bookmark;
    }
    if (n.contains('children') || n.contains('kids') || n.contains('young')) {
      return SolarIconsOutline.smileCircle;
    }
    if (n.contains('comedy') || n.contains('humor')) {
      return SolarIconsOutline.smileSquare;
    }
    if (n.contains('action') || n.contains('adventure')) {
      return SolarIconsOutline.compass;
    }
    if (n.contains('self') || n.contains('help')) {
      return SolarIconsOutline.lightbulb;
    }
    if (n.contains('biography') || n.contains('memoir')) {
      return SolarIconsOutline.userCircle;
    }
    if (n.contains('classic')) return SolarIconsOutline.crown;
    if (n.contains('non-fiction') || n.contains('nonfiction')) {
      return SolarIconsOutline.notebookMinimalistic;
    }
    if (n.contains('bestseller')) return SolarIconsOutline.crown;
    if (n.contains('news') || n.contains('talk')) {
      return SolarIconsOutline.microphone;
    }
    if (n.contains('paranormal') || n.contains('supernatural')) {
      return SolarIconsOutline.moonStars;
    }
    if (n.contains('lgbt')) return SolarIconsOutline.starsLine;
    return SolarIconsOutline.bookmark;
  }
}
