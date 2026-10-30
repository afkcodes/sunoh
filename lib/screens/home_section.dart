// One section of the music feed: its header, then whichever shape its items
// call for — the hero cards, a row of covers, a row of circles or the channel
// grid, with the section's songs as a grid of song cards under it — and what
// a tap on any of them does.
//
// Split out of home_screen.dart (954 lines) along the seam it already had:
// the screen composes sections, and this decides how one section looks.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dto.dart';
import '../audio/radio_actions.dart';
import '../data/models.dart';
import '../providers/app_state_provider.dart';
import '../router/router.dart';
import '../theme/tokens.dart';
import '../widgets/cover_hero.dart';
import '../widgets/ui.dart';
import 'feed_tiles.dart';
import 'home_channels.dart';
import 'home_hero.dart';
import 'home_song_grid.dart';

/// Songs shown in the grid before it defers to "See all". Four full columns.
const int _kSongMax = HomeSongGrid.rows * 4;

/// Covers shown in a row before it defers to "See all".
const int _kRowMax = 10;

enum _Kind { channels, circles, covers }

/// What a section's items make it, worked out once per section rather than
/// on every rebuild — the feed rebuilds whenever app state moves, and
/// scanning and copying item lists each time is exactly the build-time work
/// the performance rules keep out.
///
/// Songs always leave the rail for the song grid under it. Drawn as covers, a
/// song looked like an album though one starts playback and the other opens
/// a screen, so a mixed section is split by type rather than drawn in the
/// order the API sent.
class _Shape {
  _Shape._(HomeSection section) {
    final all = section.items;
    final allSongs = [
      for (final it in all)
        if (it.type == 'song') it,
    ];
    final rest = [
      for (final it in all)
        if (it.type != 'song') it,
    ];
    songs = allSongs.take(_kSongMax).toList();
    rail = rest.isEmpty ? null : _kindOf(rest);
    visible = rest.take(_kRowMax).toList();
    hasMore = allSongs.length > _kSongMax || rest.length > _kRowMax;
    // Channel grids always held fifteen while See all appeared past ten;
    // kept as it was.
    channels = rail == _Kind.channels ? rest.take(15).toList() : const [];
  }

  static final Expando<_Shape> _cache = Expando('home section shape');
  static _Shape of(HomeSection s) => _cache[s] ??= _Shape._(s);

  /// The shape of everything that is not a song; null when only songs.
  late final _Kind? rail;
  late final List<FeedItem> visible;
  late final List<FeedItem> songs;
  late final bool hasMore;
  late final List<FeedItem> channels;

  static _Kind _kindOf(List<FeedItem> items) {
    bool all(bool Function(FeedItem) test) => items.every(test);
    if (all((it) => it.type == 'channel')) return _Kind.channels;
    if (all(
      (it) =>
          it.type == 'artist' ||
          it.type == 'radio_station' ||
          it.type == 'radio',
    )) {
      return _Kind.circles;
    }
    return _Kind.covers;
  }
}

/// True for a row of nothing but playlists — the made-for-you shape, which
/// the feed draws once with the wider tile.
bool isPlaylistRow(HomeSection section) =>
    section.items.isNotEmpty &&
    section.items.every((it) => it.type == 'playlist');

class HomeFeedSection extends ConsumerWidget {
  const HomeFeedSection({
    super.key,
    required this.section,
    required this.colors,
    this.featured = false,
    this.wide = false,
  });

  final HomeSection section;
  final SunohColors colors;

  /// First in the feed: a row of covers becomes the hero cards.
  final bool featured;

  /// Draw the covers at the featured-mix width.
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    final shape = _Shape.of(section);
    final rail = shape.rail;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: section.heading,
          colors: c,
          onSeeAll: shape.hasMore ? () => context.openSection(section) : null,
        ),
        if (rail != null) _rail(context, ref, rail, shape),
        if (rail != null && shape.songs.isNotEmpty) const SizedBox(height: 16),
        if (shape.songs.isNotEmpty)
          HomeSongGrid(
            songs: shape.songs,
            colors: c,
            sectionLabel: section.heading,
          ),
      ],
    );
  }

  Widget _rail(BuildContext context, WidgetRef ref, _Kind kind, _Shape shape) {
    final c = colors;
    void open(FeedItem item) => _routeTap(context, ref, item);
    return switch (kind) {
      _Kind.channels => ChannelGrid(
        items: shape.channels,
        colors: c,
        sectionSource: section.source,
      ),
      _Kind.covers when featured => HomeHero(
        items: shape.visible,
        colors: c,
        onTap: open,
        heroScope: section.heading,
      ),
      _ => FeedTileRow(
        items: shape.visible,
        colors: c,
        onTap: open,
        width: wide ? kTileWideWidth : kTileWidth,
        circles: kind == _Kind.circles,
        // Circles carried only a name before and still do.
        subtitleOf: kind == _Kind.circles ? null : _subtitle,
        heroScope: section.heading,
      ),
    };
  }

  static String? _subtitle(FeedItem item) => item.displaySubtitle;

  /// The tapped cover, for the page it opens to fly in — only when the rail
  /// gave that cover a tag, so a page never waits on a cover that is not
  /// coming.
  CoverHeroRef? _hero(FeedItem item) => feedHeroRef(
    section.heading,
    _Shape.of(section).visible,
    item,
    // The hero cards are the only covers a featured section draws.
    featured ? kHeroArtSize : (wide ? kTileWideWidth : kTileWidth),
  );

  void _routeTap(BuildContext context, WidgetRef ref, FeedItem item) {
    final s = ref.read(appStateProvider);
    final src = item.source ?? section.source;

    // YouTube items are routed separately: their ids are YouTube browse ids
    // (VLRDCLAK5uy_…), which sunoh-api's album/playlist endpoints can't
    // resolve. Songs still fall through to the shared `song` case below —
    // those play via the resolver's native YouTube tier.
    if (src == 'youtube' && item.type != 'song') {
      context.openYtItem(item, hero: _hero(item));
      return;
    }

    switch (item.type) {
      case 'album':
      case 'playlist':
        context.openRef(
          DetailRef(item.type, item.id, source: src),
          hero: _hero(item),
        );
      case 'artist':
        // Pure artist tiles navigate to the artist screen. The
        // "Recommended Artist Stations" tiles are a separate concept
        // — they come back as `type='radio_station'` with
        // `stationType='artist'` (via the API's mapSaavnChannel
        // rebrand) and are caught by the radio_station case below.
        context.openRef(DetailRef('artist', item.id, source: src));
      case 'radio_station':
      case 'radio':
        // Radio stations need a two-step session bootstrap (create
        // session → fetch first batch of songs). Shared with the channel
        // detail screen via lib/audio/radio_actions.dart so both tap
        // sources behave identically.
        startRadioStation(ref, item, provider: src);
      case 'channel':
        // Channels (the Saavn "Browse" row) aren't radio stations and
        // can't be opened via /music/radio/session — but the backend
        // routes them through the occasion detail endpoint just fine
        // (/music/occasions/<channelId>?provider=saavn returns the
        // expected sections). Re-use OccasionScreen for the layout.
        context.openOccasion(item);
      case 'occasion':
        context.openOccasion(item);
      default:
        s.flashToast(item.type);
    }
  }
}
