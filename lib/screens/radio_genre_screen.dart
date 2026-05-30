// Stations within a single genre.
//
// Vertical list of `_StationRow`s. Tap = play live (PlayMode.live).
// Country-aware via the device locale, just like the Radio tab home.
//
// Pagination is deferred: we ask the API for 50 stations per genre
// (the upstream's max is 100). The Spotify-importer-style scroll
// pagination pattern would be the next step if we hit a genre with
// hundreds of stations, but for the common case 50 is plenty.

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';

import '../api/dto.dart';
import '../audio/audio_handler.dart' show PlayMode;
import '../providers/app_state_provider.dart';
import '../providers/radio_provider.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/playing_bars.dart';
import '../widgets/ui.dart';
import 'radio_tab.dart' show titleCase;

class RadioGenreScreen extends ConsumerWidget {
  const RadioGenreScreen({super.key, required this.genre});
  final String genre;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final accent = s.resolvedAccent;
    final country =
        PlatformDispatcher.instance.locale.countryCode?.toUpperCase();
    final async = ref.watch(
        radiosByGenreProvider(RadioGenreKey(genre: genre, country: country)));

    return ColoredBox(
      color: c.bg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 12, 14, 4),
              child: Row(
                children: [
                  IconBtn(
                    icon: SolarIconsOutline.altArrowLeft,
                    color: c.fg,
                    size: 22,
                    onTap: () => context.pop(),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      titleCase(genre),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SunohType.heading(
                        fontSize: 24,
                        color: c.fg,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                country == null
                    ? 'Live stations'
                    : 'Live stations · $country',
                style: SunohType.sans(fontSize: 13, color: c.fgMute),
              ),
            ),
            Expanded(
              child: async.when(
                loading: () => Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: c.fgDim,
                    ),
                  ),
                ),
                error: (e, _) => _GenreErrorState(
                  colors: c,
                  accent: accent,
                  onRetry: () => ref.invalidate(radiosByGenreProvider(
                      RadioGenreKey(genre: genre, country: country))),
                ),
                data: (stations) {
                  if (stations.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No stations for ${titleCase(genre)} yet.',
                        style:
                            SunohType.sans(fontSize: 13, color: c.fgMute),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 140),
                    itemCount: stations.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 4),
                    itemBuilder: (context, i) => _StationRow(
                      station: stations[i],
                      colors: c,
                      accent: accent,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StationRow extends ConsumerWidget {
  const _StationRow({
    required this.station,
    required this.colors,
    required this.accent,
  });
  final FeedItem station;
  final SunohColors colors;
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    final s = ref.watch(appStateProvider);
    final isCurrent = s.currentApiSong?.id == station.id;
    return GestureDetector(
      onTap: () => s.playApiQueue(
        [station],
        0,
        sourceLabel: 'RADIO · ${station.title}',
        mode: PlayMode.live,
      ),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: isCurrent
              ? accent.withValues(alpha: 0.06)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            squircleClip(
              radius: 8,
              child: SunohArt(
                id: station.id,
                imageUrl: station.artwork,
                size: 56,
                radius: 8,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    station.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SunohType.sans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isCurrent ? accent : c.fg,
                    ),
                  ),
                  if ((station.subtitle ?? '').isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      station.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          SunohType.sans(fontSize: 12, color: c.fgMute),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (isCurrent && s.isPlaying)
              SizedBox(
                width: 24,
                height: 24,
                child: Center(
                  child: PlayingBars(color: accent, size: 18),
                ),
              )
            else
              Icon(SolarIconsBold.playCircle, color: accent, size: 28),
          ],
        ),
      ),
    );
  }
}

/// Centered error block — medallion + title + retry chip. Same shape
/// as the Radio tab's _RadioMessageBlock; duplicated here rather than
/// extracted because the cross-screen reuse is shallow and each
/// instance reads cleanly on its own.
class _GenreErrorState extends StatelessWidget {
  const _GenreErrorState({
    required this.colors,
    required this.accent,
    required this.onRetry,
  });
  final SunohColors colors;
  final Color accent;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 32, 32, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: 0.16),
              ),
              alignment: Alignment.center,
              child: Icon(SolarIconsOutline.wifiRouterRound,
                  color: accent, size: 24),
            ),
            const SizedBox(height: 16),
            Text(
              'Couldn’t load stations',
              style: SunohType.heading(
                  fontSize: 15, color: c.fg, letterSpacing: -0.2),
            ),
            const SizedBox(height: 6),
            Text(
              'Check your connection and try again.',
              textAlign: TextAlign.center,
              style: SunohType.sans(fontSize: 12.5, color: c.fgMute),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: onRetry,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: squircleDecoration(
                  radius: 999,
                  color: accent.withValues(alpha: 0.14),
                  borderColor: accent.withValues(alpha: 0.32),
                ),
                child: Text(
                  'Try again',
                  style: SunohType.sans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: accent,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
