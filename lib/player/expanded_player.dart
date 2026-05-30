// Expanded full-screen player — single rich design driven by the artwork's
// palette. (The old Minimal / Immersive variants were removed 2026-05-23 —
// one well-considered layout beat three OK ones.)
//
// Visual ingredients:
//   - Soft palette-tinted radial wash at the top that bleeds into c.bg.
//   - Swipeable cover carousel — prev/next peek at the sides, ambient halo
//     ring behind the centered cover that pulses with playback.
//   - Title + artist + optional synced-lyric teaser.
//   - Scrubber + palette-accent play button.
//   - Bottom strip: LYRICS · EQ · QUEUE.
//
// Swipe-down dismisses; Hero album art animates back into the mini player.

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:solar_icons/solar_icons.dart';

import '../cast/cast_button.dart';
import '../data/catalog.dart';
import '../data/models.dart';
import '../overlays/eq_sheet.dart';
import '../overlays/sleep_sheet.dart';
import '../overlays/track_menu_sheet.dart';
import '../providers/app_state_provider.dart';
import '../providers/palette_provider.dart';
import '../router/router.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/ui.dart';
import 'scrubber.dart';

class ExpandedPlayer extends ConsumerStatefulWidget {
  const ExpandedPlayer({super.key});
  @override
  ConsumerState<ExpandedPlayer> createState() => _ExpandedPlayerState();
}

/// Reserved height for the title block. Sized so 2-line title + artist fits
/// without forcing the cover or scrubber below to shift on track change.
/// Lyric teaser (rare — synced lyrics only ship with the dummy catalog) is
/// allowed to push layout slightly when present rather than reserving empty
/// space for it in the common case.
const double _titleBlockHeight = 78;

