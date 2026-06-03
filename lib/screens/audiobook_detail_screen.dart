// Audiobook detail — reuses the canonical `AlbumLikeBody` shell so the
// hero, palette gradient, sticky header, hero actions (play / shuffle
// / heart / download / add), and the `_ApiTrackRow` chapter rows all
// match album / playlist / liked-songs visually. Chapters arrive as
// FeedItem with `type: 'song'`, which the existing track-row + queue +
// player handle natively.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dto.dart';
import '../data/models.dart';
import '../providers/app_state_provider.dart';
import '../providers/audiobook_provider.dart';
import 'detail_screens.dart' show AlbumLikeBody, DetailLoading;

class AudiobookDetailScreen extends ConsumerWidget {
  const AudiobookDetailScreen({
    super.key,
    required this.slug,
    this.seed,
  });
  final String slug;
  /// Optional tile-source FeedItem so the hero can show title + cover
  /// before the network detail resolves. AlbumLikeBody owns the hero
  /// fade-in; passing the cached values keeps the loading state honest
  /// rather than a flash of empty hero.
  final FeedItem? seed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final async = ref.watch(audiobookDetailProvider(slug));

    if (async.isLoading) return DetailLoading(colors: c);
    final detail = async.asData?.value;
    if (detail == null) return DetailLoading(colors: c);

    final cover = detail.cover ?? seed?.artwork;
    final chapters = detail.chapters;
    final author = detail.author ?? seed?.subtitle;

    return AlbumLikeBody(
      colors: c,
      id: slug,
      title: detail.title,
      imageUrl: cover,
      eyebrowText: 'AUDIOBOOK',
      sub: author,
      secondary: chapters.isEmpty
          ? null
          : '${chapters.length} chapter${chapters.length == 1 ? '' : 's'}',
      songs: chapters,
      sections: const <HomeSection>[],
      // Each chapter shares the book cover, so the per-row art column
      // is redundant — same call album-mode makes (album art shown
      // only in the hero, not per track).
      showAlbumArtInRow: false,
      sourceRef: DetailRef('audiobook', slug, source: detail.link),
    );
  }
}
