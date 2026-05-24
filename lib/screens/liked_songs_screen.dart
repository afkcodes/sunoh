// Liked Songs detail — pinned tile in the Library tab opens this. Behaves
// like an album/playlist detail (hero + track list + play-all/shuffle) but
// with a synthetic accent hero instead of an artwork-based one, since the
// liked list isn't backed by API artwork.

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:solar_icons/solar_icons.dart';

import '../api/dto.dart';
import '../providers/app_state_provider.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';

class LikedSongsScreen extends ConsumerStatefulWidget {
  const LikedSongsScreen({super.key});
  @override
  ConsumerState<LikedSongsScreen> createState() => _LikedSongsScreenState();
}

class _LikedSongsScreenState extends ConsumerState<LikedSongsScreen> {
  final _scroll = ScrollController();
  final ValueNotifier<double> _offset = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() => _offset.value = _scroll.offset);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _offset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final accent = s.resolvedAccent;
    final songs = s.likedSongs;

    return ColoredBox(
      color: c.bg,
      child: SizedBox.expand(
        child: Stack(
          children: [
            Positioned.fill(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.only(bottom: 140),
                children: [
                  _LikedHero(
                    colors: c,
                    accent: accent,
                    count: songs.length,
                    scrollOffset: _offset,
                  ),
                  _LikedActions(
                    colors: c,
                    accent: accent,
                    songs: songs,
                  ),
                  if (songs.isEmpty)
                    _EmptyState(
                      colors: c,
                      label: 'No liked songs yet.',
                      detail: 'Tap the heart on any song to add it here.',
                    )
                  else
                    for (var i = 0; i < songs.length; i++)
                      _LikedTrackRow(
                        n: i + 1,
                        song: songs[i],
                        colors: c,
                        accent: accent,
                        onTap: () => s.playApiQueue(
                          songs,
                          i,
                          sourceLabel: 'LIKED · Songs',
                        ),
                      ),
                ],
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _StickyLikedHeader(
                colors: c,
                scrollOffset: _offset,
                onBack: () => context.pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Synthetic hero — heart icon on accent gradient, since liked songs aren't
/// backed by an API artwork URL. Reads scrollOffset to fade-and-scale like
/// the album hero so the sticky header takeover feels consistent.
class _LikedHero extends StatelessWidget {
  const _LikedHero({
    required this.colors,
    required this.accent,
    required this.count,
    required this.scrollOffset,
  });
  final SunohColors colors;
  final Color accent;
  final int count;
  final ValueListenable<double> scrollOffset;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final topInset = MediaQuery.of(context).padding.top;
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  accent.withValues(alpha: 0.55),
                  accent.withValues(alpha: 0.18),
                  c.bg,
                ],
                stops: const [0, 0.55, 1],
              ),
            ),
          ),
        ),
        Column(
          children: [
            SizedBox(height: topInset + 52),
            ValueListenableBuilder<double>(
              valueListenable: scrollOffset,
              builder: (_, offset, child) {
                final progress = (offset / 320).clamp(0.0, 1.0);
                final scale = 1.0 - progress * 0.3;
                final opacity = (1.0 - progress).clamp(0.0, 1.0);
                return Opacity(
                  opacity: opacity,
                  child: Transform.scale(scale: scale, child: child),
                );
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
                child: Column(
                  children: [
                    // Heart-on-gradient "cover" — visually echoes the
                    // album/playlist hero without an actual artwork.
                    Container(
                      width: 220,
                      height: 220,
                      decoration: squircleDecoration(
                        radius: 16,
                        gradient: LinearGradient(
                          colors: [
                            accent,
                            accent.withValues(alpha: 0.55),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Icon(
                        SolarIconsBold.heart,
                        size: 96,
                        color: Colors.white.withValues(alpha: 0.92),
                      ),
                    ),
                    const SizedBox(height: 20),
                    eyebrow('YOUR LIBRARY', c.fgMute),
                    const SizedBox(height: 6),
                    Text('Liked Songs',
                        textAlign: TextAlign.center,
                        style: SunohType.heading(
                            fontSize: 26,
                            color: c.fg,
                            height: 1.1,
                            letterSpacing: -0.4)),
                    const SizedBox(height: 6),
                    Text('$count ${count == 1 ? 'song' : 'songs'}',
                        style:
                            SunohType.sans(fontSize: 13, color: c.fgDim)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LikedActions extends StatelessWidget {
  const _LikedActions({
    required this.colors,
    required this.accent,
    required this.songs,
  });
  final SunohColors colors;
  final Color accent;
  final List<FeedItem> songs;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    // We need AppState here for play actions — grab via Riverpod's
    // ProviderScope rather than asking the caller to thread it through.
    return Consumer(builder: (context, ref, _) {
      final app = ref.watch(appStateProvider);
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${songs.length} ${songs.length == 1 ? 'song' : 'songs'}',
                style: SunohType.sans(fontSize: 12, color: c.fgMute)),
            Row(
              children: [
                GestureDetector(
                  onTap: songs.isEmpty
                      ? null
                      : () => app.flashToast('Shuffle coming soon'),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: c.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.line, width: 0.5),
                    ),
                    child: Icon(PhosphorIconsBold.shuffle,
                        size: 18,
                        color: songs.isEmpty ? c.fgMute : c.fgDim),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: songs.isEmpty
                      ? null
                      : () => app.playApiQueue(songs, 0,
                          sourceLabel: 'LIKED · Songs'),
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: songs.isEmpty
                          ? c.surface
                          : accent,
                      shape: BoxShape.circle,
                      boxShadow: songs.isEmpty
                          ? null
                          : [
                              BoxShadow(
                                  color: accent.withValues(alpha: 0.33),
                                  blurRadius: 22,
                                  offset: const Offset(0, 6)),
                            ],
                    ),
                    child: Icon(PhosphorIconsFill.play,
                        size: 24,
                        color: songs.isEmpty
                            ? c.fgMute
                            : (accent.computeLuminance() > 0.55
                                ? const Color(0xFF0B0B0D)
                                : const Color(0xFFFAFAFA))),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }
}

class _LikedTrackRow extends ConsumerWidget {
  const _LikedTrackRow({
    required this.n,
    required this.song,
    required this.colors,
    required this.accent,
    required this.onTap,
  });
  final int n;
  final FeedItem song;
  final SunohColors colors;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    final s = ref.watch(appStateProvider);
    final artistsLabel = (song.artists ?? const <ApiArtistRef>[])
        .map((a) => a.name.trim())
        .where((sa) => sa.isNotEmpty)
        .take(2)
        .join(', ');
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: 20, vertical: 10 * s.density.scale),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: Center(
                child: Text(n.toString().padLeft(2, '0'),
                    style: SunohType.mono(fontSize: 11, color: c.fgMute)),
              ),
            ),
            const SizedBox(width: 12),
            // Artwork — liked rows always show the cover so the screen
            // doesn't look text-heavy without the rich palette of an
            // album page.
            _LikedThumb(song: song),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SunohType.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: c.fg)),
                  if (artistsLabel.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(artistsLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            SunohType.sans(fontSize: 11.5, color: c.fgMute)),
                  ],
                ],
              ),
            ),
            IconBtn(
                icon: SolarIconsBold.heart,
                color: accent,
                size: 16,
                width: 32,
                height: 32,
                onTap: () => s.toggleLikedSong(song)),
          ],
        ),
      ),
    );
  }
}

