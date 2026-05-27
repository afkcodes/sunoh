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
//     a "Disconnect" affordance.

import 'package:flutter/material.dart';
import 'package:flutter_chrome_cast/entities.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../api/dto.dart';
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
    final accent = s.resolvedAccent;
    final connected = s.isCasting;
    return IconBtn(
      icon: connected
          ? SolarIconsBold.screencast
          : SolarIconsOutline.screencast,
      color: connected ? accent : (widget.color ?? c.fgDim),
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
    final selected = await showModalBottomSheet<GoogleCastDevice>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => const _DevicePickerSheet(),
    );
    if (selected != null) {
      // ignore: avoid_print
      print('[cast] picker returned device, connecting…');
      final ok = await CastService.instance.connect(selected);
      // ignore: avoid_print
      print('[cast] connect result=$ok');
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
    final accent = s.resolvedAccent;
    final topInset = MediaQuery.of(context).padding.bottom;
    final maxH = MediaQuery.of(context).size.height * 0.62;

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        constraints: BoxConstraints(maxHeight: maxH),
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
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header — same medallion-+-stacked-titles rhythm as the
            // hero menu / track menu sheets. Subtitle eyebrow uses the
            // mono caps treatment the rest of the app uses for status.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Row(
                children: [
                  _CastMedallion(
                    accent: accent,
                    active: s.isCasting,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        eyebrow(
                            s.isCasting ? 'CASTING TO' : 'CAST AUDIO',
                            c.fgMute,
                            size: 9,
                            letterSpacing: 1.6),
                        const SizedBox(height: 4),
                        Text(
                          s.isCasting
                              ? (s.castDeviceName ?? 'Connected')
                              : 'Pick a nearby speaker',
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
            Flexible(
              child: s.isCasting
                  ? _ConnectedView(
                      deviceName: s.castDeviceName,
                      song: s.currentApiSong,
                      accent: accent,
                      colors: c)
                  : const _DiscoveryList(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Accent-tinted circular medallion with the cast glyph. When a session
/// is live a thin static halo rings the medallion to signal "connected"
/// without animating — the previous outward-pulse rings expanded the
/// `Stack`'s footprint every frame, which made the surrounding header
/// row re-layout and the title appear to breathe.
class _CastMedallion extends StatelessWidget {
  const _CastMedallion({required this.accent, required this.active});
  final Color accent;
  final bool active;

  @override
  Widget build(BuildContext context) {
    // Fixed-size box so the medallion never changes the row's geometry.
    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (active)
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
                active
                    ? SolarIconsBold.screencast
                    : SolarIconsOutline.screencast,
                color: accent,
                size: 20),
          ),
        ],
      ),
    );
  }
}

class _DiscoveryList extends ConsumerWidget {
  const _DiscoveryList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final accent = s.resolvedAccent;
    return StreamBuilder<List<GoogleCastDevice>>(
      stream: CastService.instance.devicesStream,
      initialData: const [],
      builder: (context, snap) {
        final devices = snap.data ?? const <GoogleCastDevice>[];
        if (devices.isEmpty) {
          return _ScanningState(accent: accent, colors: c);
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          itemCount: devices.length,
          separatorBuilder: (_, _) => const SizedBox(height: 6),
          itemBuilder: (context, i) =>
              _DeviceRow(device: devices[i], accent: accent, colors: c),
        );
      },
    );
  }
}

