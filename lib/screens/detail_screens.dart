// Detail screens wired to the live sunoh-api: album, playlist, artist and
// the browse-category (occasion) page, plus their error state. The loading
// state, which the YouTube screens reuse, is detail_loading.dart.
//
// The pages themselves live next door (album_body.dart, artist_page.dart,
// and the frame in detail_chrome.dart / detail_hero.dart); this file is the
// data wiring: which fields of each response become the title, the byline,
// the meta line and the lists.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dto.dart';
import '../data/models.dart';
import '../providers/app_state_provider.dart';
import '../providers/detail_providers.dart';
import '../providers/palette_provider.dart';
import '../providers/search_provider.dart';
import '../theme/tokens.dart';
import '../widgets/cover_hero.dart';
import '../widgets/motion.dart';
import '../widgets/ui.dart';
import 'album_body.dart';
import 'artist_page.dart';
import 'detail_chrome.dart';
import 'detail_hero.dart';
import 'detail_loading.dart';
import 'detail_shelf.dart';

// ── Album / Playlist ────────────────────────────────────────────────────────
class AlbumScreen extends ConsumerWidget {
  const AlbumScreen({
    super.key,
    required this.id,
    required this.kind,
    this.source,
    this.hero,
  });
  final String id;
  final String kind; // 'album' | 'playlist'
  final String? source; // 'saavn' | 'gaana' | 'spotify'

  /// The cover this page was opened from, which flies into its big cover.
  final CoverHeroRef? hero;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final key = (id: id, source: source);

    if (kind == 'playlist') {
      final async = ref.watch(playlistProvider(key));
      if (async.isLoading) return DetailLoading(colors: c, hero: hero);
      if (async.hasError) {
        return _DetailError(
          colors: c,
          message: '${async.error}',
          onRetry: () => ref.invalidate(playlistProvider(key)),
        );
      }
      final pl = async.requireValue;
      final art = pl.artwork;
      // Keep the loader up until the palette has resolved too — otherwise
      // the hero would briefly render with the deterministic accent and then
      // snap to the extracted tint, which reads as a half-loaded page.
      if (!paletteSettled(ref, art)) {
        return DetailLoading(colors: c, hero: hero);
      }
      return AlbumLikeBody(
        colors: c,
        id: pl.id,
        title: pl.title,
        imageUrl: art,
        kindLabel: 'Playlist',
        byline: pl.subtitle,
        metaExtra: [
          if ((pl.followers ?? '').isNotEmpty) '${pl.followers} followers',
        ],
        songCount: int.tryParse(pl.songCount ?? ''),
        description: pl.description,
        songs: pl.songs,
        sections: pl.sections,
        showAlbumArtInRow: true, // playlists often mix artists
        sourceRef: DetailRef('playlist', pl.id, source: source),
        hero: hero,
      );
    }

    final async = ref.watch(albumProvider(key));
    if (async.isLoading) return DetailLoading(colors: c, hero: hero);
    if (async.hasError) {
      return _DetailError(
        colors: c,
        message: '${async.error}',
        onRetry: () => ref.invalidate(albumProvider(key)),
      );
    }
    final al = async.requireValue;
    final art = al.artwork;
    if (!paletteSettled(ref, art)) return DetailLoading(colors: c, hero: hero);
    final lead = al.artists.isEmpty ? null : al.artists.first.image;
    return AlbumLikeBody(
      colors: c,
      id: al.id,
      title: al.title,
      imageUrl: art,
      kindLabel: 'Album',
      byline: al.artists
          .take(2)
          .map((a) => a.name)
          .where((n) => n.isNotEmpty)
          .join(', '),
      bylineArt: (lead ?? const []).isEmpty ? null : lead!.first.link,
      metaExtra: [
        if ((al.year ?? '').isNotEmpty)
          al.year!
        else if ((al.releaseDate ?? '').isNotEmpty)
          al.releaseDate!,
      ],
      songCount: int.tryParse(al.songCount ?? ''),
      description: al.description,
      songs: al.songs,
      sections: al.sections,
      showAlbumArtInRow: false,
      sourceRef: DetailRef('album', al.id, source: source),
      hero: hero,
    );
  }
}

