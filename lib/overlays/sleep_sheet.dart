// Sleep timer picker. Two modes: a duration (15/30/45/60 min) that ticks
// down on AppState, or "end of current track" which arms a flag the
// `currentSongStream` listener watches. Both fade-and-pause on fire.
//
// Laid out as the prototype's sleep control: one segmented row — Off, the
// four durations, Song — and a line under it saying what will happen. The
// line is where the live countdown lives, so the state and the control that
// set it are read together rather than in a card above a list.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_state_provider.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import 'sheet.dart';
import 'sheet_row.dart';

Future<void> showSleepSheet(BuildContext context) =>
    showSunohSheet<void>(context, builder: (_) => const _SleepSheet());

/// Segment labels, and what each arms. Index 0 is Off, the last is Song.
const List<String> _kLabels = ['Off', '15m', '30m', '45m', '1h', 'Song'];
const List<int> _kMinutes = [15, 30, 45, 60];

class _SleepSheet extends ConsumerWidget {
  const _SleepSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;

    return SunohSheet(
      title: 'Sleep timer',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SheetSegmented(
              labels: _kLabels,
              selected: _selectedIndex(s),
              colors: c,
              onSelect: (i) {
                if (i == 0) {
                  s.cancelSleepTimer();
                } else if (i == _kLabels.length - 1) {
                  s.armSleepTimer(endOfTrack: true);
                } else {
                  s.armSleepTimer(
                    duration: Duration(minutes: _kMinutes[i - 1]),
                  );
                }
                Navigator.of(context).pop();
              },
            ),
            const SizedBox(height: 10),
            // Tabular figures: the countdown ticks every second in here, and
            // proportional digits would shuffle the sentence as it does.
            Text(
              _note(s),
              style: SunohType.mono(
                fontSize: 12.5,
                color: c.fgDim,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Which segment reads as chosen. A duration only matches during the first
  /// minute after it was armed — the timer keeps what is left, not what was
  /// picked — so mid-countdown no segment is lit and the line below carries
  /// the state instead.
  static int _selectedIndex(AppState s) {
    if (!s.sleepArmed) return 0;
    if (s.sleepAtTrackEnd) return _kLabels.length - 1;
    final r = s.sleepRemaining;
    if (r == null) return -1;
    for (var i = 0; i < _kMinutes.length; i++) {
      final mins = _kMinutes[i];
      if (mins * 60 >= r.inSeconds && (mins - 1) * 60 < r.inSeconds) {
        return i + 1;
      }
    }
    return -1;
  }

  static String _note(AppState s) {
    if (s.sleepAtTrackEnd) return 'Pauses the moment this song finishes.';
    final r = s.sleepRemaining;
    if (r == null) return 'Off. Music plays until the queue ends.';
    return 'Fades out and stops in ${_fmt(r)}.';
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes;
    final secs = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
}
