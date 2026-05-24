// Podcasts tab — continue listening, subscriptions, top this week.
// Ported from radio.jsx PodcastsTab.

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../router/router.dart';

import '../data/catalog.dart';
import '../data/models.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/ui.dart';

class PodcastsTab extends StatelessWidget {
  const PodcastsTab({super.key, required this.colors});
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final continueListening = kEpisodes.take(3).toList();
    // deterministic-ish progress for each (stable across rebuilds)
    final progress = [0.42, 0.58, 0.33];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // continue listening
        SectionHeader(
            title: 'Continue listening',
            
            colors: c),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              for (var i = 0; i < continueListening.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                _ContinueCard(
                  episode: continueListening[i],
                  progress: progress[i % progress.length],
                  colors: c,
                  onTap: () => context.openRef(DetailRef('podcast', continueListening[i].pod)),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 40),

        // subscriptions
        SectionHeader(title: 'Subscriptions',  colors: c),
        SizedBox(
          height: 220,
          child: HCardRow<Podcast>(
            items: kPodcasts,
            width: 160,
            onTap: (p) => context.openRef(DetailRef('podcast', p.id)),
            builder: (p, w) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SunohArt(id: p.id, size: w, radius: 6),
                const SizedBox(height: 8),
                Text(p.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SunohType.sans(
                        fontSize: 13.5, fontWeight: FontWeight.w500, color: c.fg, height: 1.2)),
                const SizedBox(height: 3),
                eyebrow('${p.cadence} · ${p.host}', c.fgMute, size: 10, letterSpacing: 0.4),
              ],
            ),
          ),
        ),
        const SizedBox(height: 40),

        // top this week
        SectionHeader(title: 'Top this week',  colors: c),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              for (var i = 0; i < kPodcasts.length; i++)
                GestureDetector(
                  onTap: () => context.openRef(DetailRef('podcast', kPodcasts[i].id)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 24,
                          child: Text('${i + 1}',
                              textAlign: TextAlign.center,
                              style: SunohType.heading(fontSize: 24, color: c.fgMute)),
                        ),
                        const SizedBox(width: 14),
                        SunohArt(id: kPodcasts[i].id, size: 48, radius: 6),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(kPodcasts[i].title,
                                  style: SunohType.sans(
                                      fontSize: 14, fontWeight: FontWeight.w500, color: c.fg)),
                              const SizedBox(height: 2),
                              Text(kPodcasts[i].host,
                                  style: SunohType.sans(fontSize: 11.5, color: c.fgMute)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({
    required this.episode,
    required this.progress,
    required this.colors,
    required this.onTap,
  });
  final Episode episode;
  final double progress;
  final SunohColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final pod = podcastOf(episode.pod)!;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: squircleDecoration(radius: 12, color: c.surface, borderColor: c.line),
        child: Row(
          children: [
            SunohArt(id: episode.pod, size: 56, radius: 6),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  eyebrow(pod.title, c.fgMute, size: 9, letterSpacing: 1.2),
                  const SizedBox(height: 2),
                  Text(episode.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SunohType.sans(
                          fontSize: 13.5, fontWeight: FontWeight.w500, color: c.fg, height: 1.25)),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(1),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 2,
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                      valueColor: AlwaysStoppedAnimation(c.accent),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: c.line, width: 0.5),
              ),
              child: Icon(PhosphorIconsFill.play, size: 16, color: c.fg),
            ),
          ],
        ),
      ),
    );
  }
}
