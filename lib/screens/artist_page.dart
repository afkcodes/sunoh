// The artist page: a full-bleed photo hero with the name set large over it,
// Follow and play, the ranked "Popular" list, the discography shelf and an
// About card.
//
// Shared by the sunoh-api artist and the YouTube one. The YouTube artist used
// to borrow the album body, which made it a playlist with a portrait for a
// cover — and saved it to the library as a playlist.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remixicon/remixicon.dart';

import '../api/dto.dart';
import '../data/models.dart';
import '../overlays/hero_menu_sheet.dart';
import '../providers/app_state_provider.dart';
import '../providers/palette_provider.dart';
import '../share/share_link.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/motion.dart';
import '../widgets/ui.dart';
import 'artist_hero.dart';
import 'detail_chrome.dart';
import 'detail_hero.dart';
import 'detail_shelf.dart';
import 'detail_track_row.dart';

class ArtistPage extends ConsumerWidget {
  const ArtistPage({
    super.key,
    required this.colors,
    required this.artist,
    required this.topSongs,
    this.imageUrl,
    this.albums = const [],
    this.sections = const [],
    this.stats,
    this.bio,
    this.popularLimit,
    this.onRadio,
    this.onDownloadAll,
    this.onAddToQueue,
  });

  final SunohColors colors;

  /// The artist as a library item — what Follow saves, what the menu and
  /// Share describe.
  final FeedItem artist;

  /// The artist's picture, resolved once by the caller — `artwork` sorts the
  /// image list on every read.
  final String? imageUrl;
  final List<FeedItem> topSongs;
  final List<FeedItem> albums;
  final List<HomeSection> sections;

  /// The followers / listeners line under the name.
  final String? stats;
  final String? bio;

  /// How many top songs "Popular" lists; null lists them all.
  final int? popularLimit;
  final VoidCallback? onRadio;
  final VoidCallback? onDownloadAll;
  final VoidCallback? onAddToQueue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    final s = ref.read(appStateProvider);
    final url = imageUrl ?? '';
    final palette = url.isEmpty
        ? null
        : ref.watch(artPaletteProvider(url)).value;
    final accent = s.themedAccent(palette?.accent ?? artAccent(artist.id));
    final labels = TrackLabels.of(topSongs);
    final count = math.min(popularLimit ?? topSongs.length, topSongs.length);
    final queueRef = DetailRef('artist', artist.id, source: artist.source);
    final label = 'TOP SONGS · ${artist.title}';
    final aboutText = bio ?? '';

    return DetailPage(
      colors: c,
      colour: accent,
      title: artist.title,
      overMedia: true,
      actions: [
        // The share link schema resolves sunoh-api ids only; a YouTube
        // artist shares from its menu, as it always has.
        if (artist.source != 'youtube')
          BarAction(
            RemixIcons.upload_2_line,
            () => shareSunohLink(
              kind: 'artist',
              id: artist.id,
              title: artist.title,
              subtitle: artist.subtitle,
              source: artist.source,
            ),
            size: 20,
          ),
      ],
      builder: (scroll) => [
        SliverToBoxAdapter(
          child: ArtistHero(
            colors: c,
            artist: artist,
            imageUrl: imageUrl,
            stats: stats,
            scroll: scroll,
          ),
        ),
        SliverToBoxAdapter(
          child: FadeSlideIn(
            index: 2,
            child: _actions(context, accent, queueRef, label),
          ),
        ),
        if (count > 0) ...[
          SliverToBoxAdapter(
            child: SectionHeader(
              title: 'Popular',
              colors: c,
              padding: const EdgeInsets.fromLTRB(16, 22, 16, 14),
            ),
          ),
          SliverList.builder(
            itemCount: count,
            itemBuilder: (context, i) {
              final row = DetailTrackRow(
                n: i + 1,
                ranked: true,
                showArt: true,
                song: topSongs[i],
                subtitle: labels.subtitles[i],
                duration: labels.durations[i],
                colors: c,
                accent: accent,
                sourceRef: queueRef,
                onTap: () => s.playApiQueue(
                  topSongs,
                  i,
                  sourceLabel: label,
                  sourceRef: queueRef,
                ),
              );
              return i < 6 ? Entrance(index: 3 + i, child: row) : row;
            },
          ),
        ],
        if (albums.isNotEmpty)
          SliverToBoxAdapter(
            child: DetailShelf(
              section: HomeSection(
                heading: 'Discography',
                items: albums,
                source: artist.source,
              ),
              colors: c,
            ),
          ),
        for (final section in sections)
          SliverToBoxAdapter(
            child: DetailShelf(section: section, colors: c),
          ),
        if (aboutText.isNotEmpty)
          SliverToBoxAdapter(
            child: _AboutCard(
              colors: c,
              artist: artist,
              imageUrl: imageUrl,
              text: aboutText,
            ),
          ),
      ],
    );
  }

  Widget _actions(
    BuildContext context,
    Color accent,
    DetailRef queueRef,
    String label,
  ) {
    final c = colors;
    return Consumer(
      builder: (context, ref, _) {
        // Watched so the disc flips to pause while this artist's songs are
        // the queue, and a tap then toggles rather than restarting.
        final live = ref.watch(appStateProvider);
        final here =
            live.apiSourceRef?.kind == 'artist' &&
            live.apiSourceRef?.id == artist.id;
        final empty = topSongs.isEmpty;
        return DetailActions(
          colors: c,
          colour: accent,
          playing: here && live.isPlaying,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          leading: [
            FollowPill(
              colors: c,
              following: live.isSavedArtistId(artist.id),
              onTap: () => live.toggleSaved(artist),
            ),
            IconBtn(
              icon: RemixIcons.more_fill,
              color: c.fg,
              onTap: () => showHeroMenuSheet(context, entity: artist),
            ),
            if (onRadio != null)
              IconBtn(
                icon: RemixIcons.sound_module_line,
                color: c.fg,
                onTap: onRadio,
              ),
            if (onDownloadAll != null && !empty)
              IconBtn(
                icon: RemixIcons.download_2_line,
                color: c.fg,
                onTap: onDownloadAll,
              ),
            if (onAddToQueue != null && !empty)
              IconBtn(
                icon: RemixIcons.add_circle_line,
                color: c.fg,
                onTap: onAddToQueue,
              ),
          ],
          onShuffle: empty
              ? null
              : () => live.playShuffled(topSongs, sourceLabel: label),
          onPlay: empty && !here
              ? null
              : () {
                  if (here) {
                    live.playPause();
                    return;
                  }
                  live.playApiQueue(
                    topSongs,
                    0,
                    sourceLabel: label,
                    sourceRef: queueRef,
                  );
                },
        );
      },
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard({
    required this.colors,
    required this.artist,
    required this.text,
    this.imageUrl,
  });
  final SunohColors colors;
  final FeedItem artist;
  final String text;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.only(top: 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: 'About', colors: c),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(12),
            decoration: squircleDecoration(
              radius: SunohRadius.card,
              color: c.surface,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SunohArt(
                  id: artist.id,
                  imageUrl: imageUrl,
                  size: 96,
                  radius: SunohRadius.tile,
                  shadow: false,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        artist.title,
                        style: SunohType.sans(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: c.fg,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        text,
                        style: SunohType.sans(
                          fontSize: 13,
                          color: c.fgDim,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
