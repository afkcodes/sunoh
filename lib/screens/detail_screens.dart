// Detail screens — Album / Playlist / Artist are wired to the live sunoh-api
// (Riverpod providers). PodcastScreen stays on the dummy catalog until
// podcast support lands in the backend (see sunoh-rn-reference memory).

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:solar_icons/solar_icons.dart';

import '../api/dto.dart';
import '../data/catalog.dart';
import '../data/models.dart';
import '../providers/app_state_provider.dart';
import '../providers/detail_providers.dart';
import '../providers/palette_provider.dart';
import '../providers/search_provider.dart';
import '../router/router.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/ui.dart';

// ── Shared bits ──────────────────────────────────────────────────────────────

/// Back + menu-dots overlay. Renders on the sticky header's fade-in layer
/// (see [_StickyHeader]) so both buttons are hidden until the user has
/// scrolled past the hero — keeps the hero composition clean on first view.
/// System back / edge-swipe still works the whole time.
class _HeroBack extends StatelessWidget {
  const _HeroBack({required this.onBack, required this.color});
  final VoidCallback onBack;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconBtn(
            icon: SolarIconsOutline.altArrowLeft,
            color: color,
            size: 22,
            background: Colors.black.withValues(alpha: 0.35),
            onTap: onBack),
        IconBtn(
            icon: SolarIconsBold.menuDots,
            color: color,
            size: 18,
            background: Colors.black.withValues(alpha: 0.35),
            onTap: () {}),
      ],
    );
  }
}

