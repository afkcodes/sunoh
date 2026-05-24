// Karaoke-style lyrics overlay with active-line highlight + auto-scroll.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';

import '../data/catalog.dart';
import '../data/models.dart';
import '../providers/app_state_provider.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/ui.dart';

class LyricsScreen extends ConsumerStatefulWidget {
  const LyricsScreen({super.key});
  @override
  ConsumerState<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends ConsumerState<LyricsScreen> {
  final controller = ScrollController();
  int _lastIdx = -2;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  int _activeIndex(List<LyricLine> lines, int position) {
    var idx = -1;
    for (var k = 0; k < lines.length; k++) {
      if (lines[k].t <= position) {
        idx = k;
      } else {
        break;
      }
    }
    return idx;
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final accent = s.resolvedAccent;
    final track = s.current;
    final lines = kLyrics[track.id] ?? kLyrics['t01']!;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [accent.withValues(alpha: 0.16), c.bg],
          stops: const [0, 0.6],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconBtn(icon: SolarIconsOutline.altArrowDown, color: c.fgDim, size: 22, onTap: () => context.pop()),
                  eyebrow('LYRICS', c.fgMute),
                  IconBtn(icon: SolarIconsOutline.share, color: c.fgDim, size: 18, onTap: () {}),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Row(
                children: [
                  SunohArt(id: track.id, size: 44, radius: 6),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(track.title,
                            style: SunohType.sans(fontSize: 13.5, fontWeight: FontWeight.w500, color: c.fg)),
                        const SizedBox(height: 1),
                        Text(track.artist, style: SunohType.sans(fontSize: 12, color: c.fgMute)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ValueListenableBuilder<int>(
                valueListenable: s.positionTick,
                builder: (context, pos, _) {
                  final idx = _activeIndex(lines, pos);
                  if (idx != _lastIdx) {
                    _lastIdx = idx;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!controller.hasClients) return;
                      final target = (idx.clamp(0, lines.length - 1) * 52.0 - 160)
                          .clamp(0.0, controller.position.maxScrollExtent);
                      controller.animateTo(target,
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeOutCubic);
                    });
                  }
                  return ListView.builder(
                    controller: controller,
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 80),
                    itemCount: lines.length,
                    itemBuilder: (context, i) {
                      final l = lines[i];
                      if (l.line.trim().isEmpty) return const SizedBox(height: 14);
                      final active = i == idx;
                      final past = i < idx;
                      return AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOutCubic,
                        style: SunohType.heading(
                          fontSize: active ? 28 : 22,
                          color: (c.fg).withValues(alpha: active ? 1.0 : (past ? 0.45 : 0.5)),
                          height: 1.3,
                          letterSpacing: -0.3,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Text(l.line),
                        ),
                      );
                    },
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
