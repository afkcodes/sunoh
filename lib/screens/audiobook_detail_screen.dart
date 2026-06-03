// Audiobook detail screen — book metadata + chapter list.
//
// Big cover hero on top with title + author, then a "Play from start"
// button, then the chapter list. Tap any chapter row → playApiQueue
// over the full chapter list starting at that index. Standard
// PlayMode.track (finite content). The audio engine treats it like
// an album.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../api/dto.dart';
import '../providers/app_state_provider.dart';
import '../providers/audiobook_provider.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/ui.dart';

class AudiobookDetailScreen extends ConsumerWidget {
  const AudiobookDetailScreen({
    super.key,
    required this.slug,
    this.seed,
  });
  final String slug;
  /// Optional FeedItem the tile that opened this screen was rendered
  /// from. When present, the hero shows the cached title + cover before
  /// the network detail resolves — avoids a flash of empty state.
  final FeedItem? seed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final async = ref.watch(audiobookDetailProvider(slug));

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(SolarIconsOutline.altArrowLeft, color: c.fg),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          seed?.title ?? 'Audiobook',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: SunohType.sans(
              fontSize: 15, fontWeight: FontWeight.w500, color: c.fg),
        ),
      ),
      body: async.when(
        data: (d) {
          if (d == null) {
            return _MissingState(colors: c);
          }
          return _Loaded(detail: d, colors: c, seed: seed);
        },
        loading: () => _LoadingHero(seed: seed, colors: c),
        error: (_, _) => _MissingState(colors: c),
      ),
    );
  }
}

class _Loaded extends ConsumerWidget {
  const _Loaded({required this.detail, required this.colors, this.seed});
  final AudiobookDetail detail;
  final SunohColors colors;
  final FeedItem? seed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    final s = ref.read(appStateProvider);
    final cover = detail.cover ?? seed?.artwork;
    final chapters = detail.chapters;

    void playFromIndex(int i) {
      if (chapters.isEmpty) return;
      s.playApiQueue(
        chapters,
        i,
        sourceLabel: 'AUDIOBOOK · ${detail.title}',
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              squircleClip(
                radius: 16,
                child: SunohArt(
                  id: detail.id,
                  imageUrl: cover,
                  size: 132,
                  radius: 16,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      detail.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: SunohType.sans(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: c.fg,
                        height: 1.2,
                      ),
                    ),
                    if ((detail.author ?? '').isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        detail.author!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: SunohType.sans(
                          fontSize: 13,
                          color: c.fgDim,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      '${chapters.length} chapter'
                      '${chapters.length == 1 ? '' : 's'}',
                      style: SunohType.sans(
                          fontSize: 12, color: c.fgMute),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: chapters.isEmpty ? null : () => playFromIndex(0),
              icon: const Icon(SolarIconsBold.play, size: 16),
              label: const Text('Play from start'),
              style: ElevatedButton.styleFrom(
                backgroundColor: s.resolvedAccent,
                foregroundColor: c.fg,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ),
        if (chapters.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Text(
              'No chapters parsed for this book. Tap "Play from start" once '
              'the upstream lists them.',
              style: SunohType.sans(fontSize: 13, color: c.fgMute),
            ),
          )
        else
          for (int i = 0; i < chapters.length; i++)
            _ChapterRow(
              chapter: chapters[i],
              index: i,
              colors: c,
              onTap: () => playFromIndex(i),
            ),
      ],
    );
  }
}

class _ChapterRow extends StatelessWidget {
  const _ChapterRow({
    required this.chapter,
    required this.index,
    required this.colors,
    required this.onTap,
  });
  final FeedItem chapter;
  final int index;
  final SunohColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final duration = chapter.duration ?? '';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '${index + 1}',
                style: SunohType.mono(
                  fontSize: 13,
                  color: c.fgMute,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                chapter.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SunohType.sans(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: c.fg,
                ),
              ),
            ),
            if (duration.isNotEmpty)
              Text(
                duration,
                style: SunohType.mono(
                  fontSize: 12,
                  color: c.fgMute,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LoadingHero extends StatelessWidget {
  const _LoadingHero({required this.seed, required this.colors});
  final FeedItem? seed;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              squircleClip(
                radius: 16,
                child: SunohArt(
                  id: seed?.id ?? '',
                  imageUrl: seed?.artwork,
                  size: 132,
                  radius: 16,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      seed?.title ?? 'Loading…',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: SunohType.sans(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: c.fg,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 16,
                      child:
                          LinearProgressIndicator(color: c.fgMute, value: null),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MissingState extends StatelessWidget {
  const _MissingState({required this.colors});
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Couldn’t load this audiobook. Try again later.',
          textAlign: TextAlign.center,
          style: SunohType.sans(fontSize: 13, color: colors.fgMute),
        ),
      ),
    );
  }
}
