// A section's songs on Home: a horizontally snapping grid of song rows,
// three rows tall.
//
// Split out of home_section.dart, which decides what a section holds; this
// decides how its songs look.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dto.dart';
import '../overlays/track_menu_sheet.dart';
import '../providers/app_state_provider.dart';
import '../theme/tokens.dart';
import 'feed_motion.dart';
import 'feed_row.dart';

/// Rows rather than covers because a song tile and a playlist tile looked
/// identical while one started playback and the other opened a screen. In a
/// mixed section the grid sits under the rail of albums and playlists, so the
/// two kinds never share a shape. A tap plays the whole grid from that row,
/// so "Trending" behaves like a playlist you dropped into rather than a
/// single-track queue. Plain rows, unnumbered: a fill behind each row and a
/// rank beside it were tried and read as clutter under the album cards.
///
/// Columns rather than one long list so twelve songs cost a screen's width,
/// not most of a screen's height; the next column deliberately peeks past the
/// right edge, or nothing would say the grid scrolls.
class HomeSongGrid extends ConsumerWidget {
  const HomeSongGrid({
    super.key,
    required this.songs,
    required this.colors,
    required this.sectionLabel,
  });

  final List<FeedItem> songs;
  final SunohColors colors;
  final String sectionLabel;

  /// Rows per column, and so the most songs one screen-width shows.
  static const int rows = 3;

  static const double _rowHeight = 64;
  static const double _peek = 24;
  static const double _gap = 12;

  String get _label => 'HOME · $sectionLabel';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    // Only what the rows show: which song is current and whether it is
    // moving. Anything else in app state passes the grid by.
    final (playingId, isPlaying) = ref.watch(
      appStateProvider.select((s) => (s.currentApiSong?.id, s.isPlaying)),
    );
    final perColumn = math.min(rows, songs.length);
    final columns = (songs.length + rows - 1) ~/ rows;
    final full = MediaQuery.sizeOf(context).width - 32;
    // A single column has nothing to peek at, so it takes the full width.
    final width = columns > 1 ? full - _peek : full;

    Widget row(int i) {
      final song = songs[i];
      return SizedBox(
        height: _rowHeight,
        child: FeedRow(
          item: song,
          colors: c,
          gutter: 0,
          subtitle: song.subtitle,
          meta: durationOf(song),
          playing: song.id == playingId,
          animateBars: isPlaying,
          onTap: () => ref
              .read(appStateProvider)
              .playApiQueue(songs, i, sourceLabel: _label),
          onMore: () =>
              showTrackMenuSheet(context, song: song, sourceLabel: _label),
        ),
      );
    }

    return SizedBox(
      height: _rowHeight * perColumn,
      child: ListView.separated(
        // A scroll position keeps the physics it was made with; a new
        // column width needs a new position.
        key: ValueKey(width),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        physics: SnapPhysics(extent: width + _gap),
        itemCount: columns,
        separatorBuilder: (_, _) => const SizedBox(width: _gap),
        itemBuilder: (_, col) {
          final end = math.min((col + 1) * rows, songs.length);
          return SizedBox(
            width: width,
            child: Column(
              children: [for (var i = col * rows; i < end; i++) row(i)],
            ),
          );
        },
      ),
    );
  }
}
