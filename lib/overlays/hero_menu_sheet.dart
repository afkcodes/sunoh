// Entity-level (album / playlist / artist) action sheet — opened from the
// menu-dots in the detail screen's sticky header.
//
// Mirrors the style of [showTrackMenuSheet] but for the album/playlist/
// artist as a whole, not a single track: the same SheetSubject header and
// SheetRow actions. Actions vary by kind:
//   - album / playlist: Save/Unsave, View artist (when known), Download all,
//                       Share
//   - artist:           Follow/Unfollow (= toggle saved), Share
//
// Re-uses the AppState saved-collections (`isSaved` / `toggleSaved`) so
// the heart state stays in sync with the hero like button + library tab.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remixicon/remixicon.dart';

import '../api/dto.dart';
import '../data/models.dart';
import '../providers/app_state_provider.dart';
import '../providers/downloads_provider.dart';
import '../router/router.dart';
import '../share/share_link.dart';
import 'sheet.dart';
import 'sheet_row.dart';

/// Show the menu-dots sheet for an album / playlist / artist. [entity] is
/// a synthesized [FeedItem] carrying just the id / type / title / image
/// fields — enough for the sheet to render the header + persist the save
/// state.
///
/// [artist] is optional — when present (and the entity is an album/
/// playlist with a single primary artist), a "View [name]" row is shown
/// that pops the sheet + navigates.
///
/// [songs] is optional — when provided AND the entity isn't gaana, the
/// sheet shows a "Download all" row that enqueues every track into the
/// download manager. Pass an empty list (or omit) for hero kinds that
/// don't carry a flat song list (e.g. artist screens, where the songs
/// live behind a separate `topSongs` accessor).
Future<void> showHeroMenuSheet(
  BuildContext context, {
  required FeedItem entity,
  ApiArtistRef? artist,
  List<FeedItem> songs = const [],
}) {
  return showSunohSheet<void>(
    context,
    builder: (_) =>
        _HeroMenuSheet(entity: entity, artist: artist, songs: songs),
  );
}

class _HeroMenuSheet extends ConsumerWidget {
  const _HeroMenuSheet({
    required this.entity,
    this.artist,
    this.songs = const [],
  });
  final FeedItem entity;
  final ApiArtistRef? artist;
  final List<FeedItem> songs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final saved = s.isSaved(entity);
    final isArtist = entity.type == 'artist';
    final a = artist;

    // Per-kind copy. Artists "follow", everything else "saves".
    final savedLabel = isArtist
        ? (saved ? 'Unfollow' : 'Follow')
        : (saved ? 'Remove from Library' : 'Save to Library');

    return SunohSheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SheetSubject(
            id: entity.id,
            imageUrl: entity.artwork,
            title: entity.title,
            subtitle: entity.type[0].toUpperCase() + entity.type.substring(1),
            round: isArtist,
            colors: c,
          ),
          SheetRow(
            icon: saved ? RemixIcons.heart_3_fill : RemixIcons.heart_3_line,
            iconColor: saved ? c.accent : null,
            label: savedLabel,
            onTap: () {
              Navigator.of(context).pop();
              s.toggleSaved(entity);
            },
            colors: c,
          ),
          if (a != null && !isArtist && a.id.isNotEmpty)
            SheetRow(
              icon: RemixIcons.user_3_line,
              label: 'View ${a.name}',
              onTap: () {
                Navigator.of(context).pop();
                if (entity.source == 'youtube') {
                  context.openYtArtist(a.id, name: a.name);
                  return;
                }
                context.openRef(
                  DetailRef('artist', a.id, source: entity.source),
                );
              },
              colors: c,
            ),
          // Bulk download for albums/playlists — fans every track out to the
          // download manager, capped at 2 concurrent by the manager's own
          // queue. Hidden only for entity kinds without a flat song list
          // (artist, etc — caller passes [] or omits `songs`); gaana's HLS is
          // handled in audio/hls_download.dart.
          if (songs.isNotEmpty)
            SheetRow(
              icon: RemixIcons.download_2_line,
              label: 'Download all (${songs.length})',
              onTap: () {
                Navigator.of(context).pop();
                ref.read(downloadManagerProvider).enqueueAll(songs);
                s.flashToast('Queued ${songs.length} tracks');
              },
              colors: c,
            ),
          SheetRow(
            icon: RemixIcons.share_forward_line,
            label: 'Share',
            onTap: () {
              Navigator.of(context).pop();
              shareSunohLink(
                kind: entity.type,
                id: entity.id,
                title: entity.title,
                subtitle: entity.displaySubtitle ?? entity.subtitle,
                source: entity.source,
              );
            },
            colors: c,
          ),
        ],
      ),
    );
  }
}
