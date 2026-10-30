// The expanded player's bottom half: the transport row and the tools row.
// Split out of expanded_player.dart to keep that file's length down; they
// share no state with it beyond the AppState they are handed.

import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:remixicon/remixicon.dart';

import '../cast/cast_button.dart';
import '../overlays/eq_sheet.dart';
import '../overlays/sleep_sheet.dart';
import '../router/router.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';
import 'player_controls.dart';

class PlayerTransport extends StatelessWidget {
  const PlayerTransport({super.key, required this.s, required this.c});
  final AppState s;
  final SunohColors c;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          PlayerToggle(
            icon: PhosphorIconsBold.shuffle,
            on: s.shuffle,
            colors: c,
            onTap: s.toggleShuffle,
          ),
          IconBtn(
            icon: PhosphorIconsFill.skipBack,
            color: c.fg,
            size: 30,
            width: 56,
            height: 56,
            onTap: s.prev,
          ),
          PlayButton(
            playing: s.isPlaying,
            ink: c.fg,
            onInk: c.bg,
            onTap: s.playPause,
          ),
          IconBtn(
            icon: PhosphorIconsFill.skipForward,
            color: c.fg,
            size: 30,
            width: 56,
            height: 56,
            onTap: s.next,
          ),
          PlayerToggle(
            icon: s.repeat == LoopMode.one
                ? PhosphorIconsBold.repeatOnce
                : PhosphorIconsBold.repeat,
            on: s.repeat != LoopMode.off,
            colors: c,
            onTap: s.cycleRepeat,
          ),
        ],
      ),
    );
  }
}

/// Output device on the left; lyrics, sleep, equaliser and queue on the
/// right.
class PlayerTools extends StatelessWidget {
  const PlayerTools({super.key, required this.s, required this.c});
  final AppState s;
  final SunohColors c;

  @override
  Widget build(BuildContext context) {
    Widget tool(IconData icon, VoidCallback onTap, {bool on = false}) =>
        IconBtn(
          icon: icon,
          color: on ? c.accent : c.fg,
          size: 20,
          onTap: onTap,
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 8, 0),
      child: Row(
        children: [
          // Hidden by preference, but never while a cast is running — it is
          // the way back to the phone.
          if (s.showCastButton || s.isCasting)
            DeviceButton(
              label: s.isCasting
                  ? (s.castDeviceName ?? 'Casting')
                  : 'This phone',
              casting: s.isCasting,
              colors: c,
              onTap: () => openCastPicker(context),
            ),
          const Spacer(),
          tool(RemixIcons.file_text_line, () => context.openLyrics()),
          tool(
            s.sleepArmed ? RemixIcons.zzz_fill : RemixIcons.zzz_line,
            () => showSleepSheet(context),
            on: s.sleepArmed,
          ),
          tool(RemixIcons.equalizer_line, () => showEqSheet(context)),
          tool(RemixIcons.play_list_2_line, () => context.openQueue()),
        ],
      ),
    );
  }
}