class _ExpandedPlayerState extends ConsumerState<ExpandedPlayer>
    with TickerProviderStateMixin {
  double _drag = 0;
  late final AnimationController _snapBack = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );

  @override
  void dispose() {
    _snapBack.dispose();
    super.dispose();
  }

  void _snapBackToTop() {
    final anim = Tween<double>(
      begin: _drag,
      end: 0,
    ).animate(CurvedAnimation(parent: _snapBack, curve: Curves.easeOutCubic));
    void tick() => setState(() => _drag = anim.value);
    anim.addListener(tick);
    _snapBack.forward(from: 0).whenComplete(() => anim.removeListener(tick));
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final track = s.current;

    // Live palette for the current artwork. While loading or missing, fall
    // back to the user/deterministic accent so the UI never looks broken.
    final url = s.currentApiSong?.artwork ?? '';
    final palette = url.isEmpty
        ? null
        : ref.watch(artPaletteProvider(url)).value;
    final fallbackAccent = s.resolvedAccent;
    final accent = palette?.accent ?? fallbackAccent;
    final tint = palette?.dominant ?? fallbackAccent;
    final lyricLine = _currentLyric(s);

    return GestureDetector(
      onVerticalDragUpdate: (d) {
        if (d.delta.dy > 0 || _drag > 0) {
          setState(
            () => _drag = (_drag + d.delta.dy).clamp(0, double.infinity),
          );
        }
      },
      onVerticalDragEnd: (d) {
        if (_drag > 120 || (d.primaryVelocity ?? 0) > 700) {
          context.pop();
        } else {
          _snapBackToTop();
        }
      },
      child: Transform.translate(
        offset: Offset(0, _drag),
        child: Stack(
          children: [
            // Base bg.
            Positioned.fill(child: ColoredBox(color: c.bg)),
            // Palette wash at the top — gives the screen per-track character
            // without flooding it. Note all stops use `tint.withValues(alpha: …)`
            // so the gradient stays in the same hue across alpha; mixing
            // `Colors.transparent` (= black) would muddy the fade.
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -1),
                      radius: 1.15,
                      colors: [
                        tint.withValues(alpha: 0.38),
                        tint.withValues(alpha: 0.10),
                        tint.withValues(alpha: 0),
                      ],
                      stops: const [0, 0.45, 1],
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 4),
                  _header(context, s, c, track, s.apiSourceLabel),
                  Expanded(
                    child: _classic(
                      context: context,
                      s: s,
                      c: c,
                      track: track,
                      accent: accent,
                      tint: tint,
                      lyricLine: lyricLine,
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

  Widget _header(
    BuildContext context,
    AppState s,
    SunohColors c,
    Track track,
    String? sourceLabel,
  ) {
    // Resolve the eyebrow + main label. API-mode songs pass an explicit
    // `apiSourceLabel` in the form "PLAYLIST · Title" / "ALBUM · Title".
    // Split on ' · ' so the eyebrow gets the category and the main line
    // gets the title. Falls back to album lookup for the dummy path.
    String eyebrowText = 'PLAYING FROM';
    String mainText;
    if (sourceLabel != null && sourceLabel.isNotEmpty) {
      final parts = sourceLabel.split(' · ');
      if (parts.length >= 2) {
        eyebrowText = parts.first;
        mainText = parts.sublist(1).join(' · ');
      } else {
        mainText = sourceLabel;
      }
    } else {
      mainText = albumOf(track.album)?.title ?? 'Library';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconBtn(
            icon: SolarIconsOutline.altArrowDown,
            color: c.fg,
            size: 22,
            onTap: () => context.pop(),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                eyebrow(eyebrowText, c.fgMute, size: 9, letterSpacing: 1.4),
                const SizedBox(height: 2),
                Text(
                  mainText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: SunohType.sans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: c.fg,
                  ),
                ),
              ],
            ),
          ),
          IconBtn(
            icon: SolarIconsBold.menuDots,
            color: c.fg,
            size: 20,
            // Opens the reusable track-actions sheet for the currently-
            // playing song (Like / Play next / Add to queue / View Artist
            // / Share). No-op when the current track is a dummy entry
            // (radio stations, podcasts — no FeedItem to act on).
            onTap: () {
              final song = s.currentApiSong;
              if (song == null) return;
              showTrackMenuSheet(
                context,
                song: song,
                sourceLabel: s.apiSourceLabel,
                sourceRef: s.apiSourceRef,
                // True so the sheet's navigation rows also pop the
                // player itself before pushing the destination —
                // otherwise the album/artist lands behind the still-
                // open player and looks like nothing happened.
                fromPlayer: true,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _classic({
    required BuildContext context,
    required AppState s,
    required SunohColors c,
    required dynamic track,
    required Color accent,
    required Color tint,
    required String? lyricLine,
  }) {
    // The icon strip is overlaid via `Positioned` so its vertical position
    // can be tuned without redistributing the Spacer slack above it (which
    // would shift the cover / title / transport). The Column reserves a
    // SizedBox of the strip's intrinsic height so the transport stays
    // anchored at the same y as before.
    return Stack(
      children: [
        Column(
          children: [
            const Spacer(flex: 2),
            _StaticCover(
              id: track.id,
              url: s.currentApiSong?.artwork,
              playing: s.isPlaying,
              // Live streams = radio stations = often low-res logos
              // with text baked in. The framed-on-blur treatment makes
              // them look intentional instead of stretched-and-soft.
              isLive: s.isLive,
              accent: accent,
            ),
            const SizedBox(height: 24),
            // Title block in a reserved-height container — 1-line vs 2-line
            // titles don't cause the cover or controls below to jump on track
            // change. Sized to comfortably fit a 2-line title + artist + a one-
            // line lyric teaser; shorter content top-aligns inside the box.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                height: _titleBlockHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Tiny ON-AIR header above the title for live
                          // streams — clarifies that the big text below
                          // is the live "now playing" track and the
                          // smaller line is the station, not the other
                          // way around.
                          if (s.isLive)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                        color: accent,
                                        shape: BoxShape.circle),
                                  ),
                                  const SizedBox(width: 6),
                                  Text('ON AIR',
                                      style: SunohType.mono(
                                          fontSize: 9,
                                          color: accent,
                                          letterSpacing: 1.8)),
                                ],
                              ),
                            ),
                          Text(
                            // Live: prefer the ICY now-playing track;
                            // fall back to the station name. Non-live:
                            // always the track title.
                            s.isLive ? (s.icyTitle ?? track.title) : track.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: SunohType.heading(
                              fontSize: 26,
                              color: c.fg,
                              height: 1.1,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            // Secondary line: in live mode show the
                            // station name (so the user always knows
                            // the source even when ICY occupies the
                            // big slot); otherwise the artist.
                            s.isLive ? track.title : track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SunohType.sans(
                              fontSize: 13.5,
                              color: c.fgDim,
                            ),
                          ),
                          if (lyricLine != null && !s.isLive) ...[
                            const SizedBox(height: 8),
                            _LyricsTeaser(
                              line: lyricLine,
                              accent: accent,
                              onTap: () => context.openLyrics(),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: IconBtn(
                        icon: s.isLikedCurrentApi
                            ? SolarIconsBold.heart
                            : SolarIconsOutline.heart,
                        color: s.isLikedCurrentApi ? accent : c.fgDim,
                        size: 26,
                        onTap: () {
                          final item = s.currentApiSong;
                          if (item != null) {
                            // Dispatcher routes by item.type — radio
                            // stations land in `_likedStations`, songs
                            // (and episodes-treated-as-songs) in
                            // `_likedSongs`. Keeps the buckets clean.
                            s.toggleLikedApi(item);
                          } else {
                            s.toggleLike();
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (s.isLive)
              // Live streams: no scrubber / no times — the ON AIR
              // header above the title already carries the live signal.
              // Reserved spacer keeps the transport row anchored at the
              // same y as the track-mode layout.
              const SizedBox(height: 38)
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _progress(
                  s,
                  accent,
                  c.fg,
                  layout: (scrubber, pos, remaining) => Column(
                    children: [
                      scrubber,
                      const SizedBox(height: 4),
                      _times(c, fmt(pos), '-${fmt(remaining)}'),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                // Same 5-button row regardless of mode. In live mode the
                // non-applicable controls (shuffle / skip / repeat) are
                // rendered DISABLED (low-opacity, no-op onTap) instead
                // of hidden — keeps the play/pause anchored where the
                // muscle memory expects and avoids the empty-row look.
                children: [
                  IconBtn(
                    icon: PhosphorIconsBold.shuffle,
                    color: s.isLive
                        ? c.fgMute.withValues(alpha: 0.35)
                        : (s.shuffle ? accent : c.fgMute),
                    size: 22,
                    onTap: s.isLive ? () {} : s.toggleShuffle,
                  ),
                  IconBtn(
                    icon: PhosphorIconsFill.skipBack,
                    color: s.isLive
                        ? c.fg.withValues(alpha: 0.25)
                        : c.fg,
                    size: 30,
                    onTap: s.isLive ? () {} : s.prev,
                  ),
                  _PlayButton(
                    playing: s.isPlaying,
                    accent: accent,
                    onTap: s.playPause,
                    isLive: s.isLive,
                  ),
                  IconBtn(
                    icon: PhosphorIconsFill.skipForward,
                    color: s.isLive
                        ? c.fg.withValues(alpha: 0.25)
                        : c.fg,
                    size: 30,
                    onTap: s.isLive ? () {} : s.next,
                  ),
                  IconBtn(
                    icon: s.repeat == LoopMode.one
                        ? PhosphorIconsBold.repeatOnce
                        : PhosphorIconsBold.repeat,
                    color: s.isLive
                        ? c.fgMute.withValues(alpha: 0.35)
                        : (s.repeat != LoopMode.off ? accent : c.fgMute),
                    size: 22,
                    onTap: s.isLive ? () {} : s.cycleRepeat,
                  ),
                ],
              ),
            ),
            const Spacer(flex: 3),
            // Reservation for the floating strip below. Keeps the
            // transport row anchored at the same y it had before the
            // strip was lifted out of the column flow.
            const SizedBox(height: _bottomBarReservedHeight),
          ],
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: _bottomBarLift,
          child: _bottomBar(context, c),
        ),
      ],
    );
  }

  // Strip's intrinsic height with the original padding (top 4 + bottom 12 +
  // icon's own vertical 10×2 + glyph 22 ≈ 58). Bump if the iconBtn padding
  // changes.
  static const double _bottomBarReservedHeight = 58;
  // Distance the strip floats above the SafeArea bottom inset. Increasing
  // this lifts ONLY the strip — the column reservation above keeps every
  // other element pinned.
  static const double _bottomBarLift = 20;

  Widget _progress(
    AppState s,
    Color accent,
    Color fg, {
    required Widget Function(Widget scrubber, int pos, int remaining) layout,
  }) {
    return ValueListenableBuilder<int>(
      valueListenable: s.positionTick,
      builder: (_, pos, _) {
        final dur = s.currentDurationSec;
        final remaining = (dur - pos).clamp(0, dur);
        final scrubber = Scrubber(
          value: pos,
          max: dur,
          accent: accent,
          fg: fg,
          onChanged: s.seek,
          compact: false,
        );
        return layout(scrubber, pos, remaining);
      },
    );
  }

  Widget _times(SunohColors c, String left, String right) {
    final style = SunohType.mono(
      fontSize: 11,
      color: c.fgMute,
      letterSpacing: 0.4,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(left, style: style),
        Text(right, style: style),
      ],
    );
  }

  Widget _bottomBar(BuildContext context, SunohColors c) {
    Widget iconBtn(IconData icon, VoidCallback onTap, {Color? color}) =>
        GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Icon(icon, size: 22, color: color ?? c.fgMute),
          ),
        );
    return Padding(
      // Strip is overlaid by `_classic`'s Stack with a `Positioned.bottom`
      // offset (`_bottomBarLift`) that handles the visual lift off the
      // home indicator. Internal padding stays minimal so the strip's
      // intrinsic height matches `_bottomBarReservedHeight`.
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
      child: Consumer(
        builder: (ctx, ref, _) {
          final s = ref.watch(appStateProvider);
          final accent = s.resolvedAccent;
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              // Lyrics — `subtitles` is the CC-style two-line frame,
              // the canonical "lyrics / captions" glyph. Distinct from a
              // microphone (which reads as "record").
              iconBtn(SolarIconsOutline.subtitles, () => context.openLyrics()),
              // EQ — Solar's `tuning` is the three-slider stack, exactly
              // the EQ metaphor.
              iconBtn(SolarIconsOutline.tuning, () => showEqSheet(context)),
              // Cast — accent + filled glyph when a session is live so
              // the user can spot the connected state at a glance.
              iconBtn(
                s.isCasting
                    ? SolarIconsBold.screencast
                    : SolarIconsOutline.screencast,
                () => openCastPicker(context),
                color: s.isCasting ? accent : null,
              ),
              // Sleep timer — accent + filled when armed (a duration is
              // counting down OR end-of-track is queued). Tapping opens
              // the sheet which shows the live countdown.
              iconBtn(
                s.sleepArmed
                    ? SolarIconsBold.moonSleep
                    : SolarIconsOutline.moonSleep,
                () => showSleepSheet(context),
                color: s.sleepArmed ? accent : null,
              ),
              // Queue — `playlist` (the lined-card with a music-note
              // accent) reads as "music queue" more clearly than the
              // minimalistic stack-of-lines variant we had before.
              iconBtn(SolarIconsOutline.playlist, () => context.openQueue()),
            ],
          );
        },
      ),
    );
  }

  /// Current synced lyric line for the playing track. Returns null when no
  /// lyrics are available (most live API songs).
  String? _currentLyric(AppState s) {
    final id = s.currentApiSong?.id ?? s.current.id;
    final lines = kLyrics[id];
    if (lines == null || lines.isEmpty) return null;
    final pos = s.position;
    LyricLine? active;
    for (final l in lines) {
      if (l.t > pos) break;
      if (l.line.trim().isNotEmpty) active = l;
    }
    return active?.line;
  }
}

// ── Reusable parts ──────────────────────────────────────────────────────────

/// Big accent play/pause button. Icon color picks black-or-white based on
/// accent luminance so it always reads.
class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.playing,
    required this.accent,
    required this.onTap,
    this.isLive = false,
  });
  final bool playing;
  final Color accent;
  final VoidCallback onTap;
  /// When true, the "playing" state shows a stop glyph instead of
  /// pause — radio doesn't pause meaningfully (buffer drains; resume
  /// jumps to the live edge), so stop matches the user's mental model.
  /// Action is the same `s.playPause`.
  final bool isLive;
  static const double size = 72;

  @override
  Widget build(BuildContext context) {
    final icon = playing
        ? (isLive ? PhosphorIconsFill.stop : PhosphorIconsFill.pause)
        : PhosphorIconsFill.play;
    final iconColor = accent.computeLuminance() > 0.55
        ? const Color(0xFF0B0B0D)
        : const Color(0xFFFAFAFA);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: accent,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.42),
              blurRadius: 26,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Icon(icon, size: size * 0.45, color: iconColor),
      ),
    );
  }
}

