// Radio tab — country-aware live-stream catalog from /radios/home.
//
// Visually distinct from PodcastsTab:
//   - Tiles are SQUARE LOGOS, not "labeled cards". Radio station logos
//     are typically logotype-on-solid-background and don't benefit from
//     the bottom-gradient title overlay podcast covers use. The title
//     sits BELOW the cover instead.
//   - Tap = play (PlayMode.live). No detail screen — live streams have
//     no metadata browse, the player itself adapts (see [[sunoh-audio]]
//     and `expanded_player.dart` for the LIVE-mode UI).
//
// Country comes from the device locale; the backend has its own
// IP-geo fallback if the locale doesn't carry one.
//
// (Earlier incarnation was a Stateful FM-dial mockup ported from
// radio.jsx — long since unused; this file replaces it wholesale.)

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../api/dto.dart';
import '../audio/audio_handler.dart' show PlayMode;
import '../providers/app_state_provider.dart';
import '../providers/radio_provider.dart';
import '../router/router.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/ui.dart';

class RadioTab extends ConsumerWidget {
  const RadioTab({super.key, required this.colors});
  final SunohColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    final country =
        PlatformDispatcher.instance.locale.countryCode?.toUpperCase();
    final async = ref.watch(radioHomeProvider(country));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Eyebrow + "Browse genres" chip on the right. Same 20-px
        // gutter the podcasts tab uses.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              eyebrow('RADIO', c.fgMute, size: 10, letterSpacing: 1.4),
              GestureDetector(
                onTap: () => context.openRadioGenres(),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: squircleDecoration(
                    radius: 999,
                    color: c.surface,
                    borderColor: c.line,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(SolarIconsOutline.widget,
                          size: 12, color: c.fgDim),
                      const SizedBox(width: 6),
                      Text('Browse',
                          style: SunohType.sans(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: c.fgDim)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        async.when(
          loading: () => _RadioSkeleton(colors: c),
          error: (e, _) => _RadioErrorState(
            colors: c,
            accent: ref.watch(appStateProvider).resolvedAccent,
            error: e,
            onRetry: () => ref.invalidate(radioHomeProvider(country)),
          ),
          data: (sections) {
            if (sections.isEmpty) return _RadioEmpty(colors: c);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < sections.length; i++) ...[
                  _RadioSection(
                      section: sections[i],
                      colors: c,
                      featured: i == 0),
                  if (i < sections.length - 1) const SizedBox(height: 32),
                  // Drop the genres preview after the featured section
                  // for the same discovery-aid reason podcasts use the
                  // categories strip after Trending.
                  if (i == 0) ...[
                    const _GenresPreview(),
                    const SizedBox(height: 32),
                  ],
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}

/// One horizontally-scrolling row of station tiles. Featured (first)
/// section gets bigger tiles, same convention as music + podcasts home.
class _RadioSection extends ConsumerWidget {
  const _RadioSection({
    required this.section,
    required this.colors,
    this.featured = false,
  });
  final HomeSection section;
  final SunohColors colors;
  final bool featured;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    final items = section.items;
    // Tiles smaller than the podcast equivalents on purpose — radio
    // station logos are typically scraped at 150×150 from
    // onlineradiobox, so a 180-px tile would up-scale and expose every
    // pixel. Featured ≈ original podcast non-featured size; the rest
    // tighter still.
    final width = featured ? 132.0 : 104.0;
    // height = cover (square) + spacing + 2 lines of caption.
    final height = width + 48;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: section.heading, colors: c),
        SizedBox(
          height: height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, i) => _RadioTile(
              item: items[i],
              colors: c,
              width: width,
            ),
          ),
        ),
      ],
    );
  }
}