/// "Looking for devices…" state — pulses to communicate active scan +
/// gives the user something to do while waiting.
class _ScanningState extends StatefulWidget {
  const _ScanningState({required this.accent, required this.colors});
  final Color accent;
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
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _t,
            builder: (_, _) {
              return SizedBox(
                width: 56,
                height: 18,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(3, (i) {
                    final offset = (i * 0.2);
                    final phase = ((_t.value + offset) % 1.0);
                    final scale = 0.6 + 0.4 * (1 - (phase - 0.5).abs() * 2);
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Container(
                        width: 8 * scale,
                        height: 8 * scale,
                        decoration: BoxDecoration(
                          color: widget.accent.withValues(alpha: 0.85),
                          shape: BoxShape.circle,
                        ),
                      ),
                    );
                  }),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          Text('Looking for devices',
              style: SunohType.heading(
                  fontSize: 16, color: c.fg, letterSpacing: -0.2)),
          const SizedBox(height: 6),
          Text(
              'Make sure your speaker is powered on and the phone is on the same Wi-Fi network.',
              textAlign: TextAlign.center,
              style: SunohType.sans(
                  fontSize: 12, color: c.fgMute, height: 1.4)),
        ],
      ),
    );
  }
}

/// Single device row — squircle pill, accent-tinted icon medallion,
/// device name + model. Tap pops the parent picker with this device.
class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.device,
    required this.accent,
    required this.colors,
  });
  final GoogleCastDevice device;
  final Color accent;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final model = device.modelName ?? '';
    final isSpeaker = _isSpeaker(model);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        // ignore: avoid_print
        print('[cast] picker tap → ${device.friendlyName}');
        Navigator.of(context).pop(device);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: squircleDecoration(
          radius: 14,
          color: c.surface,
          borderColor: c.line,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(
                  isSpeaker
                      ? SolarIconsBold.musicLibrary
                      : SolarIconsBold.screencast,
                  color: accent,
                  size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(device.friendlyName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SunohType.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: c.fg,
                          letterSpacing: -0.1)),
                  if (model.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(model,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SunohType.sans(
                            fontSize: 11.5,
                            color: c.fgMute,
                            letterSpacing: 0)),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Icon(SolarIconsOutline.altArrowRight,
                  size: 14, color: c.fgMute),
            ),
          ],
        ),
      ),
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
    required this.accent,
    required this.colors,
  });
  final String? deviceName;
  final FeedItem? song;
  final Color accent;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (song != null)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: squircleDecoration(
                radius: 14,
                color: Color.alphaBlend(
                    accent.withValues(alpha: 0.10), c.surface),
                borderColor: accent.withValues(alpha: 0.35),
              ),
              child: Row(
                children: [
                  SunohArt(
                      id: song!.id,
                      imageUrl: song!.artwork,
                      size: 44,
                      radius: 8),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        eyebrow('NOW PLAYING ON ${(deviceName ?? '').toUpperCase()}',
                            accent.withValues(alpha: 0.85),
                            size: 9,
                            letterSpacing: 1.4,
                            maxLines: 1),
                        const SizedBox(height: 3),
                        Text(song!.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SunohType.sans(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: c.fg,
                                letterSpacing: -0.1)),
                        if ((song!.displaySubtitle ?? '').isNotEmpty) ...[
                          const SizedBox(height: 1),
                          Text(song!.displaySubtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: SunohType.sans(
                                  fontSize: 12, color: c.fgMute)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  eyebrow(
                      'CONNECTED TO ${(deviceName ?? '').toUpperCase()}',
                      c.fgMute,
                      size: 9,
                      letterSpacing: 1.4),
                  const SizedBox(height: 6),
                  Text(
                      'Play something from sunoh. and it’ll come out of your speaker.',
                      style: SunohType.sans(
                          fontSize: 13, color: c.fgMute, height: 1.4)),
                ],
              ),
            ),
          const SizedBox(height: 14),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () async {
              Navigator.of(context).pop();
              await CastService.instance.disconnect();
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: squircleDecoration(
                radius: 14,
                color: c.surface,
                borderColor: c.line,
              ),
              child: Row(
                children: [
                  Icon(SolarIconsOutline.linkBroken,
                      size: 16, color: c.fgDim),
                  const SizedBox(width: 10),
                  Text('Stop casting',
                      style: SunohType.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: c.fg)),
                  const Spacer(),
                  if (deviceName != null)
                    Text(deviceName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SunohType.sans(
                            fontSize: 12, color: c.fgMute)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

