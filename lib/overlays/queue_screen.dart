// Queue overlay — now playing + reorderable up-next list + history.
//
// Two render paths:
//   - API mode (`AppState.currentApiSong != null`): reads live from the
//     engine queue via `AppState.apiUpNext` / `audioRepo.queueListenable`,
//     and `apiHistory`. Drag-reorder, tap-to-jump, ×-remove, clear-all
//     delegate through AppState → AudioRepo → mpv playlist mutations.
//   - Dummy mode: keeps the legacy Track-based catalog path.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:remixicon/remixicon.dart';

import '../api/dto.dart';
import '../data/catalog.dart';
import '../providers/app_state_provider.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/playing_bars.dart';
import '../widgets/ui.dart';
import 'queue_menu_sheet.dart';
import 'queue_rows.dart';
import 'sheet.dart';

class QueueScreen extends ConsumerWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;

    // If a real API song is playing, render the API queue. Otherwise fall
    // back to the dummy track queue (stations / podcast paths).
    final inApi = s.currentApiSong != null && s.audioRepo != null;
    final repo = s.audioRepo;

    // A sheet over the player (see player_route.dart): rounded top, the
    // soft surface, a grabber, and the title where the old eyebrow was.
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: c.bgSoft,
        shape: squircleTopBorder(SunohRadius.sheet),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 8),
            SheetHandle(colors: c),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Queue',
                      style: SunohType.heading(fontSize: 22, color: c.fg),
                    ),
                  ),
                  IconBtn(
                    icon: RemixIcons.more_fill,
                    color: c.fgDim,
                    size: 20,
                    onTap: () => showQueueMenuSheet(context),
                  ),
                  IconBtn(
                    icon: RemixIcons.arrow_down_s_line,
                    color: c.fg,
                    size: 22,
                    onTap: () => context.pop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: inApi
                  ? _ApiQueueBody(colors: c, ref: ref)
                  : _DummyQueueBody(s: s, colors: c),
            ),
            // Hint about how many tracks are in the live queue.
            if (inApi && repo != null)
              ValueListenableBuilder<List<FeedItem>>(
                valueListenable: repo.queueListenable,
                builder: (_, q, _) {
                  final upNext = q.length - repo.currentIndex - 1;
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$upNext ${upNext == 1 ? 'track' : 'tracks'} remaining',
                          style: SunohType.sans(fontSize: 12, color: c.fgMute),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

// ── API mode (real engine queue) ───────────────────────────────────────────

class _ApiQueueBody extends StatelessWidget {
  const _ApiQueueBody({required this.colors, required this.ref});
  final SunohColors colors;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appStateProvider);
    final c = colors;
    final cur = s.currentApiSong!;
    final repo = s.audioRepo!;

    return ValueListenableBuilder<List<FeedItem>>(
      valueListenable: repo.queueListenable,
      builder: (_, q, _) {
        final upNext = s.apiUpNext;
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 6),
                  QueueNowPlayingRow(song: cur, accent: c.accent, colors: c),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text.rich(
                          TextSpan(
                            text: 'Next up',
                            style: SunohType.sans(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: c.fg,
                            ),
                            children: [
                              TextSpan(
                                text: '  ${upNext.length}',
                                style: SunohType.mono(
                                  fontSize: 12.5,
                                  color: c.fgDim,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (upNext.isNotEmpty)
                          GestureDetector(
                            onTap: s.apiClearUpNext,
                            child: Text(
                              'Clear',
                              style: SunohType.sans(
                                fontSize: 13,
                                color: c.fgDim,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (upNext.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 32,
                      ),
                      child: Center(
                        child: Text(
                          'Nothing else queued.',
                          style: SunohType.sans(
                            fontSize: 12.5,
                            color: c.fgMute,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (upNext.isNotEmpty)
              SliverReorderableList(
                itemCount: upNext.length,
                onReorderItem: s.apiReorderUpNext,
                proxyDecorator: (child, _, a) => liftedQueueRow(child, a, c),
                itemBuilder: (context, i) {
                  final song = upNext[i];
                  return QueueRow(
                    key: ValueKey('${song.id}:$i'),
                    index: i,
                    song: song,
                    colors: c,
                    onTap: () => s.apiJumpToUpNext(i),
                    onRemove: () => s.apiRemoveFromUpNext(i),
                  );
                },
              ),
            if (s.playedHistory.isNotEmpty)
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                      child: eyebrow('RECENTLY PLAYED', c.fgMute),
                    ),
                    for (final h in s.playedHistory.take(10))
                      Opacity(
                        opacity: 0.7,
                        child: QueueHistoryRow(song: h, colors: c),
                      ),
                    const SizedBox(height: 80),
                  ],
                ),
              )
            else
              const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        );
      },
    );
  }
}

// ── Dummy mode (legacy Track-based catalog path) ───────────────────────────

class _DummyQueueBody extends StatelessWidget {
  const _DummyQueueBody({required this.s, required this.colors});
  final dynamic s;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final accent = c.accent;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                child: eyebrow('NOW PLAYING', c.fgMute),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
                child: Row(
                  children: [
                    SunohArt(
                      id: s.current.id,
                      size: 56,
                      radius: SunohRadius.row,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.current.title,
                            style: SunohType.sans(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: accent,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            s.current.artist,
                            style: SunohType.sans(
                              fontSize: 12.5,
                              color: c.fgMute,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PlayingBars(color: accent, size: 20),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    eyebrow('NEXT UP · ${s.queue.length} TRACKS', c.fgMute),
                    Text(
                      'Clear',
                      style: SunohType.sans(
                        fontSize: 13,
                        color: c.fgDim,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SliverReorderableList(
          itemCount: s.queue.length,
          onReorderItem: s.reorderQueue,
          itemBuilder: (context, i) {
            final t = s.queue[i];
            return Container(
              key: ValueKey('${t.id}:$i'),
              color: c.bg,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  ReorderableDragStartListener(
                    index: i,
                    child: Icon(
                      RemixIcons.draggable,
                      size: 16,
                      color: c.fgMute.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SunohArt(id: t.id, size: 42, radius: SunohRadius.row),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => s.jumpQueue(i),
                      behavior: HitTestBehavior.opaque,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SunohType.sans(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                              color: c.fg,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            t.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SunohType.sans(
                              fontSize: 11.5,
                              color: c.fgMute,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    fmt(t.duration),
                    style: SunohType.mono(fontSize: 10, color: c.fgMute),
                  ),
                  IconBtn(
                    icon: RemixIcons.close_circle_line,
                    color: c.fgMute,
                    size: 14,
                    width: 32,
                    height: 32,
                    onTap: () => s.removeFromQueue(i),
                  ),
                ],
              ),
            );
          },
        ),
        if (s.history.isNotEmpty)
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                  child: eyebrow('RECENTLY PLAYED', c.fgMute),
                ),
                for (final t in s.history)
                  Opacity(
                    opacity: 0.6,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          SunohArt(id: t.id, size: 36, radius: SunohRadius.row),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: SunohType.sans(
                                    fontSize: 13,
                                    color: c.fgDim,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  t.artist,
                                  style: SunohType.sans(
                                    fontSize: 11,
                                    color: c.fgMute,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 80),
              ],
            ),
          )
        else
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }
}
