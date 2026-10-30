// One song in a detail page's list — an album's numbered track, a playlist
// row with its own cover, a ranked "Popular" row on an artist.
//
// Album, playlist, liked songs, the user's own playlists, an artist's top
// songs and the history list all drew this row from their own private copy,
// and the copies disagreed on padding, art size and which buttons were on the
// right. One row means a song looks the same wherever it is listed.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remixicon/remixicon.dart';

import '../api/dto.dart';
import '../data/models.dart';
import '../overlays/track_menu_sheet.dart';
import '../providers/app_state_provider.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/download_glyph.dart';
import '../widgets/motion.dart';
import '../widgets/playing_bars.dart';
import '../widgets/ui.dart';
import 'detail_chrome.dart' show hoursMinutes;

/// Display strings for a song list, worked out once per list rather than in
/// every row's build: the artist line, the "m:ss" duration and the running
/// total. Keyed by the list's identity, which the app replaces rather than
/// mutates when a list changes, so a new list is a new entry.
class TrackLabels {
  TrackLabels._(List<FeedItem> songs)
    : subtitles = [for (final s in songs) _artists(s)],
      durations = [for (final s in songs) _clock(s.duration)] {
    var total = 0;
    var known = true;
    for (final s in songs) {
      final n = int.tryParse(s.duration ?? '');
      if (n == null || n <= 0) known = false;
      total += n ?? 0;
    }
    totalSeconds = known ? total : 0;
  }

  static final Expando<TrackLabels> _cache = Expando<TrackLabels>();
  static final TrackLabels _empty = TrackLabels._(const []);

  static TrackLabels of(List<FeedItem> songs) {
    if (songs.isEmpty) return _empty;
    final hit = _cache[songs];
    // The length check is a guard, not the key: a list grown in place would
    // otherwise index past its cached labels.
    if (hit != null && hit.subtitles.length == songs.length) return hit;
    return _cache[songs] = TrackLabels._(songs);
  }

  final List<String> subtitles;
  final List<String?> durations;

  /// Sum of the durations, or 0 when any song's is unknown — a partial sum
  /// would under-report the running time.
  late final int totalSeconds;

  String? _line;
  String? _lineNoun;

  /// "13 songs, 1 h 5 min". [count] overrides the list length when the source
  /// reports more than it shipped; the running time is then left off, since
  /// it would only cover the part that arrived.
  String countLine(String noun, {int? count}) {
    if (_line != null && _lineNoun == noun && count == null) return _line!;
    final n = count ?? subtitles.length;
    final words = '$n $noun${n == 1 ? '' : 's'}';
    final whole = count == null || count == subtitles.length;
    final line = totalSeconds > 0 && whole
        ? '$words, ${hoursMinutes(totalSeconds)}'
        : words;
    if (count == null) {
      _line = line;
      _lineNoun = noun;
    }
    return line;
  }

  static String _artists(FeedItem s) {
    final names = (s.artists ?? const <ApiArtistRef>[])
        .map((a) => a.name.trim())
        .where((n) => n.isNotEmpty)
        .take(2)
        .join(', ');
    // Songs without artist refs (on-device tracks, mostly) carry their
    // artist in the subtitle instead.
    return names.isNotEmpty ? names : (s.subtitle ?? '').trim();
  }

  static String? _clock(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final n = int.tryParse(raw);
    if (n == null) return raw; // already pre-formatted upstream
    return '${n ~/ 60}:${(n % 60).toString().padLeft(2, '0')}';
  }
}

/// A song row. [n] numbers it (null for an unnumbered list); [ranked] is the
/// artist page's "Popular" style, a heavier number before the cover.
class DetailTrackRow extends ConsumerWidget {
  const DetailTrackRow({
    super.key,
    required this.song,
    required this.subtitle,
    required this.colors,
    required this.accent,
    required this.onTap,
    this.n,
    this.duration,
    this.showArt = false,
    this.ranked = false,
    this.showLike = true,
    this.showMenu = true,
    this.sourceRef,
    this.sourceLabel,
    this.removeFromUserPlaylistId,
    this.handle,
    this.trailing,
  });

  final FeedItem song;
  final String subtitle;
  final SunohColors colors;

  /// The page's colour: the playing row's title and bars take it.
  final Color accent;
  final VoidCallback onTap;
  final int? n;
  final String? duration;
  final bool showArt;
  final bool ranked;
  final bool showLike;
  final bool showMenu;

  /// Forwarded to the track menu, so it can offer "Go to album/playlist".
  final DetailRef? sourceRef;
  final String? sourceLabel;

  /// Set on the user's own playlists: the menu then offers "Remove".
  final String? removeFromUserPlaylistId;

  /// A drag handle drawn before everything else (reorderable playlists).
  final Widget? handle;

  /// Replaces the like/menu buttons (the downloads list's delete).
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    final s = ref.watch(appStateProvider);
    final isCurrent = s.currentApiSong?.id == song.id;
    final liked = showLike && s.isLikedId(song.id);
    final scale = s.density.scale;
    return Pressable(
      scale: 0.99,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8 * scale),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: showArt ? 48 : 42),
          child: Row(
            children: [
              ?handle,
              if (n != null) ...[
                SizedBox(
                  width: ranked ? 22 : 24,
                  child: Center(
                    child: isCurrent
                        ? PlayingBars(
                            color: accent,
                            size: 12,
                            animate: s.isPlaying,
                          )
                        : Text(
                            '$n',
                            style: ranked
                                ? SunohType.mono(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: c.fgDim,
                                  )
                                : SunohType.mono(fontSize: 13, color: c.fgMute),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              if (showArt) ...[
                SunohArt(
                  id: song.id,
                  imageUrl: song.artwork,
                  size: 48,
                  radius: SunohRadius.row,
                  shadow: false,
                ),
                const SizedBox(width: 12),
              ],
              Expanded(child: _text(c, isCurrent)),
              const SizedBox(width: 8),
              DownloadGlyph(songId: song.id, colors: c),
              if (duration != null)
                Text(
                  duration!,
                  style: SunohType.mono(fontSize: 12.5, color: c.fgMute),
                ),
              if (trailing != null)
                trailing!
              else ...[
                if (showLike)
                  IconBtn(
                    icon: liked
                        ? RemixIcons.heart_3_fill
                        : RemixIcons.heart_3_line,
                    color: liked ? accent : c.fgMute,
                    size: 18,
                    width: 32,
                    height: 32,
                    onTap: () => s.toggleLikedSong(song),
                  ),
                if (showMenu)
                  IconBtn(
                    icon: RemixIcons.more_fill,
                    color: c.fgMute,
                    size: 18,
                    width: 32,
                    height: 32,
                    onTap: () => showTrackMenuSheet(
                      context,
                      song: song,
                      sourceRef: sourceRef,
                      sourceLabel: sourceLabel,
                      removeFromUserPlaylistId: removeFromUserPlaylistId,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _text(SunohColors c, bool isCurrent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          song.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: SunohType.sans(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: isCurrent ? accent : c.fg,
            height: 1.3,
          ),
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 1),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SunohType.sans(fontSize: 13, color: c.fgDim),
          ),
        ],
      ],
    );
  }
}