/// 42-px liked-row thumbnail. Lives as its own widget so we can swap the
/// underlying image provider without thrashing parents on rebuild.
class _LikedThumb extends StatelessWidget {
  const _LikedThumb({required this.song});
  final FeedItem song;
  @override
  Widget build(BuildContext context) => squircleClip(
        radius: 6,
        child: SizedBox(
          width: 42,
          height: 42,
          child: ColoredBox(
            color: const Color(0xFF1A1A1F),
            child: song.artwork == null || song.artwork!.isEmpty
                ? const Icon(SolarIconsBold.heart, size: 18, color: Colors.white24)
                : Image.network(
                    song.artwork!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Icon(
                        SolarIconsBold.heart,
                        size: 18,
                        color: Colors.white24),
                  ),
          ),
        ),
      );
}

class _StickyLikedHeader extends StatelessWidget {
  const _StickyLikedHeader({
    required this.colors,
    required this.scrollOffset,
    required this.onBack,
  });
  final SunohColors colors;
  final ValueListenable<double> scrollOffset;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final topInset = MediaQuery.of(context).padding.top;
    return SizedBox(
      height: topInset + 52,
      child: ValueListenableBuilder<double>(
        valueListenable: scrollOffset,
        builder: (_, offset, _) {
          // Lighter scroll threshold than album/playlist (320 vs 360) since
          // the synthetic hero is a bit shorter.
          final bgT = ((offset - 240) / 80).clamp(0.0, 1.0);
          final titleT = ((offset - 270) / 50).clamp(0.0, 1.0);
          return Stack(
            children: [
              IgnorePointer(
                child: Stack(
                  children: [
                    if (bgT > 0.02)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: c.bg.withValues(alpha: bgT),
                            border: bgT > 0.9
                                ? Border(
                                    bottom: BorderSide(
                                        color: c.line, width: 0.5))
                                : null,
                          ),
                        ),
                      ),
                    if (titleT > 0.01)
                      Positioned(
                        top: topInset,
                        left: 64,
                        right: 64,
                        bottom: 0,
                        child: Opacity(
                          opacity: titleT,
                          child: Center(
                            child: Text('Liked Songs',
                                style: SunohType.heading(
                                    fontSize: 15,
                                    color: c.fg,
                                    letterSpacing: -0.2)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Positioned(
                top: topInset + 6,
                left: 16,
                right: 16,
                child: IgnorePointer(
                  ignoring: titleT < 0.2,
                  child: Opacity(
                    opacity: titleT,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconBtn(
                            icon: SolarIconsOutline.altArrowLeft,
                            color: c.fg,
                            size: 22,
                            background:
                                Colors.black.withValues(alpha: 0.35),
                            onTap: onBack),
                        IconBtn(
                            icon: SolarIconsBold.menuDots,
                            color: c.fg,
                            size: 18,
                            background:
                                Colors.black.withValues(alpha: 0.35),
                            onTap: () {}),
                      ],
                    ),
                  ),
                ),
              ),
              // Always-on back chip layered ABOVE so it's reachable even
              // when the sticky header hasn't faded in yet (synthetic hero
              // is the user's own data — they should always be able to
              // back out without scrolling).
              Positioned(
                top: topInset + 6,
                left: 16,
                child: IconBtn(
                    icon: SolarIconsOutline.altArrowLeft,
                    color: c.fg,
                    size: 22,
                    background: Colors.black.withValues(alpha: 0.35),
                    onTap: onBack),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.colors,
    required this.label,
    required this.detail,
  });
  final SunohColors colors;
  final String label;
  final String detail;
  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 40),
      child: Center(
        child: Column(
          children: [
            Text(label,
                style: SunohType.heading(fontSize: 18, color: c.fgDim)),
            const SizedBox(height: 8),
            Text(detail,
                textAlign: TextAlign.center,
                style: SunohType.sans(fontSize: 12.5, color: c.fgMute)),
          ],
        ),
      ),
    );
  }
}