/// Radio station tile. Reverted to a clean bare-cover-+-text layout
/// after the framed-on-card variant didn't land — see the chat for
/// what the next direction should be.
class _RadioTile extends ConsumerWidget {
  const _RadioTile({
    required this.item,
    required this.colors,
    required this.width,
  });
  final FeedItem item;
  final SunohColors colors;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    final s = ref.read(appStateProvider);
    return GestureDetector(
      onTap: () => s.playApiQueue(
        [item],
        0,
        sourceLabel: 'RADIO · ${item.title}',
        mode: PlayMode.live,
      ),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            squircleClip(
              radius: 14,
              child: SunohArt(
                id: item.id,
                imageUrl: item.artwork,
                size: width,
                radius: 14,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SunohType.sans(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: c.fg,
                height: 1.2,
              ),
            ),
            if ((item.subtitle ?? '').isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                item.subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SunohType.sans(
                  fontSize: 11,
                  color: c.fgMute,
                  height: 1.2,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Compact 2-row grid of genre chips — top 8 from the facet endpoint
/// with a "See all" CTA opening the full taxonomy. Lives between the
/// featured section and the rest of the genre rows.
class _GenresPreview extends ConsumerWidget {
  const _GenresPreview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final accent = s.resolvedAccent;
    final async = ref.watch(radioGenresProvider);
    final genres = async.asData?.value ?? const <RadioFacet>[];
    if (genres.isEmpty) return const SizedBox.shrink();
    final top = genres.take(8).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Genres',
                style: SunohType.heading(
                    fontSize: 17, color: c.fg, letterSpacing: -0.2),
              ),
              GestureDetector(
                onTap: () => context.openRadioGenres(),
                behavior: HitTestBehavior.opaque,
                child: Text(
                  'See all',
                  style: SunohType.sans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          // Slightly taller than before — the new tile shape is more
          // square-ish so the bigger glyph corner has room to breathe.
          height: 120,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: top.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) => GenreTile(
              facet: top[i],
              variant: GenreTileVariant.preview,
            ),
          ),
        ),
      ],
    );
  }
}

/// Render variant for [GenreTile]. The Radio tab's horizontal preview
/// strip uses `preview` (compact, ~130 wide); the full grid screen
/// uses `card` (bigger, 4:3, optimised for a 2-column layout).
enum GenreTileVariant { preview, card }

/// Colored genre tile shared between the Radio tab preview strip and
/// the full genres-grid screen. Single widget with two layout variants
/// so the look stays consistent.
///
/// Design:
///   - Solid color from the per-genre palette (NOT user accent —
///     genre identity should survive accent changes).
///   - White typography on color: title (bold, tightly tracked) + a
///     muted "N stations" subtitle below.
///   - Decorative Solar icon in the bottom-right corner, slightly
///     rotated, at low opacity. Picked per-genre by name when we
///     recognise it (Comedy→smiley, News→notebook, …), fallback to
///     a generic music glyph.
///   - Squircle clip so the shape matches every other rounded surface
///     in the app.
class GenreTile extends StatelessWidget {
  const GenreTile({
    super.key,
    required this.facet,
    this.variant = GenreTileVariant.preview,
  });
  final RadioFacet facet;
  final GenreTileVariant variant;

