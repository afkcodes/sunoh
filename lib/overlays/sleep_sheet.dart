// Sleep timer picker. Two modes: a duration (15/30/45/60 min) that ticks
// down on AppState, or "end of current track" which arms a flag the
// `currentSongStream` listener watches. Both fade-and-pause on fire.
//
// Visually patterned on the cast picker sheet:
//   - moonSleep medallion (52×52 SizedBox with optional accent halo when
//     armed) + eyebrow + heading
//   - prominent armed card (matches the cast "Now playing on …" card)
//   - squircle option rows with accent-tinted glyph medallion + label +
//     optional check

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../providers/app_state_provider.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';

Future<void> showSleepSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useRootNavigator: true,
    builder: (_) => const _SleepSheet(),
  );
}

class _SleepSheet extends ConsumerWidget {
  const _SleepSheet();

  static const _options = <_SleepOption>[
    _SleepOption.duration(label: '15 minutes', minutes: 15),
    _SleepOption.duration(label: '30 minutes', minutes: 30),
    _SleepOption.duration(label: '45 minutes', minutes: 45),
    _SleepOption.duration(label: '1 hour', minutes: 60),
    _SleepOption.endOfTrack(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final accent = s.resolvedAccent;
    final topInset = MediaQuery.of(context).padding.bottom;

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
            // Drag handle.
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header — same medallion-+-eyebrow-+-heading rhythm as the
            // cast picker / track menu sheets.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Row(
                children: [
                  _SleepMedallion(accent: accent, armed: s.sleepArmed),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        eyebrow(
                            s.sleepArmed ? 'SLEEP IN' : 'SLEEP TIMER',
                            c.fgMute,
                            size: 9,
                            letterSpacing: 1.6),
                        const SizedBox(height: 4),
                        Text(
                          s.sleepArmed
                              ? (s.sleepAtTrackEnd
                                  ? 'When this track ends'
                                  : _fmtHeading(s.sleepRemaining))
                              : 'Pick a duration',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SunohType.heading(
                              fontSize: 18,
                              color: c.fg,
                              letterSpacing: -0.3),
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
              margin: const EdgeInsets.symmetric(horizontal: 12),
            ),
            // Armed card (only when active).
            if (s.sleepArmed)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
                child: _ArmedCard(
                  state: s,
                  accent: accent,
                  colors: c,
                  onCancel: () {
                    s.cancelSleepTimer();
                    Navigator.of(context).pop();
                  },
                ),
              ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < _options.length; i++) ...[
                  _OptionRow(
                    option: _options[i],
                    active: _isActive(_options[i], s),
                    accent: accent,
                    colors: c,
                    onTap: () {
                      if (_options[i].endOfTrack) {
                        s.armSleepTimer(endOfTrack: true);
                      } else {
                        s.armSleepTimer(
                            duration:
                                Duration(minutes: _options[i].minutes!));
                      }
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool _isActive(_SleepOption opt, AppState s) {
    if (opt.endOfTrack) return s.sleepAtTrackEnd;
    final r = s.sleepRemaining;
    if (r == null) return false;
    final mins = opt.minutes!;
    return mins * 60 >= r.inSeconds && (mins - 1) * 60 < r.inSeconds;
  }

  static String _fmtHeading(Duration? d) {
    if (d == null) return '';
    final m = d.inMinutes;
    final secs = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
}

/// Accent-tinted moonSleep medallion. Mirrors the cast medallion's static
/// halo treatment when armed.
class _SleepMedallion extends StatelessWidget {
  const _SleepMedallion({required this.accent, required this.armed});
  final Color accent;
  final bool armed;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (armed)
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: accent.withValues(alpha: 0.35), width: 1),
              ),
            ),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.22),
              shape: BoxShape.circle,
            ),
            child: Icon(
                armed
                    ? SolarIconsBold.moonSleep
                    : SolarIconsOutline.moonSleep,
                color: accent,
                size: 20),
          ),
        ],
      ),
    );
  }
}

/// Armed-state card — accent-tinted squircle, eyebrow + big remaining
/// time, with a "Cancel" pill on the right. Visually matches the cast
/// picker's "Now playing on …" card.
class _ArmedCard extends StatelessWidget {
  const _ArmedCard({
    required this.state,
    required this.accent,
    required this.colors,
    required this.onCancel,
  });
  final AppState state;
  final Color accent;
  final SunohColors colors;
  final VoidCallback onCancel;
  @override
  Widget build(BuildContext context) {
    final c = colors;
    final atTrackEnd = state.sleepAtTrackEnd;
    final remaining = state.sleepRemaining;
    final eyebrowText = atTrackEnd ? 'END OF TRACK' : 'TIME REMAINING';
    final mainText = atTrackEnd
        ? 'Playback fades out when this track ends'
        : (remaining == null
            ? ''
            : _fmt(remaining));
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: squircleDecoration(
        radius: 14,
        color:
            Color.alphaBlend(accent.withValues(alpha: 0.10), c.surface),
        borderColor: accent.withValues(alpha: 0.35),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.20),
              shape: BoxShape.circle,
            ),
            child: Icon(SolarIconsBold.moonSleep,
                color: accent, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                eyebrow(eyebrowText, accent.withValues(alpha: 0.85),
                    size: 9, letterSpacing: 1.4, maxLines: 1),
                const SizedBox(height: 3),
                Text(mainText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: atTrackEnd
                        ? SunohType.sans(
                            fontSize: 13, color: c.fg, height: 1.3)
                        : SunohType.heading(
                            fontSize: 22,
                            color: c.fg,
                            letterSpacing: -0.4)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onCancel,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: squircleDecoration(
                radius: 12,
                color: c.surface,
                borderColor: c.line,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(SolarIconsOutline.closeCircle,
                      size: 14, color: c.fgDim),
                  const SizedBox(width: 6),
                  Text('Cancel',
                      style: SunohType.sans(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: c.fg)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

/// Flat option row — matches the track menu sheet's `_MenuRow` pattern:
/// `InkWell + Padding(22, 14)`, a small leading icon, label (active rows
/// tint accent), optional subtitle, and a check on the right when active.
/// No per-row background or border — hairline dividers in the parent
/// separate adjacent rows.
class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.option,
    required this.active,
    required this.accent,
    required this.colors,
    required this.onTap,
  });
  final _SleepOption option;
  final bool active;
  final Color accent;
  final SunohColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        child: Row(
          children: [
            Icon(
                option.endOfTrack
                    ? SolarIconsOutline.musicNote
                    : SolarIconsOutline.clockCircle,
                size: 18,
                color: active ? accent : c.fgDim),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(option.label,
                      style: SunohType.sans(
                          fontSize: 14,
                          fontWeight:
                              active ? FontWeight.w600 : FontWeight.w400,
                          color: active ? accent : c.fg)),
                  if (option.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(option.subtitle!,
                        style: SunohType.sans(
                            fontSize: 11.5, color: c.fgMute)),
                  ],
                ],
              ),
            ),
            if (active)
              Icon(SolarIconsBold.checkCircle, size: 18, color: accent),
          ],
        ),
      ),
    );
  }
}

class _SleepOption {
  const _SleepOption.duration({
    required this.label,
    required int this.minutes,
  })  : endOfTrack = false,
        subtitle = null;
  const _SleepOption.endOfTrack()
      : label = 'End of current track',
        subtitle = 'Pauses the moment this song finishes',
        minutes = null,
        endOfTrack = true;
  final String label;
  final String? subtitle;
  final int? minutes;
  final bool endOfTrack;
}
