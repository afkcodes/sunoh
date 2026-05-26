// Entity-level (album / playlist / artist) action sheet — opened from the
// menu-dots in the detail screen's sticky header.
//
// Mirrors the style of [showTrackMenuSheet] but for the album/playlist/
// artist as a whole, not a single track. Actions vary by kind:
//   - album / playlist: Save/Unsave, Share, View artist (when known)
//   - artist:           Follow/Unfollow (= toggle saved), Share
//
// Re-uses the AppState saved-collections (`isSaved` / `toggleSaved`) so
// the heart state stays in sync with the hero like button + library tab.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../api/dto.dart';
import '../data/models.dart';
import '../providers/app_state_provider.dart';
import '../router/router.dart';
import '../share/share_link.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/ui.dart';

/// Show the menu-dots sheet for an album / playlist / artist. [entity] is
/// a synthesized [FeedItem] carrying just the id / type / title / image
/// fields — enough for the sheet to render the header + persist the save
/// state.
///
/// [artist] is optional — when present (and the entity is an album/
/// playlist with a single primary artist), a "View [name]" row is shown
/// that pops the sheet + navigates.
Future<void> showHeroMenuSheet(
  BuildContext context, {
  required FeedItem entity,
  ApiArtistRef? artist,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useRootNavigator: true,
    builder: (_) => _HeroMenuSheet(entity: entity, artist: artist),
  );
}

class _HeroMenuSheet extends ConsumerWidget {
  const _HeroMenuSheet({required this.entity, this.artist});
  final FeedItem entity;
  final ApiArtistRef? artist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final accent = s.resolvedAccent;
    final saved = s.isSaved(entity);
    final isArtist = entity.type == 'artist';
    final topInset = MediaQuery.of(context).padding.bottom;

    // Per-kind copy. Artists "follow", everything else "saves".
    final savedLabel = isArtist
        ? (saved ? 'Unfollow' : 'Follow')
        : (saved ? 'Remove from Library' : 'Save to Library');

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        decoration: squircleDecoration(
          radius: 20,
          color: const Color(0xFF15151A),
          borderColor: c.line,
        ),
        padding: EdgeInsets.fromLTRB(0, 8, 0, 8 + topInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
              child: Row(
                children: [
                  SunohArt(
                    id: entity.id,
                    imageUrl: entity.artwork,
                    size: 52,
                    radius: isArtist ? 999 : 8,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entity.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: SunohType.sans(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w500,
                                color: c.fg,
                                height: 1.2)),
                        const SizedBox(height: 3),
                        Text(
                          entity.type[0].toUpperCase() +
                              entity.type.substring(1),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SunohType.sans(fontSize: 12, color: c.fgMute),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
                height: 0.5,
                color: c.line,
                margin: const EdgeInsets.symmetric(horizontal: 12)),
            _HeroMenuRow(
              icon: saved ? SolarIconsBold.heart : SolarIconsOutline.heart,
              iconColor: saved ? accent : c.fg,
              label: savedLabel,
              onTap: () {
                Navigator.of(context).pop();
                s.toggleSaved(entity);
              },
              colors: c,
            ),
            if (artist != null && !isArtist && artist!.id.isNotEmpty)
              _HeroMenuRow(
                icon: SolarIconsOutline.user,
                label: 'View ${artist!.name}',
                onTap: () {
                  Navigator.of(context).pop();
                  context.openRef(DetailRef('artist', artist!.id,
                      source: entity.source));
                },
                colors: c,
              ),
            _HeroMenuRow(
              icon: SolarIconsOutline.share,
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
      ),
    );
  }
}

class _HeroMenuRow extends StatelessWidget {
  const _HeroMenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.colors,
    this.iconColor,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final SunohColors colors;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: iconColor ?? c.fg),
            const SizedBox(width: 16),
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SunohType.sans(fontSize: 14, color: c.fg)),
            ),
          ],
        ),
      ),
    );
  }
}