/// One-line teaser pulled from the synced lyric matching the current pos.
class _LyricsTeaser extends StatelessWidget {
  const _LyricsTeaser({
    required this.line,
    required this.accent,
    required this.onTap,
  });
  final String line;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Flexible(
            child: Text(
              line,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SunohType.sans(
                fontSize: 13,
                color: accent.withValues(alpha: 0.85),
                fontWeight: FontWeight.w500,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Static centered cover. The drop shadow from SunohArt provides the visual
/// lift — no separate palette halo (tried it, looked weird while playing).
/// `playing ? 1.0 : 0.92` scale is the play/paused cue.
class _StaticCover extends StatelessWidget {
  const _StaticCover({
    required this.id,
    required this.url,
    required this.playing,
    this.isLive = false,
    required this.accent,
  });
  final String id;
  final String? url;
  final bool playing;
  /// When true, render as a small framed card on a heavily-blurred
  /// backdrop of the same image — disguises the resolution issues
  /// most radio-station logos suffer from. Falls back to the standard
  /// full-bleed cover when false (regular tracks).
  final bool isLive;
  final Color accent;

  static const double coverSize = 336;
  /// Inner card side for the live treatment — small enough that the
  /// blurred backdrop reads as a halo around it, big enough that the
  /// logo is still recognisable. Tuned against 150×150 onlineradiobox
  /// logos which are the most common upstream resolution.
  static const double _liveCardSize = 200;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: coverSize,
      height: coverSize,
      child: Hero(
        tag: 'sunoh-player-art',
        child: AnimatedScale(
          scale: playing ? 1.0 : 0.92,
          duration: const Duration(milliseconds: 340),
          curve: Curves.easeOutCubic,
          child: isLive
              ? _liveTreatment()
              : SunohArt(
                  id: id, imageUrl: url, size: coverSize, radius: 16),
        ),
      ),
    );
  }

  Widget _liveTreatment() {
    return Stack(
      alignment: Alignment.center,
      fit: StackFit.expand,
      children: [
        // Layer 1 — full-bleed art rendered LARGE then heavily blurred.
        // Acts as a coloured ambient backdrop that picks up the
        // station's palette without exposing its pixelation.
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // The raw art, scaled up so the blur has substance.
              Transform.scale(
                scale: 1.3,
                child: SunohArt(
                    id: id, imageUrl: url, size: coverSize, radius: 0),
              ),
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 36, sigmaY: 36),
                child: Container(color: Colors.black.withValues(alpha: 0.32)),
              ),
            ],
          ),
        ),
        // Layer 2 — small framed card with the crisp logo. Subtle
        // accent-tinted border so it reads as deliberately framed
        // rather than awkwardly inset.
        Container(
          width: _liveCardSize,
          height: _liveCardSize,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.18), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.32),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: SunohArt(
                id: id, imageUrl: url, size: _liveCardSize, radius: 0),
          ),
        ),
      ],
    );
  }
}
