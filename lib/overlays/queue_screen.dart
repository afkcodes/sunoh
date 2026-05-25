// Queue overlay — now playing + reorderable up-next list + history.
//
// Two render paths:
//   - API mode (`AppState.currentApiSong != null`): reads live from the
//     engine queue via `AppState.apiUpNext` / `audioRepo.queueListenable`,
//     and `apiHistory`. Drag-reorder, tap-to-jump, ×-remove, clear-all
//     delegate through AppState → AudioRepo → mpv playlist mutations.
//   - Dummy mode: keeps the legacy Track-based path (radio stations etc.).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';

import '../api/dto.dart';
import '../data/catalog.dart';
import '../providers/app_state_provider.dart';
import '../theme/tokens.dart';
import 'queue_menu_sheet.dart';
import '../widgets/album_art.dart';
import '../widgets/playing_bars.dart';
import '../widgets/ui.dart';

class QueueScreen extends ConsumerWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final accent = s.resolvedAccent;

    // If a real API song is playing, render the API queue. Otherwise fall
    // back to the dummy track queue (stations / podcast paths).
    final inApi = s.currentApiSong != null && s.audioRepo != null;
    final repo = s.audioRepo;

    return ColoredBox(
      color: c.bg,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconBtn(
                      icon: SolarIconsOutline.altArrowDown,
                      color: c.fgDim,
                      size: 22,
                      onTap: () => context.pop()),
                  eyebrow('QUEUE', c.fgMute),
                  IconBtn(
                      icon: SolarIconsBold.menuDots,
                      color: c.fgDim,
                      size: 20,
                      onTap: () => showQueueMenuSheet(context)),
                ],
              ),
            ),
            Expanded(
              child: inApi
                  ? _ApiQueueBody(accent: accent, colors: c, ref: ref)
                  : _DummyQueueBody(s: s, accent: accent, colors: c),
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
                        eyebrow(
                            '$upNext ${upNext == 1 ? 'TRACK' : 'TRACKS'} REMAINING',
                            c.fgMute,
                            size: 10),
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
  const _ApiQueueBody(
      {required this.accent, required this.colors, required this.ref});
  final Color accent;
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                    child: eyebrow('NOW PLAYING', c.fgMute),
                  ),
                  _ApiNowPlayingRow(song: cur, accent: accent, colors: c),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        eyebrow('NEXT UP · ${upNext.length} TRACKS', c.fgMute),
                        if (upNext.isNotEmpty)
                          GestureDetector(
                            onTap: s.apiClearUpNext,
                            child: Text('Clear',
                                style: SunohType.sans(
                                    fontSize: 11,
                                    color: c.fgMute,
                                    fontWeight: FontWeight.w500)),
                          ),
                      ],
                    ),
                  ),
                  if (upNext.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 32),
                      child: Center(
                        child: Text(
                          'Nothing else queued.',
                          style: SunohType.sans(
                              fontSize: 12.5, color: c.fgMute),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (upNext.isNotEmpty)
              SliverReorderableList(
                itemCount: upNext.length,
                onReorder: s.apiReorderUpNext,
                itemBuilder: (context, i) {
                  final song = upNext[i];
                  return _ApiQueueRow(
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
                      child:
                          eyebrow('RECENTLY PLAYED', c.fgMute),
                    ),
                    for (final h in s.playedHistory.take(10))
                      Opacity(
                        opacity: 0.7,
                        child: _ApiHistoryRow(song: h, colors: c),
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

class _ApiNowPlayingRow extends StatelessWidget {
  const _ApiNowPlayingRow(
      {required this.song, required this.accent, required this.colors});
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
      child: Row(
        children: [
          SunohArt(id: song.id, imageUrl: song.artwork, size: 56, radius: 6),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SunohType.sans(
                        fontSize: 15, fontWeight: FontWeight.w500, color: accent)),
                const SizedBox(height: 2),
                Text(artist.isEmpty ? '—' : artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SunohType.sans(fontSize: 12.5, color: c.fgMute)),
              ],
            ),
          ),
          PlayingBars(color: accent, size: 20),
        ],
      ),
    );
  }
}

class _ApiQueueRow extends StatelessWidget {
  const _ApiQueueRow({
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
    return Container(
      color: c.bg,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: Icon(SolarIconsOutline.hamburgerMenu,
                size: 16, color: c.fgMute.withValues(alpha: 0.6)),
          ),
          const SizedBox(width: 8),
          SunohArt(id: song.id, imageUrl: song.artwork, size: 42, radius: 4),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SunohType.sans(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          color: c.fg)),
                  if (artist.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SunohType.sans(fontSize: 11.5, color: c.fgMute)),
                  ],
                ],
              ),
            ),
          ),
          if (dur != null) ...[
            const SizedBox(width: 8),
            Text(dur, style: SunohType.mono(fontSize: 10, color: c.fgMute)),
          ],
          IconBtn(
            icon: SolarIconsOutline.closeCircle,
            color: c.fgMute,
            size: 14,
            width: 32,
            height: 32,
            onTap: onRemove,
          ),
        ],
      ),
    );
  }
}

class _ApiHistoryRow extends StatelessWidget {
  const _ApiHistoryRow({required this.song, required this.colors});
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
          SunohArt(id: song.id, imageUrl: song.artwork, size: 36, radius: 4),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SunohType.sans(fontSize: 13, color: c.fgDim)),
                if (artist.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SunohType.sans(fontSize: 11, color: c.fgMute)),
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

// ── Dummy mode (legacy Track-based) — kept for radio stations etc. ──────────

class _DummyQueueBody extends StatelessWidget {
  const _DummyQueueBody(
      {required this.s, required this.accent, required this.colors});
  final dynamic s;
  final Color accent;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
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
                    SunohArt(id: s.current.id, size: 56, radius: 6),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.current.title,
                              style: SunohType.sans(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: accent)),
                          const SizedBox(height: 2),
                          Text(s.current.artist,
                              style: SunohType.sans(
                                  fontSize: 12.5, color: c.fgMute)),
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
                    Text('Clear',
                        style: SunohType.sans(fontSize: 11, color: c.fgMute)),
                  ],
                ),
              ),
            ],
          ),
        ),
        SliverReorderableList(
          itemCount: s.queue.length,
          onReorder: s.reorderQueue,
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
                    child: Icon(SolarIconsOutline.hamburgerMenu,
                        size: 16, color: c.fgMute.withValues(alpha: 0.6)),
                  ),
                  const SizedBox(width: 8),
                  SunohArt(id: t.id, size: 42, radius: 4),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => s.jumpQueue(i),
                      behavior: HitTestBehavior.opaque,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: SunohType.sans(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w500,
                                  color: c.fg)),
                          const SizedBox(height: 1),
                          Text(t.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: SunohType.sans(
                                  fontSize: 11.5, color: c.fgMute)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(fmt(t.duration),
                      style: SunohType.mono(fontSize: 10, color: c.fgMute)),
                  IconBtn(
                    icon: SolarIconsOutline.closeCircle,
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
                      padding:
                          const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      child: Row(
                        children: [
                          SunohArt(id: t.id, size: 36, radius: 4),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(t.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: SunohType.sans(
                                        fontSize: 13, color: c.fgDim)),
                                const SizedBox(height: 1),
                                Text(t.artist,
                                    style: SunohType.sans(
                                        fontSize: 11, color: c.fgMute)),
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

