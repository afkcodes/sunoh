// The album page body: hero, actions, numbered tracks, then the description
// and related shelves.
//
// Albums, playlists and YouTube playlists all render through it,
// each wiring its own response's fields into the hero (detail_screens.dart,
// ytmusic_screens.dart).

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remixicon/remixicon.dart';

import '../api/dto.dart';
import '../audio/download_store.dart';
import '../data/models.dart';
import '../overlays/hero_menu_sheet.dart';
import '../providers/app_state_provider.dart';
import '../providers/downloads_provider.dart';
import '../providers/palette_provider.dart';
import '../share/share_link.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/cover_hero.dart';
import '../widgets/motion.dart';
import '../widgets/ui.dart';
import 'detail_chrome.dart';
import 'detail_hero.dart';
import 'detail_shelf.dart';
import 'detail_track_row.dart';

/// The album page: hero, actions, numbered tracks, then the description and
/// related shelves. Albums, playlists and YouTube playlists all
/// render through it.
class AlbumLikeBody extends ConsumerStatefulWidget {
  const AlbumLikeBody({
    super.key,
    required this.colors,
    required this.id,
    required this.title,
    required this.songs,
    required this.sections,
    required this.showAlbumArtInRow,
    required this.sourceRef,
    this.imageUrl,
    this.kindLabel,
    this.metaExtra = const [],
    this.byline,
    this.bylineArt,
    this.songCount,
    this.countNoun = 'song',
    this.description,
    this.onRadio,
    this.hero,
  });

  /// The cover this page was opened from (see DetailCover).
  final CoverHeroRef? hero;

  final SunohColors colors;
  final String id;
  final String title;

  /// The detail-ref of *this* screen — forwarded into each track row's menu
  /// sheet so the "Go to album / Go to playlist" navigation row can re-open
  /// the source, and into the queue so the play disc knows it is playing.
  final DetailRef sourceRef;
  final String? imageUrl;

  /// "Album", "Playlist" — the meta line's first word.
  final String? kindLabel;

  /// Whatever else the source knows that belongs in the meta line: a year,
  /// a follower count.
  final List<String> metaExtra;

  /// The artists, owner or author, under the title.
  final String? byline;
  final String? bylineArt;

  /// The source's own track count, when it ships fewer tracks than it has.
  final int? songCount;
  final String countNoun;
  final String? description;
  final List<FeedItem> songs;
  final List<HomeSection> sections;
  final bool showAlbumArtInRow;

  /// Optional "start a station from this" action, surfaced in the actions
  /// row. Null for sources that can't seed one.
  final VoidCallback? onRadio;

  @override
  ConsumerState<AlbumLikeBody> createState() => _AlbumLikeBodyState();
}

class _AlbumLikeBodyState extends ConsumerState<AlbumLikeBody> {
  late String _note;
  late String _meta;
  late FeedItem _entity;

  // What the library saves this as.
  String get _kind => widget.showAlbumArtInRow ? 'playlist' : 'album';

  @override
  void initState() {
    super.initState();
    _derive();
  }

  @override
  void didUpdateWidget(AlbumLikeBody old) {
    super.didUpdateWidget(old);
    final w = widget;
    if (old.description != w.description ||
        !identical(old.songs, w.songs) ||
        old.title != w.title ||
        old.imageUrl != w.imageUrl ||
        old.kindLabel != w.kindLabel ||
        old.songCount != w.songCount ||
        !listEquals(old.metaExtra, w.metaExtra)) {
      _derive();
    }
  }

