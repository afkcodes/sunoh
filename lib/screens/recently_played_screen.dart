// Full Recently Played list — opened from the Library tab. No hero (it's a
// transient list, not a curated playlist): a big page title, then the rows,
// with the pinned bar taking the title over once it scrolls away.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../overlays/confirm_sheet.dart';
import '../providers/app_state_provider.dart';
import '../theme/tokens.dart';
import '../widgets/motion.dart';
import 'detail_chrome.dart';
import 'detail_track_row.dart';

class RecentlyPlayedScreen extends ConsumerWidget {
  const RecentlyPlayedScreen({super.key});

  static const String _label = 'RECENTLY PLAYED';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final history = s.playedHistory;
    final labels = TrackLabels.of(history);

    return DetailPage(
      colors: c,
      colour: c.bg,
      title: 'Recently Played',
      solidAt: PageTitle.solidAt,
      builder: (_) => [
        SliverToBoxAdapter(
          child: PageTitle(
            colors: c,
            title: 'Recently Played',
            trailing: history.isEmpty
                ? null
                : Pressable(
                    onTap: () => _confirmClear(context, s.clearPlayedHistory),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 0, 4),
                      child: Text(
                        'Clear',
                        style: SunohType.sans(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: c.fgDim,
                        ),
                      ),
                    ),
                  ),
          ),
        ),
        if (history.isEmpty)
          SliverToBoxAdapter(child: _Empty(colors: c))
        else
          SliverList.builder(
            itemCount: history.length,
            itemBuilder: (context, i) {
              final row = DetailTrackRow(
                song: history[i],
                subtitle: labels.subtitles[i],
                duration: labels.durations[i],
                colors: c,
                accent: c.accent,
                showArt: true,
                sourceLabel: _label,
                onTap: () => s.playApiQueue(history, i, sourceLabel: _label),
              );
              return i < 9 ? Entrance(index: 1 + i, child: row) : row;
            },
          ),
      ],
    );
  }

  // Takes the clear itself rather than the AppState, which this used to take
  // as `dynamic` and so call unchecked.
  static Future<void> _confirmClear(
    BuildContext context,
    VoidCallback clear,
  ) async {
    final confirmed = await showConfirmSheet(
      context,
      title: 'Clear history?',
      message:
          'This removes everything from Recently Played. Liked songs are not '
          'affected.',
      confirmLabel: 'Clear',
    );
    if (confirmed) clear();
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.colors});
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 40, 16, 40),
      child: Column(
        children: [
          Text(
            'Nothing here yet.',
            style: SunohType.heading(fontSize: 18, color: c.fgDim),
          ),
          const SizedBox(height: 8),
          Text(
            'Songs you play will show up here so you can jump back in.',
            textAlign: TextAlign.center,
            style: SunohType.sans(fontSize: 13, color: c.fgMute),
          ),
        ],
      ),
    );
  }
}
