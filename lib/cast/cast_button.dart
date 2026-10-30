// Tappable cast icon + device picker sheet.
//
// The button itself stays mounted everywhere it's placed (mini-player,
// expanded player). Visual states:
//   * Cast SDK not available / no devices yet → outlined cast glyph,
//     accent fgDim.
//   * Devices visible but not connected → outlined cast glyph, accent.
//   * Connected → filled cast glyph, accent + thin pulse-ring.
//
// Tap behaviour:
//   * Not connected → open `_DevicePickerSheet`, start LAN discovery on
//     open + stop on close (saves battery + mDNS chatter).
//   * Connected → open the same sheet showing the connected device with
//     a "Stop casting" row.
//
// The picker is a SunohSheet: title and status in its header, devices as the
// shared sheet rows (icon, name, model), and the now-playing card in the
// surface2 a card takes on a sheet.

import 'package:flutter/material.dart';
import 'package:flutter_chrome_cast/entities.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remixicon/remixicon.dart';

import '../api/dto.dart';
import '../overlays/sheet.dart';
import '../overlays/sheet_row.dart';
import '../providers/app_state_provider.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/ui.dart';
import 'cast_service.dart';

class CastButton extends ConsumerStatefulWidget {
  const CastButton({
    super.key,
    this.size = 22,
    this.width = 40,
    this.height = 40,
    this.color,
  });
  final double size;
  final double width;
  final double height;

  /// Override the idle-state color. Defaults to `colors.fgDim`.
  final Color? color;

  @override
  ConsumerState<CastButton> createState() => _CastButtonState();
}

class _CastButtonState extends ConsumerState<CastButton> {
  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final connected = s.isCasting;
    // Hidden by preference — but never while a cast is actually running, or
    // there would be no way back off the TV except from the notification.
    if (!s.showCastButton && !connected) return const SizedBox.shrink();
    return IconBtn(
      icon: connected ? RemixIcons.cast_fill : RemixIcons.cast_line,
      color: connected ? c.accent : (widget.color ?? c.fgDim),
      size: widget.size,
      width: widget.width,
      height: widget.height,
      onTap: () => openCastPicker(context),
    );
  }
}

/// Open the device picker. Starts mDNS discovery on entry, stops on
/// exit. Idempotent — safe to call from any tap handler (CastButton,
/// CastLabel, the home header icon, etc).
Future<void> openCastPicker(BuildContext context) async {
  await CastService.instance.startDiscovery();
  if (!context.mounted) {
    await CastService.instance.stopDiscovery();
    return;
  }
  // The picker returns the user-selected device (or null on dismiss).
  // We *don't* call `connect` from inside the row's onTap because the
  // sheet's pop would fall back into this scope and trigger
  // `stopDiscovery()` in parallel with the in-flight session handshake
  // — Cast SDK then invalidates the route's provider mid-select and
  // MediaRouter silently drops the selection ("Ignoring invalid
  // provider descriptor: null" in logcat).
  //
  // Doing the connect AFTER the sheet has closed but BEFORE
  // stopDiscovery keeps the route alive long enough for the SDK to
  // establish the session.
  final selected = await showSunohSheet<GoogleCastDevice>(
    context,
    builder: (_) => const _DevicePickerSheet(),
  );
  if (selected != null) {
    debugPrint('[cast] picker returned device, connecting…');
    final ok = await CastService.instance.connect(selected);
    debugPrint('[cast] connect result=$ok');
    if (!ok && context.mounted) {
      ProviderScope.containerOf(context)
          .read(appStateProvider)
          .flashToast('Couldn’t connect to ${selected.friendlyName}');
    }
  }
  await CastService.instance.stopDiscovery();
}

class _DevicePickerSheet extends ConsumerWidget {
  const _DevicePickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    return SunohSheet(
      title: s.isCasting ? (s.castDeviceName ?? 'Connected') : 'Cast audio',
      subtitle: s.isCasting ? 'Casting now' : 'Pick a nearby speaker',
      child: s.isCasting
          ? _ConnectedView(
              deviceName: s.castDeviceName,
              song: s.currentApiSong,
              colors: c,
            )
          : const _DiscoveryList(),
    );
  }
}