  // The meta line, the stripped description and the library item, worked out
  // once per change rather than on every rebuild — the parent rebuilds on
  // every app-state change.
  void _derive() {
    final w = widget;
    _note = _stripHtml(w.description ?? '');
    final count = w.songs.isEmpty && w.songCount == null
        ? null
        : TrackLabels.of(w.songs).countLine(w.countNoun, count: w.songCount);
    _meta = joinMeta([w.kindLabel, ...w.metaExtra, count]);
    _entity = FeedItem(
      id: w.id,
      title: w.title,
      type: _kind,
      image: (w.imageUrl ?? '').isEmpty
          ? const []
          : [ApiImage(quality: 'hero', link: w.imageUrl!)],
      // Source MUST round-trip into the saved FeedItem so the library can
      // re-open the detail via `?provider=…`. Without it a gaana album saved
      // and re-opened from Library hit saavn by default and 404'd.
      source: w.sourceRef.source,
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final c = w.colors;
    final s = ref.read(appStateProvider);
    final url = w.imageUrl ?? '';
    // Prefer the extracted vibrant colour; fall back to the deterministic
    // accent. Through themedAccent: either one raw is a pastel on light.
    final palette = url.isEmpty
        ? null
        : ref.watch(artPaletteProvider(url)).value;
    final accent = s.themedAccent(palette?.accent ?? artAccent(w.id));
    final songs = w.songs;
    final labels = TrackLabels.of(songs);
    final label = '${_kind.toUpperCase()} · ${w.title}';
    // Only kinds the share link schema knows; the menu covers the rest.
    final shareable =
        (w.sourceRef.kind == 'album' || w.sourceRef.kind == 'playlist') &&
        w.sourceRef.source != 'youtube';

    return DetailPage(
      colors: c,
      colour: accent,
      title: w.title,
      actions: [
        if (shareable)
          BarAction(
            RemixIcons.upload_2_line,
            () => shareSunohLink(
              kind: _kind,
              id: w.id,
              title: w.title,
              subtitle: w.byline,
              source: w.sourceRef.source,
            ),
            size: 20,
          ),
      ],
      builder: (scroll) => [
        SliverToBoxAdapter(
          child: DetailHero(
            colors: c,
            colour: accent,
            scroll: scroll,
            cover: DetailCover(id: w.id, imageUrl: w.imageUrl, hero: w.hero),
            title: w.title,
            byline: w.byline,
            bylineArt: w.bylineArt,
            meta: _meta,
          ),
        ),
        SliverToBoxAdapter(
          child: FadeSlideIn(index: 3, child: _actions(accent, label)),
        ),
        SliverPadding(
          padding: const EdgeInsets.only(top: 8),
          sliver: SliverList.builder(
            itemCount: songs.length,
            itemBuilder: (context, i) {
              final row = DetailTrackRow(
                n: i + 1,
                song: songs[i],
                subtitle: labels.subtitles[i],
                duration: labels.durations[i],
                colors: c,
                accent: accent,
                showArt: w.showAlbumArtInRow,
                sourceRef: w.sourceRef,
                onTap: () => s.playApiQueue(
                  songs,
                  i,
                  sourceLabel: label,
                  sourceRef: w.sourceRef,
                ),
              );
              return i < 6 ? Entrance(index: 4 + i, child: row) : row;
            },
          ),
        ),
        if (_note.isNotEmpty)
          SliverToBoxAdapter(
            child: DetailNote(colors: c, text: _note),
          ),
        for (final section in w.sections)
          SliverToBoxAdapter(
            child: DetailShelf(section: section, colors: c),
          ),
      ],
    );
  }

  Widget _actions(Color accent, String label) {
    final w = widget;
    final c = w.colors;
    final songs = w.songs;
    return Consumer(
      builder: (context, ref, _) {
        // Watched, not read: the disc turns to pause while this collection
        // is the queue, and a tap then toggles instead of restarting.
        final live = ref.watch(appStateProvider);
        final playing = live.apiSourceRef;
        final here =
            playing?.kind == w.sourceRef.kind && playing?.id == w.sourceRef.id;
        final entries = ref.watch(downloadEntriesProvider).asData?.value;
        final offline = songs.isNotEmpty && _allDone(songs, entries);
        return DetailActions(
          colors: c,
          colour: accent,
          playing: here && live.isPlaying,
          leading: [
            IconBtn(
              icon: live.isSaved(_entity)
                  ? RemixIcons.heart_3_fill
                  : RemixIcons.heart_3_line,
              color: c.fg,
              onTap: () => live.toggleSaved(_entity),
            ),
            if (songs.isNotEmpty) ...[
              // Takes the page colour once every track is on the device.
              IconBtn(
                icon: RemixIcons.download_2_line,
                color: offline ? accent : c.fg,
                onTap: () {
                  ref.read(downloadManagerProvider).enqueueAll(songs);
                  live.flashToast('Queued ${songs.length} tracks');
                },
              ),
              IconBtn(
                icon: RemixIcons.add_circle_line,
                color: c.fg,
                onTap: () => live.addApiSongsToQueue(songs),
              ),
            ],
            if (w.onRadio != null)
              IconBtn(
                icon: RemixIcons.sound_module_line,
                color: c.fg,
                onTap: w.onRadio,
              ),
            IconBtn(
              icon: RemixIcons.more_fill,
              color: c.fg,
              onTap: () =>
                  showHeroMenuSheet(context, entity: _entity, songs: songs),
            ),
          ],
          onShuffle: songs.isEmpty
              ? null
              : () {
                  // A random start and shuffle on in one go, so the first
                  // track is unpredictable too — starting at #1 felt broken.
                  final start =
                      DateTime.now().microsecondsSinceEpoch % songs.length;
                  live.playApiQueue(
                    songs,
                    start,
                    sourceLabel: label,
                    sourceRef: w.sourceRef,
                  );
                  if (!live.shuffle) live.toggleShuffle();
                },
          onPlay: songs.isEmpty && !here
              ? null
              : () {
                  if (here) {
                    // Resume or pause — never restart from track 1 while
                    // the queue is already this collection.
                    live.playPause();
                    return;
                  }
                  live.playApiQueue(
                    songs,
                    0,
                    sourceLabel: label,
                    sourceRef: w.sourceRef,
                  );
                },
        );
      },
    );
  }

  static bool _allDone(List<FeedItem> songs, List<DownloadEntry>? entries) {
    if (entries == null) return false;
    final done = {
      for (final e in entries)
        if (e.state == DownloadState.done) e.id,
    };
    return songs.every((sg) => done.contains(sg.id));
  }
}

/// Decode the limited subset of HTML that backend descriptions ship with —
/// Gaana / Saavn responses include raw `<p>`, `<span style="…">` wrappers
/// and entity-encoded apostrophes/quotes. Strip tags, collapse whitespace and
/// decode the few entities that actually show up. Not a full HTML parser.
String _stripHtml(String raw) {
  if (raw.isEmpty) return raw;
  // Tags first, so an attribute value containing `&` isn't touched by the
  // entity step.
  var s = raw.replaceAll(RegExp(r'<[^>]*>'), '');
  s = s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'");
  // Numeric entities (&#1234; / &#x1F4A9;).
  s = s.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
    final code = int.tryParse(m.group(1)!);
    return code == null ? m.group(0)! : String.fromCharCode(code);
  });
  s = s.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
    final code = int.tryParse(m.group(1)!, radix: 16);
    return code == null ? m.group(0)! : String.fromCharCode(code);
  });
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}
