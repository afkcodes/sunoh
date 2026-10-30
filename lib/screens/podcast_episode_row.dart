// One podcast episode as a list row, with the small pieces it needs: the
// listened-so-far bar and its precomputed date/length line.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remixicon/remixicon.dart';

import '../api/dto.dart';
import '../providers/app_state_provider.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/motion.dart';
import '../widgets/playing_bars.dart';
import '../widgets/ui.dart';
import 'detail_chrome.dart' show joinMeta;

/// An episode as a list row: cover, title (two lines — episode titles run
/// long), the date and length, and how far in you are. The playing episode
/// takes the page colour and the bars. Tapping plays it; the button on the
/// right queues it.
class EpisodeRow extends ConsumerWidget {
  const EpisodeRow({
    super.key,
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
    final dur = int.tryParse(episode.duration ?? '') ?? 0;
    final pos = s.episodeProgressSec(episode.id) ?? 0;
    final started = pos > 30 && dur > 0;
    final meta = _EpisodeMeta.of(episode);
    return Pressable(
      scale: 0.99,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
        child: Row(
          children: [
            SunohArt(
              id: episode.id,
              imageUrl: meta.art,
              size: 48,
              radius: SunohRadius.row,
              shadow: false,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (isCurrent) ...[
                        PlayingBars(
                          color: accent,
                          size: 12,
                          animate: s.isPlaying,
                        ),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          episode.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: SunohType.sans(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: isCurrent ? accent : c.fg,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (meta.line.isNotEmpty || started) ...[
                    const SizedBox(height: 1),
                    Text(
                      started
                          ? joinMeta([
                              meta.line,
                              '${_minutesLeft(dur, pos)} left',
                            ])
                          : meta.line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SunohType.sans(fontSize: 13, color: c.fgDim),
                    ),
                  ],
                  if (started) ...[
                    const SizedBox(height: 6),
                    _Progress(
                      value: (pos / dur).clamp(0.0, 1.0),
                      colors: c,
                      accent: accent,
                    ),
                  ],
                ],
              ),
            ),
            IconBtn(
              icon: RemixIcons.add_circle_line,
              color: c.fgMute,
              size: 18,
              onTap: () => s.addApiSongToQueue(episode),
            ),
          ],
        ),
      ),
    );
  }

  static String _minutesLeft(int totalSec, int posSec) =>
      '${((totalSec - posSec).clamp(0, totalSec) / 60).round()}m';
}

/// A 2px listened-so-far bar under an episode's meta line.
class _Progress extends StatelessWidget {
  const _Progress({
    required this.value,
    required this.colors,
    required this.accent,
  });
  final double value;
  final SunohColors colors;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 2,
      decoration: squircleDecoration(radius: 1, color: colors.line),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: value,
        child: DecoratedBox(
          decoration: squircleDecoration(radius: 1, color: accent),
        ),
      ),
    );
  }
}

/// An episode's cover URL and its "Mon · 45m" line, worked out once per
/// episode rather than in every row build — the date parse is not free.
class _EpisodeMeta {
  _EpisodeMeta._(FeedItem e)
    : art = e.image.isNotEmpty ? e.image.last.link : null,
      line = joinMeta([_formatDate(e.releaseDate), _fmtDur(e.duration)]);

  static final Expando<_EpisodeMeta> _cache = Expando<_EpisodeMeta>();
  static _EpisodeMeta of(FeedItem e) => _cache[e] ??= _EpisodeMeta._(e);

  final String? art;
  final String line;

  static String _fmtDur(String? raw) {
    final sec = int.tryParse(raw ?? '') ?? 0;
    if (sec <= 0) return '';
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
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
