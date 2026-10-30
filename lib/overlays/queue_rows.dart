// The queue's rows: the song playing now, each song waiting, and each song
// already played.
//
// Split out of queue_screen.dart, which was over the size limit, along the
// seam between the screen (sections, ordering, the dummy fallback) and the
// shape of a single row. Nothing here reads app state; each row is handed
// what it draws.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:remixicon/remixicon.dart';

import '../api/dto.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/playing_bars.dart';
import '../widgets/ui.dart';

class QueueNowPlayingRow extends StatelessWidget {
  const QueueNowPlayingRow({
    super.key,
    required this.song,
    required this.accent,
    required this.colors,
  });
  final FeedItem song;
  final Color accent;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final artist = (song.artists ?? const <ApiArtistRef>[])
        .map((a) => a.name)
        .where((n) => n.isNotEmpty)
        .take(2)
        .join(', ');
    // A card tinted with the song's own accent, so what is playing stands
    // apart from what is queued under it rather than being the first row of
    // the same list.
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 6, 14, 14),
      padding: const EdgeInsets.all(10),
      decoration: squircleDecoration(
        radius: 16,
        color: Color.alphaBlend(accent.withValues(alpha: 0.14), c.surface),
      ),
      child: Row(
        children: [
          SunohArt(
            id: song.id,
            imageUrl: song.artwork,
            size: 56,
            radius: SunohRadius.row,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SunohType.sans(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  artist.isEmpty ? '—' : artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SunohType.sans(fontSize: 13, color: c.fgDim),
                ),
              ],
            ),
          ),
          PlayingBars(color: accent, size: 20),
        ],
      ),
    );
  }
}

class QueueRow extends StatelessWidget {
  const QueueRow({
    super.key,
    required this.index,
    required this.song,
    required this.colors,
    required this.onTap,
    required this.onRemove,
  });
  final int index;
  final FeedItem song;
  final SunohColors colors;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final artist = (song.artists ?? const <ApiArtistRef>[])
        .map((a) => a.name)
        .where((n) => n.isNotEmpty)
        .take(2)
        .join(', ');
    final dur = _fmtDuration(song.duration);
    // Wrap the whole row in a faster delayed-drag listener so a long
    // press anywhere on the row (not just the handle) starts reordering.
    // Flutter's built-in `ReorderableDelayedDragStartListener` hard-codes
    // ~500 ms via `kLongPressTimeout` — see [_FastReorderListener] for the
    // local subclass that drops that to 200 ms.
    //
    // Removing is a swipe to the left, which uncovers a red "Remove" — the
    // row no longer carries a close button of its own next to the handle.
    return _FastReorderListener(
      index: index,
      child: Dismissible(
        key: ValueKey('q-$index-${song.id}'),
        direction: DismissDirection.endToStart,
        onDismissed: (_) => onRemove(),
        background: Container(
          color: c.danger,
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          child: Text(
            'Remove',
            style: SunohType.sans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: c.bg,
            ),
          ),
        ),
        child: Container(
          color: c.bgSoft,
          height: 60,
          padding: const EdgeInsets.only(left: 16, right: 4),
          child: Row(
            children: [
              SunohArt(
                id: song.id,
                imageUrl: song.artwork,
                size: 44,
                radius: SunohRadius.row,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: onTap,
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SunohType.sans(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w500,
                          color: c.fg,
                        ),
                      ),
                      if (artist.isNotEmpty)
                        Text(
                          artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SunohType.sans(fontSize: 12.5, color: c.fgDim),
                        ),
                    ],
                  ),
                ),
              ),
              if (dur != null) ...[
                const SizedBox(width: 10),
                Text(dur, style: SunohType.mono(fontSize: 12, color: c.fgMute)),
              ],
              ReorderableDragStartListener(
                index: index,
                child: SizedBox(
                  width: 40,
                  height: 60,
                  child: Icon(
                    RemixIcons.draggable,
                    size: 18,
                    color: c.fgMute,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class QueueHistoryRow extends StatelessWidget {
  const QueueHistoryRow({super.key, required this.song, required this.colors});
  final FeedItem song;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final artist = (song.artists ?? const <ApiArtistRef>[])
        .map((a) => a.name)
        .where((n) => n.isNotEmpty)
        .take(2)
        .join(', ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          SunohArt(
            id: song.id,
            imageUrl: song.artwork,
            size: 40,
            radius: SunohRadius.row,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SunohType.sans(fontSize: 15, color: c.fgDim),
                ),
                if (artist.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SunohType.sans(fontSize: 13, color: c.fgMute),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String? _fmtDuration(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final n = int.tryParse(raw);
  if (n == null) return raw;
  final m = n ~/ 60;
  final s = n % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// `ReorderableDragStartListener` subclass that uses a 200 ms long-press
/// delay instead of Flutter's built-in ~500 ms. The Material library's
/// `ReorderableDelayedDragStartListener` doesn't expose the delay, so
/// we re-implement the one line that matters: which recognizer to
/// construct. Everything else (drag handling, scroll-while-dragging,
/// proxyDecorator hookup) is inherited.
class _FastReorderListener extends ReorderableDragStartListener {
  const _FastReorderListener({required super.child, required super.index});

  @override
  MultiDragGestureRecognizer createRecognizer() {
    return DelayedMultiDragGestureRecognizer(
      delay: const Duration(milliseconds: 200),
      debugOwner: this,
    );
  }
}

/// A row being dragged: lifted onto a lighter surface with a deep shadow and
/// grown 2%, so it reads as picked up off the list.
Widget liftedQueueRow(Widget child, Animation<double> a, SunohColors c) =>
    AnimatedBuilder(
      animation: a,
      child: child,
      builder: (_, child) {
        final t = Curves.easeOut.transform(a.value);
        return Transform.scale(
          scale: 1 + 0.02 * t,
          child: DecoratedBox(
            decoration: squircleDecoration(
              radius: SunohRadius.card,
              color: c.surface2,
              shadows: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.55 * t),
                  blurRadius: 34,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Material(type: MaterialType.transparency, child: child),
          ),
        );
      },
    );