/// Whether the artwork's palette has been extracted yet.
///
/// Detail screens hold their loader until this is true. Rendering the hero
/// before it resolves means painting with the deterministic accent and then
/// snapping to the extracted tint, which reads as a half-loaded page.
///
/// Public because the YouTube screens reuse [AlbumLikeBody] and therefore need
/// to wait on exactly the same thing.
bool paletteSettled(WidgetRef ref, String? url) {
  if (url == null || url.isEmpty) return true;
  return !ref.watch(artPaletteProvider(url)).isLoading;
}

// ── Error ─────────────────────────────────────────────────────────────────

class _DetailError extends StatelessWidget {
  const _DetailError({
    required this.colors,
    required this.message,
    required this.onRetry,
  });
  final SunohColors colors;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return ColoredBox(
      color: c.bg,
      child: Stack(
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Couldn't load this.",
                    textAlign: TextAlign.center,
                    style: SunohType.heading(fontSize: 22, color: c.fg),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: SunohType.sans(fontSize: 13, color: c.fgMute),
                  ),
                  const SizedBox(height: 20),
                  Pressable(
                    onTap: onRetry,
                    child: Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      alignment: Alignment.center,
                      decoration: squircleDecoration(
                        radius: 20,
                        color: c.surface2,
                      ),
                      child: Text(
                        'Try again',
                        style: SunohType.sans(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: c.fg,
                        ),
                      ),
                    ),
                  ),
                ],
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
}

// ── Artist ──────────────────────────────────────────────────────────────────
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
    if (async.isLoading) return DetailLoading(colors: c, round: true);
    if (async.hasError) {
      return _DetailError(
        colors: c,
        message: '${async.error}',
        onRetry: () => ref.invalidate(artistProvider(key)),
      );
    }
    final artist = async.requireValue;
    final art = artist.artwork;
    if (!paletteSettled(ref, art)) {
      return DetailLoading(colors: c, round: true);
    }
    final followers = artist.followers ?? '';
    return ArtistPage(
      colors: c,
      artist: FeedItem(
        id: artist.id,
        title: artist.name,
        type: 'artist',
        image: artist.image,
        subtitle: artist.subtitle,
        source: artist.source,
      ),
      imageUrl: art,
      topSongs: artist.topSongs,
      albums: artist.albums,
      sections: artist.sections,
      stats: joinMeta([
        if (followers.isNotEmpty) '$followers followers',
        artist.role ?? artist.subtitle,
      ]),
      bio: artist.bio,
      popularLimit: 5,
    );
  }
}

// ── Occasion (browse-category collections from /music/occasions/:slug) ──────
// The album page's hero, but no track list or play action of its own:
// occasions are containers of sections (other playlists, songs, albums).
class OccasionScreen extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final url = imageUrl ?? '';
    final palette = url.isEmpty
        ? null
        : ref.watch(artPaletteProvider(url)).value;
    final accent = palette == null ? c.accent : s.themedAccent(palette.accent);
    final async = ref.watch(
      occasionDetailProvider((slug: slug, provider: source)),
    );
    final from = source.isEmpty
        ? ''
        : '${source[0].toUpperCase()}${source.substring(1)}';

    Widget status(String text) => SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 30, 16, 0),
        child: Text(text, style: SunohType.sans(fontSize: 13, color: c.fgMute)),
      ),
    );

    return DetailPage(
      colors: c,
      colour: accent,
      title: title,
      builder: (scroll) => [
        SliverToBoxAdapter(
          child: DetailHero(
            colors: c,
            colour: accent,
            scroll: scroll,
            cover: DetailCover(id: slug, imageUrl: imageUrl),
            title: title,
            meta: joinMeta(['Category', from]),
          ),
        ),
        ...async.when(
          loading: () => [status('Loading…')],
          error: (e, _) => [status('Couldn’t load “$title”.\n$e')],
          data: (sections) {
            final nonEmpty = [
              for (final sec in sections)
                if (sec.items.isNotEmpty) sec,
            ];
            if (nonEmpty.isEmpty) {
              return [status('Nothing in this category right now.')];
            }
            return [
              for (final sec in nonEmpty)
                SliverToBoxAdapter(
                  child: DetailShelf(section: sec, colors: c),
                ),
            ];
          },
        ),
      ],
    );
  }
}