class _HeroActions extends StatelessWidget {
  const _HeroActions({
    required this.colors,
    required this.accent,
    required this.liked,
    required this.isPlaying,
    required this.onPlay,
    required this.onShuffle,
    this.onLike,
  });
  final SunohColors colors;
  final Color accent;
  final bool liked;
  final bool isPlaying;
  final VoidCallback onPlay;
  final VoidCallback onShuffle;
  final VoidCallback? onLike;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              IconBtn(
                  icon: liked ? SolarIconsBold.heart : SolarIconsOutline.heart,
                  color: liked ? accent : c.fgDim,
                  size: 22,
                  onTap: onLike),
              IconBtn(
                  icon: SolarIconsOutline.downloadMinimalistic,
                  color: c.fgDim,
                  size: 20,
                  onTap: () {}),
              IconBtn(
                  icon: SolarIconsOutline.addCircle,
                  color: c.fgDim,
                  size: 20,
                  onTap: () {}),
            ],
          ),
          Row(
            children: [
              GestureDetector(
                onTap: onShuffle,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: c.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.line, width: 0.5),
                  ),
                  child: Icon(PhosphorIconsBold.shuffle, size: 18, color: c.fgDim),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: onPlay,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: accent.withValues(alpha: 0.33), blurRadius: 22, offset: const Offset(0, 6)),
                    ],
                  ),
                  child: Icon(isPlaying ? PhosphorIconsFill.pause : PhosphorIconsFill.play,
                      size: 24, color: _contrastOn(accent)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Scroll distance over which the hero artwork shrinks+fades and the sticky
// header takes over. Mirrors RN's HEADER_SCROLL_DISTANCE.
const double _kHeroScrollDistance = 360;

// Static zero offset — for hero contexts that don't have a scroll listener
// attached (e.g., the dummy PodcastScreen). Cheap to keep alive forever.
final ValueNotifier<double> _kZeroOffset = ValueNotifier<double>(0);

/// Pick a foreground (icon/text) color that reads cleanly on top of [bg].
/// Light backgrounds → near-black; dark backgrounds → near-white. Used for
/// the accent Play button — black-on-red looked muddy on warm light accents.
Color _contrastOn(Color bg) {
  // computeLuminance returns 0..1 (0 black, 1 white).
  return bg.computeLuminance() > 0.55
      ? const Color(0xFF0B0B0D)
      : const Color(0xFFFAFAFA);
}

/// Immersive hero — a large blurred copy of the artwork bleeds under the
/// status bar, washed with the extracted dominant color and ramped into c.bg.
/// The crisp foreground art floats on top.
///
/// Watches [scrollOffset] (driven by the parent ScrollController) so the
/// foreground content (cover + meta) scales 1.0→0.7 and fades 1.0→0 as the
/// user scrolls — RN-style. The backdrop gradient scrolls normally with the
/// list and is not animated.
class _DetailHero extends ConsumerWidget {
  const _DetailHero({
    required this.id,
    required this.title,
    required this.colors,
    required this.accent,
    required this.scrollOffset,
    this.imageUrl,
    this.eyebrowText,
    this.sub,
    this.secondary,
  });
  final String id;
  final String? imageUrl;
  final String title;
  final SunohColors colors;
  final Color accent;
  final ValueListenable<double> scrollOffset;
  final String? eyebrowText;
  final String? sub;
  final String? secondary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    final topInset = MediaQuery.of(context).padding.top;
    final url = imageUrl ?? '';
    final palette = url.isEmpty
        ? null
        : ref.watch(artPaletteProvider(url)).value;
    final tint = palette?.dominant ?? accent;

    // Stack sizes to the Column's intrinsic height — the backdrop fills it,
    // so its gradient ramp to c.bg matches the actual content height.
    return Stack(
      children: [
        Positioned.fill(
          child: _HeroBackdrop(tint: tint, bg: c.bg),
        ),
        Column(
          children: [
            // Status bar spacer + room for the overlay back/more buttons.
            SizedBox(height: topInset + 52),
            // Cover + meta — scaled and faded based on scroll.
            ValueListenableBuilder<double>(
              valueListenable: scrollOffset,
              builder: (_, offset, child) {
                final progress =
                    (offset / _kHeroScrollDistance).clamp(0.0, 1.0);
                final scale = 1.0 - progress * 0.3; // 1.0 → 0.7
                final opacity = (1.0 - progress).clamp(0.0, 1.0);
                // Never collapse the layout — keep the same vertical space
                // even when fully transparent. If we returned SizedBox.shrink
                // at opacity 0, the ListView's total scrollable extent would
                // shrink mid-scroll and the user could never scroll back to
                // see the hero again.
                return Opacity(
                  opacity: opacity,
                  child: Transform.scale(scale: scale, child: child),
                );
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
                child: Column(
                  // Explicit center alignment + Center() around the cover so
                  // the artwork sits exactly on the screen's horizontal axis
                  // (the back/more buttons in the sticky header are at 16-px
                  // edges, so the cover's content-area padding of 24-px would
                  // otherwise read as slightly off relative to them).
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Center(
                      child: SunohArt(
                          id: id, imageUrl: imageUrl, size: 320, radius: 16),
                    ),
                    const SizedBox(height: 20),
                    if ((eyebrowText ?? '').isNotEmpty) ...[
                      eyebrow(eyebrowText!, c.fgMute),
                      const SizedBox(height: 6),
                    ],
                    Text(title,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: SunohType.heading(
                            fontSize: 26,
                            color: c.fg,
                            height: 1.1,
                            letterSpacing: -0.4)),
                    if ((sub ?? '').isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(sub!,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SunohType.sans(fontSize: 13, color: c.fgDim)),
                    ],
                    if ((secondary ?? '').isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(secondary!,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SunohType.sans(fontSize: 11.5, color: c.fgMute)),
                    ],
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

/// Palette-driven gradient backdrop for the detail hero.
/// No blurred image — we tried that and the source-image echo (orange brand
/// bars, recognizable faces, etc. still readable through the blur) looked
/// amateurish. A clean color gradient lets the foreground cover own the
/// composition while the dominant color still sets the mood.
class _HeroBackdrop extends StatelessWidget {
  const _HeroBackdrop({required this.tint, required this.bg});
  final Color tint;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    // Darken the tint defensively — palette dominants can be very light
    // (cream skin tones, white text bars). Mixing with black guarantees
    // the top of the hero stays dark enough for white icons/text.
    final darkTint = Color.lerp(Colors.black, tint, 0.55)!;
    final topColor = Color.lerp(bg, darkTint, 0.85)!;
    final upperMid = Color.lerp(bg, darkTint, 0.55)!;
    final mid = Color.lerp(bg, tint, 0.15)!;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [topColor, upperMid, mid, bg, bg],
          stops: const [0, 0.28, 0.6, 0.9, 1],
        ),
      ),
    );
  }
}

/// Track row consuming a song [FeedItem] (live API). Used in
/// AlbumScreen / PlaylistScreen / ArtistScreen.
class _ApiTrackRow extends ConsumerWidget {
  const _ApiTrackRow({
    required this.n,
    required this.song,
    required this.colors,
    required this.accent,
    this.showArt = false,
    this.onTap,
  });
  final int n;
  final FeedItem song;
  final SunohColors colors;
  final Color accent;
  final bool showArt;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    final s = ref.watch(appStateProvider);
    final scale = s.density.scale;
    final liked = s.isLikedId(song.id);
    final artistsLabel = (song.artists ?? const <ApiArtistRef>[])
        .map((a) => a.name.trim())
        .where((sa) => sa.isNotEmpty)
        .take(2)
        .join(', ');
    final durationLabel = _formatDuration(song.duration);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10 * scale),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: Center(
                child: Text(n.toString().padLeft(2, '0'),
                    style: SunohType.mono(fontSize: 11, color: c.fgMute)),
              ),
            ),
            if (showArt) ...[
              const SizedBox(width: 12),
              SunohArt(id: song.id, imageUrl: song.artwork, size: 42, radius: 6),
            ],
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SunohType.sans(
                          fontSize: 14, fontWeight: FontWeight.w500, color: c.fg)),
                  if (artistsLabel.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(artistsLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SunohType.sans(fontSize: 11.5, color: c.fgMute)),
                  ],
                ],
              ),
            ),
            if (durationLabel != null) ...[
              const SizedBox(width: 8),
              Text(durationLabel,
                  style: SunohType.mono(fontSize: 11, color: c.fgMute)),
            ],
            IconBtn(
                icon: liked ? SolarIconsBold.heart : SolarIconsOutline.heart,
                color: liked ? accent : c.fgMute,
                size: 16,
                width: 32,
                height: 32,
                onTap: () => s.toggleLikedSong(song)),
            IconBtn(
                icon: SolarIconsBold.menuDots,
                color: c.fgMute,
                size: 16,
                width: 32,
                height: 32,
                onTap: () {}),
          ],
        ),
      ),
    );
  }

  static String? _formatDuration(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final n = int.tryParse(raw);
    if (n == null) return raw; // already pre-formatted
    final m = n ~/ 60;
    final s = n % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

// ── Reused loading/error states ─────────────────────────────────────────────

class _DetailLoading extends StatelessWidget {
  const _DetailLoading({required this.colors, this.round = false});
  final SunohColors colors;
  final bool round;
  @override
  Widget build(BuildContext context) {
    final c = colors;
    return ColoredBox(
      color: c.bg,
      child: ListView(
        padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 56, bottom: 140),
        children: [
          Center(
            child: Container(
              width: 220,
              height: 220,
              decoration: squircleDecoration(
                radius: round ? 999 : 12,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          const SizedBox(height: 22),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        ],
      ),
    );
  }
}

class _DetailError extends StatelessWidget {
  const _DetailError({
    required this.colors,
    required this.message,
    required this.onRetry,
    required this.onBack,
  });
  final SunohColors colors;
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return ColoredBox(
      color: c.bg,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _HeroBack(onBack: onBack, color: c.fg),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text("Couldn't load this.",
                        textAlign: TextAlign.center,
                        style: SunohType.heading(fontSize: 20, color: c.fg)),
                    const SizedBox(height: 8),
                    Text(message,
                        textAlign: TextAlign.center,
                        style: SunohType.sans(fontSize: 12, color: c.fgMute)),
                    const SizedBox(height: 20),
                    GestureDetector(
                      onTap: onRetry,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        decoration: squircleDecoration(
                            radius: 999, color: c.surface, borderColor: c.line),
                        child: Text('Try again',
                            style: SunohType.sans(
                                fontSize: 13, fontWeight: FontWeight.w600, color: c.fg)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Album / Playlist detail ─────────────────────────────────────────────────
class AlbumScreen extends ConsumerWidget {
  const AlbumScreen({
    super.key,
    required this.id,
    required this.kind,
    this.source,
  });
  final String id;
  final String kind; // 'album' | 'playlist'
  final String? source; // 'saavn' | 'gaana' | 'spotify'

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final isPlaylist = kind == 'playlist';
    final key = (id: id, source: source);

    if (isPlaylist) {
      final async = ref.watch(playlistProvider(key));
      if (async.isLoading) return _DetailLoading(colors: c);
      if (async.hasError) {
        return _DetailError(
          colors: c,
          message: '${async.error}',
          onRetry: () => ref.invalidate(playlistProvider(key)),
          onBack: () => context.pop(),
        );
      }
      final pl = async.requireValue;
      // Keep the loader up until the palette has resolved too — otherwise
      // the hero would briefly render with the deterministic accent and then
      // snap to the extracted tint, which reads as a half-loaded page.
      if (!_paletteSettled(ref, pl.artwork)) {
        return _DetailLoading(colors: c);
      }
      return _AlbumLikeBody(
        colors: c,
        id: pl.id,
        title: pl.title,
        imageUrl: pl.artwork,
        eyebrowText: 'PLAYLIST',
        sub: (pl.subtitle ?? '').isNotEmpty ? pl.subtitle : null,
        secondary: pl.metaLine.isNotEmpty ? pl.metaLine : null,
        description: pl.description,
        songs: pl.songs,
        sections: pl.sections,
        showAlbumArtInRow: true, // playlists often mix artists
      );
    }

    final async = ref.watch(albumProvider(key));
    if (async.isLoading) return _DetailLoading(colors: c);
    if (async.hasError) {
      return _DetailError(
        colors: c,
        message: '${async.error}',
        onRetry: () => ref.invalidate(albumProvider(key)),
        onBack: () => context.pop(),
      );
    }
    final al = async.requireValue;
    if (!_paletteSettled(ref, al.artwork)) {
      return _DetailLoading(colors: c);
    }
    return _AlbumLikeBody(
      colors: c,
      id: al.id,
      title: al.title,
      imageUrl: al.artwork,
      eyebrowText: 'ALBUM${(al.year ?? '').isNotEmpty ? ' · ${al.year}' : ''}',
      sub: al.artists.isNotEmpty
          ? al.artists.take(2).map((a) => a.name).join(', ')
          : null,
      secondary: al.metaLine.isNotEmpty ? al.metaLine : null,
      description: al.description,
      songs: al.songs,
      sections: al.sections,
      showAlbumArtInRow: false,
    );
  }
}

/// True when palette extraction for [url] is no longer in-flight (either it
/// returned a palette, returned null, errored out, or there's no URL to
/// extract from in the first place). Used by detail screens to delay reveal
/// until the immersive hero can render in its final tinted state.
bool _paletteSettled(WidgetRef ref, String? url) {
  if (url == null || url.isEmpty) return true;
  return !ref.watch(artPaletteProvider(url)).isLoading;
}

class _AlbumLikeBody extends ConsumerStatefulWidget {
  const _AlbumLikeBody({
    required this.colors,
    required this.id,
    required this.title,
    required this.songs,
    required this.sections,
    required this.showAlbumArtInRow,
    this.imageUrl,
    this.eyebrowText,
    this.sub,
    this.secondary,
    this.description,
  });

  final SunohColors colors;
  final String id;
  final String title;
  final String? imageUrl;
  final String? eyebrowText;
  final String? sub;
  final String? secondary;
  final String? description;
  final List<FeedItem> songs;
  final List<HomeSection> sections;
  final bool showAlbumArtInRow;

  @override
  ConsumerState<_AlbumLikeBody> createState() => _AlbumLikeBodyState();
}

class _AlbumLikeBodyState extends ConsumerState<_AlbumLikeBody> {
  late final ScrollController _scroll;
  // Drives the hero shrink + sticky header fade-in. ValueNotifier so the
  // animated bits rebuild independently of the whole tree on each tick.
  late final ValueNotifier<double> _offset;

  @override
  void initState() {
    super.initState();
    _offset = ValueNotifier<double>(0);
    _scroll = ScrollController()
      ..addListener(() {
        if (!_scroll.hasClients) return;
        final v = _scroll.offset.clamp(0.0, _kHeroScrollDistance);
        if ((v - _offset.value).abs() > 0.5) _offset.value = v;
      });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _offset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final s = ref.read(appStateProvider);
    final imageUrl = widget.imageUrl;
    final id = widget.id;
    final title = widget.title;
    final eyebrowText = widget.eyebrowText;
    final sub = widget.sub;
    final secondary = widget.secondary;
    final description = widget.description;
    final songs = widget.songs;
    final sections = widget.sections;
    final showAlbumArtInRow = widget.showAlbumArtInRow;

    // Prefer the extracted vibrant color from the artwork; fall back to the
    // deterministic accent while the palette is loading or absent.
    final palette = (imageUrl ?? '').isEmpty
        ? null
        : ref.watch(artPaletteProvider(imageUrl!)).value;
    final accent = palette?.accent ?? artAccent(id);

    return ColoredBox(
      color: c.bg,
      // SizedBox.expand forces tight constraints down to the Stack. Without
      // this, an upstream loose-constraint context (transitions, etc.) lets
      // the Stack take on the ListView's infinite intrinsic height — which
      // caused the "items repeating, endless scroll" glitch.
      child: SizedBox.expand(
        child: Stack(
          children: [
            // ListView fills the stack via Positioned.fill so Stack doesn't
            // try to size itself to the ListView's infinite intrinsic height.
            Positioned.fill(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.only(bottom: 140),
                children: [
                  _DetailHero(
                    id: id,
                    imageUrl: imageUrl,
                    title: title,
                    eyebrowText: eyebrowText,
                    sub: sub,
                    secondary: secondary,
                    colors: c,
                    accent: accent,
                    scrollOffset: _offset,
                  ),
                  _HeroActions(
                    colors: c,
                    accent: accent,
                    liked: false,
                    isPlaying: false,
                    onPlay: () {
                      if (songs.isNotEmpty) {
                        s.playApiQueue(songs, 0,
                            sourceLabel:
                                '${showAlbumArtInRow ? 'PLAYLIST' : 'ALBUM'} · $title');
                      }
                    },
                    onShuffle: () => s.flashToast('Shuffle coming soon'),
                    onLike: () => s.flashToast('Saved'),
                  ),
                  for (var i = 0; i < songs.length; i++)
                    _ApiTrackRow(
                      n: i + 1,
                      song: songs[i],
                      colors: c,
                      accent: accent,
                      showArt: showAlbumArtInRow,
                      onTap: () => s.playApiQueue(songs, i,
                          sourceLabel:
                              '${showAlbumArtInRow ? 'PLAYLIST' : 'ALBUM'} · $title'),
                    ),
                  if ((description ?? '').isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                      child: Text(description!,
                          style: SunohType.sans(
                              fontSize: 13, color: c.fgDim, height: 1.5)),
                    ),
                  ],
                  for (var i = 0; i < sections.length; i++) ...[
                    const SizedBox(height: 32),
                    _RelatedSection(section: sections[i], colors: c),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
            // Sticky header — back chip + menu-dots + bg + title all fade
            // in together once the user scrolls past the hero.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _StickyHeader(
                title: title,
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

/// Frosted top bar overlay. EVERYTHING in the header — bg, title, AND the
/// back / menu-dots buttons — fades in together as the user scrolls past
/// the hero. Initially nothing in the top bar is visible so the artwork
/// owns the composition; once the user has scrolled the back/menu chips
/// appear alongside the title. System back / edge-swipe still works while
/// the back button is hidden.
class _StickyHeader extends StatelessWidget {
  const _StickyHeader({
    required this.title,
    required this.colors,
    required this.scrollOffset,
    required this.onBack,
  });
  final String title;
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
          final bgT =
              ((offset - (_kHeroScrollDistance - 80)) / 80).clamp(0.0, 1.0);
          final titleT =
              ((offset - (_kHeroScrollDistance - 50)) / 50).clamp(0.0, 1.0);
          // Back + menu-dots fade in on the same curve as the title so the
          // whole bar emerges as one piece. IgnorePointer until they're
          // visible enough so the invisible chips don't absorb taps that
          // belong to the ListView.
          return Stack(
            children: [
              // Non-interactive bg + title — wrapped in IgnorePointer so
              // scroll drags pass through to the ListView below.
              IgnorePointer(
                child: Stack(
                  children: [
                    // Solid bg fade (cheap; no BackdropFilter re-raster).
                    if (bgT > 0.02)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: c.bg.withValues(alpha: bgT),
                            border: bgT > 0.9
                                ? Border(
                                    bottom: BorderSide(
                                        color: c.line, width: 0.5),
                                  )
                                : null,
                          ),
                        ),
                      ),
                    // Centered title.
                    if (titleT > 0.01)
                      Positioned(
                        top: topInset,
                        left: 64,
                        right: 64,
                        bottom: 0,
                        child: Opacity(
                          opacity: titleT,
                          child: Transform.translate(
                            offset: Offset(0, (1 - titleT) * 6),
                            child: Center(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: SunohType.heading(
                                  fontSize: 15,
                                  color: c.fg,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Back + menu-dots — interactive, but fade in with the header.
              Positioned(
                top: topInset + 6,
                left: 16,
                right: 16,
                child: IgnorePointer(
                  ignoring: titleT < 0.2,
                  child: Opacity(
                    opacity: titleT,
                    child: _HeroBack(onBack: onBack, color: c.fg),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// Renders one related/recommendation row (used at the bottom of album +
// playlist detail). Keeps the home design language: SectionHeader + horizontal
// squircle card row.
class _RelatedSection extends StatelessWidget {
  const _RelatedSection({required this.section, required this.colors});
  final HomeSection section;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final isArtistRow = section.items.every((it) => it.type == 'artist');
    final width = isArtistRow ? 96.0 : 140.0;
    final gap = isArtistRow ? 18.0 : 12.0;
    final visible = section.items.take(10).toList();
    final hasMore = section.items.length > 10;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: section.heading,
          colors: c,
          onSeeAll: hasMore ? () => context.openSection(section) : null,
        ),
        HCardRow<FeedItem>(
          items: visible,
          width: width,
          gap: gap,
          onTap: (item) {
            if (item.type == 'album' || item.type == 'playlist' || item.type == 'artist') {
              context.openRef(DetailRef(item.type, item.id,
                  source: item.source ?? section.source));
            }
          },
          builder: (item, w) => isArtistRow
              ? Column(
                  children: [
                    SunohArt(
                        id: item.id,
                        imageUrl: item.artwork,
                        size: w - 10,
                        radius: 999),
                    const SizedBox(height: 10),
                    Text(item.title,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: SunohType.sans(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: c.fg,
                            height: 1.2)),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SunohArt(
                        id: item.id,
                        imageUrl: item.artwork,
                        size: w,
                        radius: 10),
                    const SizedBox(height: 8),
                    Text(item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SunohType.sans(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                            color: c.fg,
                            height: 1.2)),
                    if ((item.displaySubtitle ?? '').isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(item.displaySubtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SunohType.sans(fontSize: 11.5, color: c.fgMute)),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

// ── Artist page ─────────────────────────────────────────────────────────────
class ArtistScreen extends ConsumerWidget {
  const ArtistScreen({super.key, required this.id, this.source});
  final String id;
  final String? source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final key = (id: id, source: source);
    final async = ref.watch(artistProvider(key));
    if (async.isLoading) return _DetailLoading(colors: c, round: true);
    if (async.hasError) {
      return _DetailError(
        colors: c,
        message: '${async.error}',
        onRetry: () => ref.invalidate(artistProvider(key)),
        onBack: () => context.pop(),
      );
    }
    final artist = async.requireValue;
    if (!_paletteSettled(ref, artist.artwork)) {
      return _DetailLoading(colors: c, round: true);
    }
    return _ArtistBody(colors: c, artist: artist);
  }
}

class _ArtistBody extends ConsumerWidget {
  const _ArtistBody({required this.colors, required this.artist});
  final SunohColors colors;
  final ArtistDetail artist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    final s = ref.read(appStateProvider);
    final coverUrl = artist.artwork;
    final palette = (coverUrl ?? '').isEmpty
        ? null
        : ref.watch(artPaletteProvider(coverUrl!)).value;
    final accent = palette?.accent ?? artAccent(artist.id);
    final tint = palette?.dominant ?? accent;
    final topInset = MediaQuery.of(context).padding.top;
    final tagsLine = (artist.role ?? artist.subtitle ?? '').trim();

    return ColoredBox(
      color: c.bg,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 140),
        children: [
          // Full-bleed image hero (bleeds under the status bar). Taller than
          // before so the artist face has room, and the gradient stack picks
          // up the extracted tint for a richer ramp into c.bg.
          SizedBox(
            height: 400,
            child: Stack(
              children: [
                SunohArt(
                  id: artist.id,
                  imageUrl: coverUrl,
                  width: double.infinity,
                  height: 400,
                  radius: 0,
                  shadow: false,
                ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      // Transparent middle stop uses the tint's hue so the
                      // fade into the tint band below stays clean — using
                      // Colors.transparent (= black w/ alpha 0) here muddied
                      // the gradient through dark grey.
                      colors: [
                        Colors.black.withValues(alpha: 0.35),
                        tint.withValues(alpha: 0),
                        tint.withValues(alpha: 0.18),
                        c.bg,
                      ],
                      stops: const [0, 0.25, 0.75, 1],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: topInset + 8,
                left: 16,
                right: 16,
                child: _HeroBack(onBack: () => context.pop(), color: Colors.white),
              ),
              Positioned(
                left: 20,
                right: 20,
                bottom: 56,
                child: Row(
                  children: [
                    Icon(SolarIconsBold.verifiedCheck, size: 18, color: accent),
                    const SizedBox(width: 8),
                    Text('Verified artist',
                        style: SunohType.sans(
                            fontSize: 11, color: Colors.white.withValues(alpha: 0.85))),
                  ],
                ),
              ),
              Positioned(
                left: 20,
                right: 20,
                bottom: 16,
                child: Text(artist.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: SunohType.heading(
                        fontSize: 40, color: Colors.white, height: 1, letterSpacing: -0.7)),
              ),
              ],
            ),
          ),
          if ((artist.followers ?? '').isNotEmpty || tagsLine.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: eyebrow(
                  [
                    if ((artist.followers ?? '').isNotEmpty) '${artist.followers} FOLLOWERS',
                    if (tagsLine.isNotEmpty) tagsLine.toUpperCase(),
                  ].join(' · '),
                  c.fgMute,
                  size: 10,
                  letterSpacing: 1.2),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: c.fgDim),
                  ),
                  child: Text('Follow',
                      style: SunohType.sans(fontSize: 12, fontWeight: FontWeight.w500, color: c.fg)),
                ),
                Row(
                  children: [
                    IconBtn(icon: SolarIconsOutline.share, color: c.fgDim, size: 18, width: 36, height: 36, onTap: () {}),
                    IconBtn(icon: SolarIconsBold.menuDots, color: c.fgDim, size: 18, width: 36, height: 36, onTap: () {}),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () {
                        if (artist.topSongs.isNotEmpty) {
                          s.playApiQueue(artist.topSongs, 0,
                              sourceLabel: 'TOP SONGS · ${artist.name}');
                        }
                      },
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: accent,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: accent.withValues(alpha: 0.33), blurRadius: 18, offset: const Offset(0, 6)),
                          ],
                        ),
                        child: Icon(PhosphorIconsFill.play, size: 20, color: _contrastOn(accent)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (artist.topSongs.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: eyebrow('POPULAR', c.fgMute),
            ),
            for (var i = 0; i < artist.topSongs.length && i < 5; i++)
              _ApiTrackRow(
                n: i + 1,
                song: artist.topSongs[i],
                colors: c,
                accent: accent,
                showArt: true,
                onTap: () => s.playApiQueue(artist.topSongs, i,
                    sourceLabel: 'TOP SONGS · ${artist.name}'),
              ),
          ],
          if (artist.albums.isNotEmpty) ...[
            const SizedBox(height: 20),
            SectionHeader(title: 'Discography', colors: c),
            HCardRow<FeedItem>(
              items: artist.albums,
              width: 140,
              onTap: (a) => context.openRef(
                  DetailRef(a.type, a.id, source: a.source ?? artist.source)),
              builder: (a, w) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SunohArt(id: a.id, imageUrl: a.artwork, size: w, radius: 10),
                  const SizedBox(height: 8),
                  Text(a.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SunohType.sans(
                          fontSize: 13, fontWeight: FontWeight.w500, color: c.fg, height: 1.2)),
                  if ((a.displaySubtitle ?? '').isNotEmpty) ...[
                    const SizedBox(height: 3),
                    eyebrow(a.displaySubtitle!, c.fgMute, size: 10, letterSpacing: 0.8),
                  ],
                ],
              ),
            ),
          ],
          for (var i = 0; i < artist.sections.length; i++) ...[
            const SizedBox(height: 32),
            _RelatedSection(section: artist.sections[i], colors: c),
          ],
          if ((artist.bio ?? '').isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionHeader(title: 'About', colors: c, padding: const EdgeInsets.only(bottom: 14)),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: squircleDecoration(radius: 12, color: c.surface, borderColor: c.line),
                    child: Text(
                      artist.bio!,
                      style: SunohType.sans(fontSize: 13, color: c.fgDim, height: 1.55),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ── Podcast detail (still on dummy catalog — backend support is upcoming) ────
class PodcastScreen extends ConsumerStatefulWidget {
  const PodcastScreen({super.key, required this.id});
  final String id;
  @override
  ConsumerState<PodcastScreen> createState() => _PodcastScreenState();
}

class _PodcastScreenState extends ConsumerState<PodcastScreen> {
  String tab = 'Episodes';

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final pod = podcastOf(widget.id) ?? kPodcasts[0];
    final episodes = episodesOf(pod.id);
    final accent = artAccent(widget.id);

    void playEpisode(Episode e) => s.playTrack(Track(
          id: e.id,
          title: e.title,
          artist: pod.title,
          duration: 6500,
          plays: '—',
          album: pod.id,
        ));

    return ColoredBox(
      color: c.bg,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 140),
        children: [
          _DetailHero(
            id: widget.id,
            title: pod.title,
            eyebrowText: 'PODCAST · ${pod.cadence.toUpperCase()}',
            sub: pod.host,
            secondary: '${pod.episodes} episodes',
            colors: c,
            accent: accent,
            scrollOffset: _kZeroOffset,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
            child: Text(pod.sub,
                textAlign: TextAlign.center,
                style: SunohType.sans(fontSize: 13, color: c.fgDim, height: 1.5)),
          ),
          _HeroActions(
            colors: c,
            accent: accent,
            liked: true,
            isPlaying: false,
            onPlay: () => episodes.isNotEmpty ? playEpisode(episodes.first) : null,
            onShuffle: () {},
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.line, width: 0.5)),
            ),
            child: Row(
              children: [
                for (final t in ['Episodes', 'About', 'Reviews'])
                  Padding(
                    padding: const EdgeInsets.only(right: 18),
                    child: GestureDetector(
                      onTap: () => setState(() => tab = t),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(t,
                              style: SunohType.sans(
                                  fontSize: 13,
                                  fontWeight: t == tab ? FontWeight.w600 : FontWeight.w500,
                                  color: t == tab ? c.fg : c.fgMute)),
                          const SizedBox(height: 4),
                          Container(
                              height: 1.5,
                              width: 24,
                              color: t == tab ? accent : Colors.transparent),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (tab == 'Episodes')
            for (var i = 0; i < episodes.length; i++)
              _EpisodeRow(
                episode: episodes[i],
                colors: c,
                isLast: i == episodes.length - 1,
                onTap: () => playEpisode(episodes[i]),
              ),
          if (tab == 'About')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${pod.sub} A weekly show recorded in a small studio in a small city. Listener questions read out at the start of each month.',
                    style: SunohType.sans(fontSize: 13.5, color: c.fgDim, height: 1.55),
                  ),
                  const SizedBox(height: 18),
                  DefaultTextStyle(
                    style: SunohType.mono(fontSize: 11, color: c.fgMute, letterSpacing: 0.4, height: 1.8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _kv('HOSTED BY', pod.host, c),
                        _kv('CADENCE', pod.cadence, c),
                        _kv('EPISODES', '${pod.episodes}', c),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (tab == 'Reviews')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
              child: Column(
                children: [
                  Text('4.8 out of 5', style: SunohType.heading(fontSize: 22, color: c.fgDim)),
                  const SizedBox(height: 6),
                  eyebrow('1,402 RATINGS', c.fgMute, size: 10, letterSpacing: 1.2),
                ],
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _kv(String k, String v, SunohColors c) => RichText(
        text: TextSpan(
          style: SunohType.mono(fontSize: 11, color: c.fgMute, letterSpacing: 0.4),
          children: [
            TextSpan(text: '$k '),
            TextSpan(text: v, style: SunohType.mono(fontSize: 11, color: c.fg, letterSpacing: 0.4)),
          ],
        ),
      );
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({
    required this.episode,
    required this.colors,
    required this.isLast,
    required this.onTap,
  });
  final Episode episode;
  final SunohColors colors;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          border: isLast ? null : Border(bottom: BorderSide(color: c.line, width: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            eyebrow('EP ${episode.num.toString().padLeft(3, '0')} · ${episode.date.toUpperCase()}',
                c.fgMute, size: 10, letterSpacing: 1.2),
            const SizedBox(height: 8),
            Text(episode.title,
                style: SunohType.heading(fontSize: 18, color: c.fg, height: 1.2, letterSpacing: -0.2)),
            if (episode.sub.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(episode.sub,
                  style: SunohType.sans(fontSize: 13, color: c.fgDim, height: 1.45)),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: c.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.line, width: 0.5),
                  ),
                  child: Icon(PhosphorIconsFill.play, size: 14, color: c.fg),
                ),
                Row(
                  children: [
                    Text(episode.duration,
                        style: SunohType.mono(fontSize: 10, color: c.fgMute, letterSpacing: 0.6)),
                    const SizedBox(width: 16),
                    Icon(SolarIconsOutline.downloadMinimalistic, size: 15, color: c.fgMute),
                    const SizedBox(width: 16),
                    Icon(SolarIconsBold.menuDots, size: 15, color: c.fgMute),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Occasion detail (browse-category collections from /music/occasions/:slug) ──
// Same hero + sticky-header pattern as album/playlist, but with no track list
// or play action of its own — occasions are CONTAINERS of sections (other
// playlists / songs / albums). The body is just stacked `_RelatedSection`s.
class OccasionScreen extends ConsumerStatefulWidget {
  const OccasionScreen({
    super.key,
    required this.slug,
    required this.title,
    required this.imageUrl,
    this.source = 'gaana',
  });
  final String slug;
  final String title;
  final String? imageUrl;
  final String source;

  @override
  ConsumerState<OccasionScreen> createState() => _OccasionScreenState();
}

class _OccasionScreenState extends ConsumerState<OccasionScreen> {
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
    final async = ref.watch(occasionDetailProvider(
        (slug: widget.slug, provider: widget.source)));

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
                  _DetailHero(
                    id: widget.slug,
                    imageUrl: widget.imageUrl,
                    title: widget.title,
                    eyebrowText: 'CATEGORY · ${widget.source.toUpperCase()}',
                    colors: c,
                    accent: accent,
                    scrollOffset: _offset,
                  ),
                  // Sections (Hero playlists, Songs, Albums, etc.) — async.
                  async.when(
                    loading: () => Padding(
                      padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
                      child: Text(
                        'Loading…',
                        style:
                            SunohType.sans(fontSize: 13, color: c.fgMute),
                      ),
                    ),
                    error: (e, _) => Padding(
                      padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
                      child: Text(
                        'Couldn’t load “${widget.title}”.\n$e',
                        style:
                            SunohType.sans(fontSize: 13, color: c.fgMute),
                      ),
                    ),
                    data: (sections) {
                      final nonEmpty = sections
                          .where((sec) => sec.items.isNotEmpty)
                          .toList();
                      if (nonEmpty.isEmpty) {
                        return Padding(
                          padding:
                              const EdgeInsets.fromLTRB(20, 32, 20, 32),
                          child: Text(
                            'Nothing in this category right now.',
                            style: SunohType.sans(
                                fontSize: 13, color: c.fgMute),
                          ),
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < nonEmpty.length; i++) ...[
                            const SizedBox(height: 28),
                            _RelatedSection(
                              section: nonEmpty[i],
                              colors: c,
                            ),
                          ],
                          const SizedBox(height: 24),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _StickyHeader(
                title: widget.title,
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