class _DiscoveryList extends ConsumerWidget {
  const _DiscoveryList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(appStateProvider).colors;
    return StreamBuilder<List<GoogleCastDevice>>(
      stream: CastService.instance.devicesStream,
      initialData: const [],
      builder: (context, snap) {
        final devices = snap.data ?? const <GoogleCastDevice>[];
        if (devices.isEmpty) return _ScanningState(colors: c);
        // A handful of devices on any one network, so built in one go inside
        // the sheet's own scroll view.
        return Column(
          children: [
            for (final device in devices) _DeviceRow(device: device, colors: c),
          ],
        );
      },
    );
  }
}

/// "Looking for devices…" state — pulses to communicate active scan +
/// gives the user something to do while waiting.
class _ScanningState extends StatefulWidget {
  const _ScanningState({required this.colors});
  final SunohColors colors;

  @override
  State<_ScanningState> createState() => _ScanningStateState();
}

class _ScanningStateState extends State<_ScanningState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 56,
            height: 18,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 3; i++)
                  _ScanDot(t: _t, offset: i * 0.2, color: c.fgDim),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Looking for devices',
            style: SunohType.heading(fontSize: 16, color: c.fg),
          ),
          const SizedBox(height: 6),
          Text(
            'Make sure your speaker is powered on and the phone is on the same Wi-Fi network.',
            textAlign: TextAlign.center,
            style: SunohType.sans(fontSize: 13, color: c.fgDim, height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// One dot of the scanning pulse. Each listens to the controller itself, so a
/// frame rebuilds a dot rather than the whole state.
class _ScanDot extends AnimatedWidget {
  const _ScanDot({
    required Animation<double> t,
    required this.offset,
    required this.color,
  }) : super(listenable: t);

  final double offset;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final phase = ((listenable as Animation<double>).value + offset) % 1.0;
    final scale = 0.6 + 0.4 * (1 - (phase - 0.5).abs() * 2);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Container(
        width: 8 * scale,
        height: 8 * scale,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

/// Single device row — the sheet row with a speaker or screen glyph, the
/// device's name and its model. Tap pops the parent picker with this device.
class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.device, required this.colors});
  final GoogleCastDevice device;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final model = device.modelName ?? '';
    return SheetRow(
      icon: _isSpeaker(model)
          ? RemixIcons.speaker_2_line
          : RemixIcons.tv_2_line,
      label: device.friendlyName,
      subtitle: model,
      trailing: Icon(RemixIcons.arrow_right_s_line, size: 16, color: c.fgMute),
      colors: c,
      onTap: () {
        debugPrint('[cast] picker tap → ${device.friendlyName}');
        Navigator.of(context).pop(device);
      },
    );
  }

  static bool _isSpeaker(String model) {
    final m = model.toLowerCase();
    return m.contains('speaker') ||
        m.contains('nest mini') ||
        m.contains('home') ||
        m.contains('sonos') ||
        m.contains('audio');
  }
}

class _ConnectedView extends StatelessWidget {
  const _ConnectedView({
    required this.deviceName,
    required this.song,
    required this.colors,
  });
  final String? deviceName;
  final FeedItem? song;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final playing = song;
    final name = deviceName ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          padding: const EdgeInsets.all(12),
          decoration: squircleDecoration(
            radius: SunohRadius.card,
            color: c.surface2,
          ),
          child: playing == null
              ? Text(
                  'Play something from sunoh. and it’ll come out of your speaker.',
                  style: SunohType.sans(
                    fontSize: 13.5,
                    color: c.fgDim,
                    height: 1.4,
                  ),
                )
              : Row(
                  children: [
                    SunohArt(
                      id: playing.id,
                      imageUrl: playing.artwork,
                      size: 48,
                      radius: SunohRadius.row,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          eyebrow(
                            'Now playing on $name',
                            c.fgMute,
                            size: 10.5,
                            letterSpacing: 0.84,
                            maxLines: 1,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            playing.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SunohType.sans(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: c.accent,
                            ),
                          ),
                          if ((playing.displaySubtitle ?? '').isNotEmpty)
                            Text(
                              playing.displaySubtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: SunohType.sans(
                                fontSize: 13,
                                color: c.fgDim,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
        SheetRow(
          icon: RemixIcons.link_unlink,
          label: 'Stop casting',
          trailing: name.isEmpty
              ? null
              : Text(
                  name,
                  style: SunohType.sans(fontSize: 12.5, color: c.fgMute),
                ),
          colors: c,
          onTap: () async {
            Navigator.of(context).pop();
            await CastService.instance.disconnect();
          },
        ),
      ],
    );
  }
}
