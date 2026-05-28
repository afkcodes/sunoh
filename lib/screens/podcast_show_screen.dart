// Podcast show detail — Podify-inspired layout.
//
// Layout, top to bottom:
//   1. Compact nav bar with circular-bg back + share IconBtns and the
//      show title + author stacked in the middle. No sticky-header
//      takeover needed; the title is always visible.
//   2. Full-width squircle cover with a soft palette wash behind it.
//   3. "About" card — single squircle holding the description (with
//      Read more), an inline action strip (subscribe / download /
//      add-to-queue / overflow) and a wide accent-filled Play pill.
//   4. Episodes header.
//   5. Episode cards (Podify-style, from earlier work).
//
// Visually quieter than music's centered-hero detail because the
// chrome is more compact; but it diverges enough (action chips inside
// the about card, pill play button instead of round, title in the
// nav) to feel like its own thing.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:solar_icons/solar_icons.dart';

import '../api/dto.dart';
import '../providers/app_state_provider.dart';
import '../providers/palette_provider.dart';
import '../providers/podcast_provider.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/playing_bars.dart';
import '../widgets/ui.dart';

class PodcastShowScreen extends ConsumerWidget {
  const PodcastShowScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final async = ref.watch(podcastShowProvider(id));
    return ColoredBox(
      color: c.bg,
      child: SafeArea(
        child: async.when(
          loading: () => _CenteredSpinner(colors: c),
          error: (e, _) => _ErrorState(
            colors: c,
            message: '$e',
            onRetry: () => ref.invalidate(podcastShowProvider(id)),
          ),
          data: (show) {
            final url = show.artwork ?? '';
            final palette = url.isEmpty
                ? null
                : ref.watch(artPaletteProvider(url)).value;
            final accent = palette?.accent ?? s.resolvedAccent;
            final tint = palette?.dominant ?? accent;
            return Column(
              children: [
                _NavBar(
                  title: show.title,
                  subtitle: show.subtitle,
                  colors: c,
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 140),
                    children: [
                      const SizedBox(height: 8),
                      _Cover(show: show, tint: tint, colors: c),
                      const SizedBox(height: 18),
                      _AboutCard(
                          show: show, colors: c, accent: accent),
                      const SizedBox(height: 22),
                      _EpisodesHeader(
                          count: show.episodes.length, colors: c),
                      if (show.episodes.isEmpty)
                        _NoEpisodes(colors: c)
                      else
                        for (var i = 0; i < show.episodes.length; i++)
                          _EpisodeRow(
                            episode: show.episodes[i],
                            colors: c,
                            accent: accent,
                            onTap: () => s.playApiQueue(
                              show.episodes,
                              i,
                              sourceLabel: 'PODCAST · ${show.title}',
                            ),
                          ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Compact nav bar — circular-bg back IconBtn on the left, share on
/// the right, show title + author stacked in the middle. Replaces the
/// sticky-header takeover music uses: the title sits in the bar from
/// the very first frame, so scrolling doesn't need to swap chrome in
/// and out.
class _NavBar extends StatelessWidget {
  const _NavBar({
    required this.title,
    required this.subtitle,
    required this.colors,
  });
  final String title;
  final String? subtitle;
  final SunohColors colors;
  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      child: Row(
        children: [
          IconBtn(
              icon: SolarIconsOutline.altArrowLeft,
              color: c.fg,
              size: 22,
              width: 40,
              height: 40,
              background: c.surface,
              onTap: () => context.pop()),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: SunohType.heading(
                        fontSize: 16,
                        color: c.fg,
                        letterSpacing: -0.2)),
                if ((subtitle ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style:
                          SunohType.sans(fontSize: 12, color: c.fgMute)),
                ],
              ],
            ),
          ),
          IconBtn(
              icon: SolarIconsOutline.share,
              color: c.fg,
              size: 20,
              width: 40,
              height: 40,
              background: c.surface,
              onTap: () {}),
        ],
      ),
    );
  }
}

/// Big squircle cover with a soft palette wash bleeding behind it. The
/// cover is the visual anchor of the page now that the title lives in
/// the nav bar.
class _Cover extends StatelessWidget {
  const _Cover({
    required this.show,
    required this.tint,
    required this.colors,
  });
  final PodcastShowDetail show;
  final Color tint;
  final SunohColors colors;
  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Soft palette bleed UNDER the cover — gives the dominant
          // artwork color a chance to whisper into the surrounding bg
          // without flooding the page like music's hero backdrop does.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topCenter,
                  radius: 1.1,
                  colors: [
                    tint.withValues(alpha: 0.30),
                    tint.withValues(alpha: 0.05),
                    c.bg,
                  ],
                  stops: const [0, 0.6, 1],
                ),
              ),
            ),
          ),
          squircleClip(
            radius: 18,
            child: AspectRatio(
              aspectRatio: 1,
              child: SunohArt(
                id: show.id,
                imageUrl: show.artwork,
                size: 360,
                radius: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "About" card carrying the description + an inline action strip +
/// the Play pill. Mirrors the Podify shot — wraps everything related
/// to the show metadata in a single squircle so the page below is
/// purely the episode list.
class _AboutCard extends ConsumerStatefulWidget {
  const _AboutCard({
    required this.show,
    required this.colors,
    required this.accent,
  });
  final PodcastShowDetail show;
  final SunohColors colors;
  final Color accent;
  @override
  ConsumerState<_AboutCard> createState() => _AboutCardState();
}

class _AboutCardState extends ConsumerState<_AboutCard> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final accent = widget.accent;
    final s = ref.watch(appStateProvider);
    final subscribed = s.isSubscribedPodcast(widget.show.id);
    final episodes = widget.show.episodes;
    final isEmpty = episodes.isEmpty;
    final cleaned = _strip(widget.show.description ?? '');
    final fgOnAccent = accent.computeLuminance() > 0.55
        ? const Color(0xFF0B0B0D)
        : const Color(0xFFFAFAFA);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        decoration: squircleDecoration(
          radius: 16,
          color: c.surface,
          borderColor: c.line,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('About this podcast',
                style: SunohType.heading(
                    fontSize: 15,
                    color: c.fg,
                    letterSpacing: -0.2)),
            if (cleaned.isNotEmpty) ...[
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                behavior: HitTestBehavior.opaque,
                child: _DescriptionText(
                  text: cleaned,
                  expanded: _expanded,
                  colors: c,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                _ChipIcon(
                  icon: subscribed
                      ? SolarIconsBold.heart
                      : SolarIconsOutline.heart,
                  color: subscribed ? accent : c.fgDim,
                  onTap: () => s.toggleSubscribedPodcast(
                      _showAsFeedItem(widget.show)),
                ),
                const SizedBox(width: 8),
                _ChipIcon(
                  icon: SolarIconsOutline.downloadMinimalistic,
                  color: c.fgDim,
                  onTap: () => s.flashToast('Downloads coming soon'),
                ),
                const SizedBox(width: 8),
                _ChipIcon(
                  icon: SolarIconsOutline.playlistMinimalistic,
                  color: c.fgDim,
                  onTap: isEmpty
                      ? null
                      : () {
                          for (final e in episodes) {
                            s.addApiSongToQueue(e);
                          }
                          s.flashToast(
                              'Added ${episodes.length} to queue');
                        },
                ),
                const Spacer(),
                // Wide pill Play — text + glyph, accent-filled.
                GestureDetector(
                  onTap: isEmpty
                      ? null
                      : () => s.playApiQueue(episodes, 0,
                          sourceLabel:
                              'PODCAST · ${widget.show.title}'),
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.only(left: 16, right: 6),
                    decoration: BoxDecoration(
                      color: isEmpty ? c.surface : accent,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: isEmpty
                          ? null
                          : [
                              BoxShadow(
                                  color: accent.withValues(alpha: 0.28),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4)),
                            ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Play',
                            style: SunohType.sans(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: isEmpty
                                    ? c.fgMute
                                    : fgOnAccent)),
                        const SizedBox(width: 10),
                        Container(
                          width: 30,
                          height: 30,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isEmpty
                                ? c.line
                                : (fgOnAccent ==
                                        const Color(0xFF0B0B0D)
                                    ? const Color(0xFF0B0B0D)
                                    : const Color(0xFFFAFAFA)),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(PhosphorIconsFill.play,
                              size: 13,
                              color: isEmpty
                                  ? c.fgDim
                                  : (fgOnAccent ==
                                          const Color(0xFF0B0B0D)
                                      ? const Color(0xFFFAFAFA)
                                      : const Color(0xFF0B0B0D))),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _strip(String html) {
    final s = html.replaceAll(RegExp(r'<[^>]*>'), ' ');
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

class _DescriptionText extends StatelessWidget {
  const _DescriptionText({
    required this.text,
    required this.expanded,
    required this.colors,
  });
  final String text;
  final bool expanded;
  final SunohColors colors;
  @override
  Widget build(BuildContext context) {
    final c = colors;
    if (expanded) {
      return Text(text,
          style: SunohType.sans(fontSize: 13, color: c.fgDim, height: 1.5));
    }
    // Inline "see more" — render the truncated body + a single bold
    // link at the end so the user can expand without a separate
    // button row underneath.
    return Text.rich(
      TextSpan(
        style: SunohType.sans(fontSize: 13, color: c.fgDim, height: 1.5),
        children: [
          TextSpan(text: _truncated(text)),
          TextSpan(
            text: '… see more',
            style: SunohType.sans(
                fontSize: 13,
                color: c.fg,
                fontWeight: FontWeight.w600,
                height: 1.5),
          ),
        ],
      ),
      maxLines: 4,
      overflow: TextOverflow.fade,
    );
  }

  /// Trims text to ~3.5 lines worth of characters. Real layout-aware
  /// truncation needs a TextPainter; this approximation is good
  /// enough for the four-line cap.
  static String _truncated(String s) {
    if (s.length <= 220) return s;
    return s.substring(0, 220);
  }
}

/// Circular-bg action chip used inside the About card. Round 40-px tap
/// target matching the nav bar chips, c.bg fill so it pops cleanly off
/// the About card's c.surface background.
class _ChipIcon extends StatelessWidget {
  const _ChipIcon({
    required this.icon,
    required this.color,
    this.onTap,
  });
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
          color: Color(0xFF0F0F12),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}

FeedItem _showAsFeedItem(PodcastShowDetail s) => FeedItem(
      id: s.id,
      title: s.title,
      subtitle: s.subtitle,
      type: 'podcast',
      image: s.image,
      source: 'podcastindex',
      language: s.language,
      url: s.url,
    );

class _EpisodesHeader extends StatelessWidget {
  const _EpisodesHeader({required this.count, required this.colors});
  final int count;
  final SunohColors colors;
  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('Episodes',
              style: SunohType.heading(
                  fontSize: 19, color: c.fg, letterSpacing: -0.2)),
          const SizedBox(width: 10),
          Text('$count',
              style: SunohType.mono(
                  fontSize: 12, color: c.fgMute, letterSpacing: 0.4)),
        ],
      ),
    );
  }
}

/// Episode card — Podify-inspired: cover + title + meta on top,
/// inline action row + big play circle on the bottom. Each row is
/// its own card (c.surface bg + accent-tinted border when active),
/// so the list reads as a stack of distinct episode "cards" rather
/// than a uniform tracklist. Tapping anywhere in the card plays the
/// episode; the inline icons handle their own sub-actions.
class _EpisodeRow extends ConsumerWidget {
  const _EpisodeRow({
    required this.episode,
    required this.colors,
    required this.accent,
    required this.onTap,
  });
  final FeedItem episode;
  final SunohColors colors;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    final s = ref.watch(appStateProvider);
    final isCurrent = s.currentApiSong?.id == episode.id;
    final isPlayingHere = isCurrent && s.isPlaying;
    final dur = int.tryParse(episode.duration ?? '') ?? 0;
    final savedPos = s.episodeProgressSec(episode.id) ?? 0;
    final dateLabel = _formatDate(episode.releaseDate);
    final durLabel = dur > 0 ? _fmtDur(dur) : '';
    final progressFrac = (savedPos > 30 && dur > 0)
        ? (savedPos / dur).clamp(0.0, 1.0)
        : 0.0;
    final metaParts = <String>[
      if (dateLabel.isNotEmpty) dateLabel,
      if (durLabel.isNotEmpty) durLabel,
      if (savedPos > 30 && dur > 0)
        '${_fmtRemaining(dur, savedPos)} left',
    ];
    final fgOnAccent = accent.computeLuminance() > 0.55
        ? const Color(0xFF0B0B0D)
        : const Color(0xFFFAFAFA);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        // Flat list treatment — no surface, no border. Vertical
        // padding gives the row breathing room from its neighbours;
        // the active episode gets a subtle accent-tinted wash so it
        // stays spottable in the list.
        decoration: BoxDecoration(
          color: isCurrent
              ? accent.withValues(alpha: 0.06)
              : Colors.transparent,
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  squircleClip(
                    radius: 10,
                    child: SunohArt(
                      id: episode.id,
                      imageUrl: episode.image.isNotEmpty
                          ? episode.image.last.link
                          : null,
                      size: 80,
                      radius: 10,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(episode.title,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: SunohType.sans(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: isCurrent ? accent : c.fg,
                                height: 1.3,
                                letterSpacing: -0.1)),
                        if (metaParts.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(metaParts.join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: SunohType.sans(
                                  fontSize: 11.5,
                                  color: c.fgMute,
                                  letterSpacing: 0.1)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (progressFrac > 0) ...[
                const SizedBox(height: 12),
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: c.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: progressFrac,
                    child: Container(
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  _ActionIcon(
                    icon: SolarIconsOutline.addCircle,
                    color: c.fgDim,
                    onTap: () => s.addApiSongToQueue(episode),
                  ),
                  const SizedBox(width: 4),
                  _ActionIcon(
                    icon: SolarIconsOutline.downloadMinimalistic,
                    color: c.fgDim,
                    onTap: () => s.flashToast('Downloads coming soon'),
                  ),
                  const SizedBox(width: 4),
                  _ActionIcon(
                    icon: SolarIconsOutline.share,
                    color: c.fgDim,
                    onTap: () {},
                  ),
                  const SizedBox(width: 4),
                  _ActionIcon(
                    icon: SolarIconsBold.menuDots,
                    color: c.fgMute,
                    onTap: () {},
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: onTap,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                              color: accent.withValues(alpha: 0.30),
                              blurRadius: 14,
                              offset: const Offset(0, 4)),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: isPlayingHere
                          ? PlayingBars(
                              color: fgOnAccent, size: 14, animate: true)
                          : Icon(PhosphorIconsFill.play,
                              size: 18, color: fgOnAccent),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
  }

  static String _fmtDur(int sec) {
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  static String _fmtRemaining(int totalSec, int posSec) {
    final remaining = (totalSec - posSec).clamp(0, totalSec);
    final m = (remaining / 60).round();
    return '${m}m';
  }

  static String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    DateTime? dt;
    final asInt = int.tryParse(raw);
    if (asInt != null && asInt > 1_000_000_000) {
      dt = DateTime.fromMillisecondsSinceEpoch(asInt * 1000);
    } else {
      dt = DateTime.tryParse(raw);
    }
    if (dt == null) return raw;
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return weekdays[(dt.weekday - 1).clamp(0, 6)];
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.icon,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 36,
        height: 36,
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}

class _NoEpisodes extends StatelessWidget {
  const _NoEpisodes({required this.colors});
  final SunohColors colors;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Text('No episodes yet.',
          style: SunohType.sans(fontSize: 13, color: colors.fgMute)),
    );
  }
}

class _CenteredSpinner extends StatelessWidget {
  const _CenteredSpinner({required this.colors});
  final SunohColors colors;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
            strokeWidth: 2, color: colors.fgDim),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Couldn’t load this show.',
                style: SunohType.heading(fontSize: 18, color: c.fgDim)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: SunohType.sans(fontSize: 12, color: c.fgMute)),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: squircleDecoration(
                  radius: 12,
                  color: c.surface,
                  borderColor: c.line,
                ),
                child: Text('Retry',
                    style: SunohType.sans(
                        fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