  @override
  Widget build(BuildContext context) {
    final isCard = variant == GenreTileVariant.card;
    final seed = genreColorFor(facet.value);
    return GestureDetector(
      onTap: () => context.openRadioGenre(facet.value),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: isCard ? null : 130,
        child: squircleClip(
          radius: isCard ? 16 : 12,
          child: Container(
            // Subtle vertical gradient — top is the seed, bottom a hair
            // darker. Catches light without overwhelming the title.
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  seed,
                  Color.lerp(seed, Colors.black, 0.18)!,
                ],
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.hardEdge,
              children: [
                // Decorative glyph in the bottom-right corner. Offset
                // partly off the tile + tilted so the corner reads
                // as "marked" rather than centered around an icon.
                Positioned(
                  right: isCard ? -10 : -8,
                  bottom: isCard ? -10 : -8,
                  child: Transform.rotate(
                    angle: -0.18,
                    child: Icon(
                      genreIconFor(facet.value),
                      size: isCard ? 72 : 52,
                      color: Colors.white.withValues(alpha: 0.22),
                    ),
                  ),
                ),
                // Text block — bottom-left, title first then count.
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      isCard ? 16 : 12,
                      isCard ? 14 : 10,
                      isCard ? 16 : 12,
                      isCard ? 14 : 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        titleCase(facet.value),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: SunohType.heading(
                          fontSize: isCard ? 18 : 14,
                          color: Colors.white,
                          letterSpacing: -0.25,
                          height: 1.1,
                        ),
                      ),
                      Text(
                        _formatCount(facet.count),
                        style: SunohType.sans(
                          fontSize: isCard ? 12 : 11,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
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

/// "1,234 stations" / "5 stations" — compact, no decimal abbreviation.
/// At <10 we drop the "stations" suffix since the count alone reads
/// fine in tight tile space.
String _formatCount(int n) {
  final formatted = n
      .toString()
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  return n == 1 ? '$formatted station' : '$formatted stations';
}

/// 12-color curated palette — shared by Radio tab preview tiles AND
/// the full genres-grid screen so the same genre always wears the
/// same color. Hues sit warm-to-cool around the wheel; saturation +
/// brightness tuned to read cleanly with white text on top.
const _genrePalette = <Color>[
  Color(0xFFE05656), // red — News, talk
  Color(0xFFE07A3C), // orange — Comedy
  Color(0xFFD9A93C), // amber — Country, blues
  Color(0xFF6FBF73), // green — Reggae, world
  Color(0xFF3FB7C7), // teal — Chill, lounge
  Color(0xFF4A8FE0), // blue — Jazz, classical
  Color(0xFF8466DC), // violet — Electronic, dance
  Color(0xFFCB5BB6), // pink — Pop, hits
  Color(0xFFC36F4F), // brick — Rock, indie
  Color(0xFF4F9F8F), // sea — Folk, acoustic
  Color(0xFFB36FB9), // mauve — R&B, soul
  Color(0xFF6FAB4F), // olive — Hip-hop, urban
];

/// Stable color for a genre — every render of "jazz" gets the same hue
/// regardless of where it appears. Uses absolute hashCode so positive
/// values are guaranteed.
Color genreColorFor(String value) =>
    _genrePalette[value.hashCode.abs() % _genrePalette.length];

/// Best-effort genre → Solar icon mapping. Falls back to a generic
/// music-note glyph for anything not recognised. Mirrors the per-
/// category mapping podcast_categories_screen uses; kept ordered so
/// more-specific terms (e.g. "country" before "talk") match first
/// when a genre name contains multiple keywords.
IconData genreIconFor(String value) {
  final n = value.toLowerCase();
  if (n.contains('news')) return SolarIconsBold.notebookMinimalistic;
  if (n.contains('comedy') || n.contains('humor')) {
    return SolarIconsBold.emojiFunnyCircle;
  }
  if (n.contains('sport')) return SolarIconsBold.basketball;
  if (n.contains('talk')) return SolarIconsBold.chatRoundLine;
  if (n.contains('jazz') || n.contains('classical') ||
      n.contains('orchestra')) {
    return SolarIconsBold.musicNote4;
  }
  if (n.contains('rock') || n.contains('metal') || n.contains('punk')) {
    return SolarIconsBold.radioMinimalistic;
  }
  if (n.contains('pop') || n.contains('hits') || n.contains('top')) {
    return SolarIconsBold.stars;
  }
  if (n.contains('hip') ||
      n.contains('rap') ||
      n.contains('rnb') ||
      n.contains("r'n'b")) {
    return SolarIconsBold.headphonesRound;
  }
  if (n.contains('country') || n.contains('folk') || n.contains('blues')) {
    return SolarIconsBold.microphone;
  }
  if (n.contains('dance') ||
      n.contains('electronic') ||
      n.contains('house') ||
      n.contains('techno')) {
    return SolarIconsBold.soundwaveSquare;
  }
  if (n.contains('chill') || n.contains('lounge') || n.contains('lo-fi') ||
      n.contains('lofi')) {
    return SolarIconsBold.moonStars;
  }
  if (n.contains('religious') ||
      n.contains('gospel') ||
      n.contains('spirit') ||
      n.contains('hindu') ||
      n.contains('christian') ||
      n.contains('islam')) {
    return SolarIconsBold.starsLine;
  }
  if (n.contains('kids') || n.contains('family')) {
    return SolarIconsBold.usersGroupTwoRounded;
  }
  if (n.contains('bollywood') || n.contains('hindi') ||
      n.contains('indian')) {
    return SolarIconsBold.musicNote2;
  }
  if (n.contains('variety') || n.contains('mix')) {
    return SolarIconsBold.musicLibrary2;
  }
  return SolarIconsBold.musicNote;
}

/// Title-cased genre label — "hip-hop" → "Hip-Hop", "top40" → "Top40".
/// Used by genre chips + the genre-detail screen header.
String titleCase(String s) {
  if (s.isEmpty) return s;
  return s.split(RegExp(r'\s+')).map((w) {
    if (w.isEmpty) return w;
    return w[0].toUpperCase() + w.substring(1).toLowerCase();
  }).join(' ');
}

class _RadioSkeleton extends StatelessWidget {
  const _RadioSkeleton({required this.colors});
  final SunohColors colors;
  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < 3; i++) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Container(
              width: 120,
              height: 14,
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          SizedBox(
            height: 188,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: 5,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (_, _) => Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ],
    );
  }
}

/// Empty / failed state for the Radio tab.
///
/// Renders a centered illustration block — accent-tinted icon medallion,
/// a friendly title, a single line of humanised cause (NEVER the raw
/// DioException toString), and a Retry chip. Same shape used by
/// `_RadioEmpty` (no error, no stations) so the layout stays consistent
/// when the user hits either path.
class _RadioErrorState extends StatelessWidget {
  const _RadioErrorState({
    required this.colors,
    required this.accent,
    required this.error,
    required this.onRetry,
  });
  final SunohColors colors;
  final Color accent;
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _RadioMessageBlock(
      colors: colors,
      accent: accent,
      icon: SolarIconsOutline.wifiRouterRound,
      title: 'No radio right now',
      detail: _humaniseRadioError(error),
      action: ('Try again', onRetry),
    );
  }
}

class _RadioEmpty extends StatelessWidget {
  const _RadioEmpty({required this.colors});
  final SunohColors colors;
  @override
  Widget build(BuildContext context) {
    // Empty state borrows the same medallion shape; passing accent from
    // the nearest ConsumerWidget would mean threading another param —
    // accent is recoverable from app state but `_RadioEmpty` is a leaf,
    // so use the colors layer's `fgDim` neutral instead (less alarming
    // than the error variant, fitting an empty rather than failed state).
    return _RadioMessageBlock(
      colors: colors,
      accent: colors.fgDim,
      icon: SolarIconsOutline.musicLibrary2,
      title: 'No stations yet',
      detail: 'The catalog is empty in your region right now. '
          'Try a different country from Browse.',
      action: null,
    );
  }
}

/// Shared layout for the empty / error states — medallion + title +
/// muted detail + optional action chip, vertically centered.
class _RadioMessageBlock extends StatelessWidget {
  const _RadioMessageBlock({
    required this.colors,
    required this.accent,
    required this.icon,
    required this.title,
    required this.detail,
    required this.action,
  });
  final SunohColors colors;
  final Color accent;
  final IconData icon;
  final String title;
  final String detail;
  /// `(label, onTap)` — null hides the action button.
  final (String, VoidCallback)? action;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 56, 32, 32),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: 0.16),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: accent, size: 28),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: SunohType.heading(
                fontSize: 17, color: c.fg, letterSpacing: -0.2),
          ),
          const SizedBox(height: 6),
          Text(
            detail,
            textAlign: TextAlign.center,
            style:
                SunohType.sans(fontSize: 13, color: c.fgMute, height: 1.4),
          ),
          if (action != null) ...[
            const SizedBox(height: 18),
            GestureDetector(
              onTap: action!.$2,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                decoration: squircleDecoration(
                  radius: 999,
                  color: accent.withValues(alpha: 0.14),
                  borderColor: accent.withValues(alpha: 0.32),
                ),
                child: Text(
                  action!.$1,
                  style: SunohType.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: accent,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Map any error from the radio-home future into a one-liner that
/// belongs in the UI. The DioException toString is a stack-trace-y
/// disaster — we never want to render that to a user. Keep this in
/// sync with the SpotifyImport humaniser in [[app_state]].
String _humaniseRadioError(Object e) {
  final raw = e.toString();
  if (raw.contains('SocketException') ||
      raw.contains('Failed host lookup') ||
      raw.contains('timeout')) {
    return 'Check your connection and try again.';
  }
  if (raw.contains('502') || raw.contains('503') || raw.contains('504')) {
    return 'Our radio service is having a moment. Try again in a bit.';
  }
  if (raw.contains('500')) {
    return 'Something went wrong on our end. Try again shortly.';
  }
  return 'Something went wrong loading stations. Try again.';
}
