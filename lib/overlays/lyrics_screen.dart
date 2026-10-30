// Karaoke lyrics page: the line being sung in ink and the rest receded, a
// word-by-word sweep where the source gave word timings, and auto-scroll.
//
// Lyrics are looked up across every source in `lib/api/lyrics/`, keyed by the
// currently playing API song's title + artist + duration. When there's no API
// song (dummy/local catalog tracks, the cold-launch landing track) we fall
// back to the bundled `kLyrics` map so the screen still demos.
//
// This file is the page's chrome: the player's header and the player's
// colour, so opening lyrics reads as turning the player over rather than as a
// new screen. The colour and the scrims that match it are
// `lyrics_backdrop.dart`; the list itself is `lyrics_body.dart`.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:remixicon/remixicon.dart';

import '../api/dto.dart';
import '../audio/lyrics_clock.dart';
import '../data/catalog.dart';
import '../providers/app_state_provider.dart';
import '../providers/lyrics_provider.dart';
import '../providers/palette_provider.dart';
import '../share/share_link.dart';
import '../theme/tokens.dart';
import '../widgets/motion.dart';
import '../widgets/ui.dart';
import 'lyrics_backdrop.dart';
import 'lyrics_body.dart';
import 'lyrics_parts.dart';

class LyricsScreen extends ConsumerStatefulWidget {
  const LyricsScreen({super.key});
  @override
  ConsumerState<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends ConsumerState<LyricsScreen>
    with SingleTickerProviderStateMixin {
  final controller = ScrollController();

  /// Milliseconds, running at vsync — the whole reason word timing is
  /// possible. Lives for the length of the page only; nothing else in the app
  /// needs a clock this fine, and one running behind a closed page would be a
  /// frame callback for nothing.
  LyricsClock? _clock;

  @override
  void initState() {
    super.initState();
    final state = ref.read(appStateProvider);
    final handler = state.audioRepo?.handler;
    if (handler != null) {
      _clock = LyricsClock(
        vsync: this,
        positions: handler.positionStream,
        positionNow: () => handler.position,
        // The AppState instance is stable for the app's life, so this reads a
        // field rather than going through the provider container sixty times
        // a second.
        isPlaying: () => state.isPlaying,
      );
      return;
    }
    // No engine behind the page — the bundled demo lyrics on a dummy track.
    // The 1 Hz tick is all there is, and line-synced demo text is all it has
    // to drive.
    _tick = state.positionTick;
    _tick!.addListener(_onTick);
    _onTick();
  }

  /// Stands in for [_clock] when there is no engine; see [initState].
  final ValueNotifier<int> _fallback = ValueNotifier<int>(0);
  ValueNotifier<int>? _tick;

  void _onTick() => _fallback.value = (_tick?.value ?? 0) * 1000;

  ValueListenable<int> get _positionMs => _clock ?? _fallback;

  /// Tapping a line jumps playback to it.
  ///
  /// AppState.seek deals in whole seconds, so this floors rather than rounds:
  /// landing a hair before the line means its first word is still sung, where
  /// rounding up would clip it.
  void _seekTo(int timeMs) =>
      ref.read(appStateProvider).seek((timeMs / 1000).floor());

  @override
  void dispose() {
    _tick?.removeListener(_onTick);
    _fallback.dispose();
    _clock?.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final track = s.current;
    final apiSong = s.currentApiSong;

    // The artwork's own accent, as the player takes it; the user's accent
    // while the palette is loading or when there is no artwork.
    final url = apiSong?.artwork ?? '';
    final palette = url.isEmpty
        ? null
        : ref.watch(artPaletteProvider(url)).value;
    final tone = s.themedAccent(palette?.accent ?? s.resolvedAccent);

    final query = _queryFor(apiSong);
    // No API song (dummy/local catalog) → keep the bundled lyrics demo.
    final fallbackLines = kLyrics[track.id] ?? kLyrics['t01']!;

    final list = query == null
        ? LyricsBody(
            colors: c,
            lines: fallbackLines,
            synced: true,
            controller: controller,
            clock: _positionMs,
            onSeek: _seekTo,
          )
        : _LiveLyrics(
            query: query,
            colors: c,
            controller: controller,
            clock: _positionMs,
            onSeek: _seekTo,
          );

    return ColoredBox(
      color: c.bg,
      child: LayoutBuilder(
        builder: (context, box) => Stack(
          children: [
            Positioned.fill(
              child: LyricsBackdrop(tone: tone, bg: c.bg),
            ),
            // Bottom left open: the list runs under the navigation bar and
            // fades out there, rather than stopping short of it on a hard
            // edge.
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  FadeSlideIn(
                    child: _Header(
                      title: track.title,
                      artist: track.artist,
                      colors: c,
                      onShare: apiSong == null ? null : () => _share(apiSong),
                    ),
                  ),
                  Expanded(
                    child: FadeSlideIn(
                      index: 1,
                      child: LyricsFadedEdges(
                        tone: tone,
                        bg: c.bg,
                        pageHeight: box.maxHeight,
                        child: list,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The lyrics page is bound to the currently playing song, so share that.
  /// Only an API song has an identity worth sharing; a dummy/local entry has
  /// no share action at all.
  static void _share(FeedItem song) => shareSunohLink(
    kind: 'song',
    id: song.id,
    title: song.title,
    subtitle: song.displaySubtitle ?? song.subtitle,
    source: song.source,
  );

  /// Build a [LyricsQuery] from the currently-playing API song. Returns
  /// null when there isn't enough metadata to attempt a lookup — the UI
  /// then falls back to bundled lyrics.
  LyricsQuery? _queryFor(FeedItem? song) {
    if (song == null) return null;
    final title = song.title.trim();
    if (title.isEmpty) return null;
    final artist = _artistNameOf(song);
    if (artist.isEmpty) return null;
    return LyricsQuery(
      track: title,
      artist: artist,
      durationSec: _durationSecOf(song),
      // SimpMusic matches on the video id, which is the one source that cannot
      // hand back a different edit of the song. Only YouTube tracks have one;
      // for everything else it stays empty and that source sits the race out.
      videoId: song.source == 'youtube' ? song.id : '',
    );
  }

  static String _artistNameOf(FeedItem song) {
    final fromRefs = (song.artists ?? const <ApiArtistRef>[])
        .map((a) => a.name.trim())
        .where((n) => n.isNotEmpty)
        .toList();
    if (fromRefs.isNotEmpty) return fromRefs.first;
    return (song.subtitle ?? '').trim();
  }

  static int? _durationSecOf(FeedItem song) {
    final raw = (song.duration ?? '').trim();
    if (raw.isEmpty) return null;
    return int.tryParse(raw);
  }
}

/// The player's header row: close on the left, what is playing in the middle
/// under a "Lyrics" eyebrow, share on the right.
///
/// The cover that used to sit in a row under the header is gone — the page is
/// already the cover's colour, and the title and artist it carried are here.
class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.artist,
    required this.colors,
    required this.onShare,
  });

  final String title;
  final String artist;
  final SunohColors colors;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            IconBtn(
              icon: RemixIcons.arrow_down_s_line,
              color: c.fg,
              size: 24,
              onTap: () => context.pop(),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  eyebrow('Lyrics', c.fgDim, letterSpacing: 0.8),
                  const SizedBox(height: 2),
                  Text(
                    artist.isEmpty ? title : '$title · $artist',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: SunohType.sans(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: c.fg,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Kept in place, if inert, when there is nothing to share, so the
            // title stays centred on the page.
            IconBtn(
              icon: RemixIcons.share_forward_line,
              color: onShare == null ? c.fgMute : c.fg,
              size: 22,
              onTap: onShare,
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveLyrics extends ConsumerWidget {
  const _LiveLyrics({
    required this.query,
    required this.colors,
    required this.controller,
    required this.clock,
    required this.onSeek,
  });

  final LyricsQuery query;
  final SunohColors colors;
  final ScrollController controller;
  final ValueListenable<int> clock;
  final void Function(int timeMs) onSeek;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(lyricsProvider(query));
    return async.when(
      loading: () => LyricsHint(colors: colors, label: 'Finding lyrics…'),
      error: (e, _) => LyricsHint(
        colors: colors,
        label: 'Couldn’t load lyrics',
        detail: '$e',
      ),
      data: (r) {
        if (r.instrumental) {
          return LyricsHint(
            colors: colors,
            label: 'Instrumental',
            detail: 'No lyrics for this track.',
          );
        }
        if (!r.found || r.lines.isEmpty) {
          return LyricsHint(
            colors: colors,
            label: 'No lyrics found',
            detail: 'None of the lyrics databases had this song.',
          );
        }
        return LyricsBody(
          colors: colors,
          lines: r.lines,
          synced: r.synced,
          controller: controller,
          clock: clock,
          onSeek: onSeek,
          source: r.source,
        );
      },
    );
  }
}
