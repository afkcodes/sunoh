// The list row Home's song shelves and Search's results share, and the two
// labels rows and cards format: a duration and a raw API word.
//
// Split from feed_tiles.dart along the tile/row seam; the same reasons for
// sharing apply — see that file.

import 'package:flutter/material.dart';
import 'package:remixicon/remixicon.dart';

import '../api/dto.dart';
import '../theme/tokens.dart';
import '../widgets/cover_hero.dart';
import '../widgets/motion.dart';
import '../widgets/playing_bars.dart';

// ── Labels ───────────────────────────────────────────────────────────────

final Expando<String> _durations = Expando('feed duration');

/// `m:ss` for an item's duration in seconds, or '' when it has none.
///
/// Memoised on the item: a row rebuilds whenever playback moves, and
/// formatting the same number again each time is the work the build rule
/// exists to keep out.
String durationOf(FeedItem item) =>
    _durations[item] ??= _formatSeconds(item.duration);

String _formatSeconds(String? raw) {
  final total = int.tryParse(raw ?? '');
  if (total == null || total <= 0) return '';
  final r = total % 60;
  return '${total ~/ 60}:${r.toString().padLeft(2, '0')}';
}

final Map<String, String> _labels = {};

/// A raw API word as a label: `radio_station` reads "Radio station", `hindi`
/// reads "Hindi". Cached per word — there are a few dozen types and
/// languages between them, and a card asks again every rebuild.
String labelFor(String raw) => _labels.putIfAbsent(raw, () {
  final t = raw.replaceAll('_', ' ').trim();
  return t.isEmpty ? '' : t[0].toUpperCase() + t.substring(1);
});

// ── Rows ─────────────────────────────────────────────────────────────────

/// A list row: optional rank, 48dp art, title and subtitle, then a right-hand
/// meta (a duration) and either a more button or a chevron.
///
/// No dividers between rows — the art column and the 64dp rhythm already
/// separate them. The row playing now takes the accent and the bars.
class FeedRow extends StatelessWidget {
  const FeedRow({
    super.key,
    required this.item,
    required this.colors,
    required this.onTap,
    this.subtitle,
    this.rank,
    this.playing = false,
    this.animateBars = true,
    this.meta,
    this.onMore,
    this.chevron = false,
    this.gutter = 16,
    this.heroTag,
  });

  final FeedItem item;
  final SunohColors colors;
  final VoidCallback onTap;
  final String? subtitle;
  final int? rank;
  final bool playing;
  final bool animateBars;
  final String? meta;
  final VoidCallback? onMore;
  final bool chevron;
  final double gutter;

  /// Flies this row's cover into the page it opens (widgets/cover_hero.dart).
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final sub = subtitle ?? '';
    final right = meta ?? '';
    return Pressable(
      scale: 0.99,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: gutter, vertical: 8),
          child: Row(
            children: [
              if (rank != null) ...[
                SizedBox(
                  width: 22,
                  child: Text(
                    '$rank',
                    textAlign: TextAlign.center,
                    style: SunohType.mono(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: c.fgDim,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              CoverHero(
                tag: heroTag,
                id: item.id,
                imageUrl: item.artwork,
                size: 48,
                radius: item.type == 'artist' ? 999 : SunohRadius.row,
              ),
              const SizedBox(width: 12),
              Expanded(child: _titles(c, sub)),
              if (right.isNotEmpty) ...[
                const SizedBox(width: 12),
                Text(
                  right,
                  style: SunohType.mono(fontSize: 12.5, color: c.fgMute),
                ),
              ],
              if (onMore != null)
                Padding(
                  padding: EdgeInsets.only(left: right.isEmpty ? 12 : 4),
                  child: _MoreButton(color: c.fgMute, onTap: onMore!),
                )
              else if (chevron) ...[
                const SizedBox(width: 12),
                Icon(RemixIcons.arrow_right_s_line, size: 18, color: c.fgMute),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _titles(SunohColors c, String sub) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Flexible(
            child: Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SunohType.sans(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: playing ? c.accent : c.fg,
                height: 1.3,
              ),
            ),
          ),
          if (playing) ...[
            const SizedBox(width: 8),
            PlayingBars(color: c.accent, size: 12, animate: animateBars),
          ],
        ],
      ),
      if (sub.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SunohType.sans(fontSize: 13, color: c.fgDim),
          ),
        ),
    ],
  );
}

class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.color, required this.onTap});
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 32,
        height: 40,
        child: Icon(RemixIcons.more_fill, size: 18, color: color),
      ),
    );
  }
}
