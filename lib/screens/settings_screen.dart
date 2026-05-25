// Settings — full-route replacement of the legacy bottom-sheet tweaks panel.
// Four sections: Playback, Appearance, Library, About. Lives inside the
// active tab branch so back returns to wherever you opened it from.
//
// Layout: bare eyebrow label + flat list of rows per section (matches the
// rest of the app's section convention — squircle cards group items, not
// rows). Vertical whitespace + density.scale carry the rhythm.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/app_state_provider.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';

/// Where "Support sunoh." money goes. Hardcoded — there's only one user
/// (the developer), so the values don't need to be configurable.
const _kUpiVpa = 'afkcodes@ybl';
const _kUpiName = 'Sunoh';
const _kBuyMeCoffeeUrl = 'https://buymeacoffee.com/afkcodes';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final scale = s.density.scale;
    final topInset = MediaQuery.of(context).padding.top;

    return ColoredBox(
      color: c.bg,
      child: ListView(
        padding: EdgeInsets.fromLTRB(0, topInset + 12, 0, 140),
        children: [
          _Header(colors: c),
          SizedBox(height: 24 * scale),
          _DonationCard(colors: c, accent: s.resolvedAccent),
          SizedBox(height: 28 * scale),

          _Section(
            label: 'PLAYBACK',
            colors: c,
            scale: scale,
            rows: [
              _RadioRow<String>(
                label: 'Stream quality',
                value: s.streamQuality,
                options: const {
                  'auto': 'Auto',
                  'high': 'High',
                  'data': 'Data saver',
                },
                onChange: s.setStreamQuality,
                colors: c,
              ),
            ],
          ),

          _Section(
            label: 'APPEARANCE',
            colors: c,
            scale: scale,
            rows: [
              _AccentRow(s: s, colors: c, scale: scale),
              _ToggleRow(
                label: 'Tint from artwork',
                value: s.tintFromArt,
                onChange: s.setTintFromArt,
                colors: c,
              ),
              if (s.tintFromArt)
                _SliderRow(
                  label: 'Tint intensity',
                  value: s.tintIntensity,
                  min: 0,
                  max: 1,
                  divisions: 20,
                  suffix: '${(s.tintIntensity * 100).round()}%',
                  onChange: s.setTintIntensity,
                  colors: c,
                ),
              _RadioRow<Density>(
                label: 'Density',
                value: s.density,
                options: const {
                  Density.compact: 'Compact',
                  Density.regular: 'Regular',
                  Density.comfy: 'Comfy',
                },
                onChange: s.setDensity,
                colors: c,
              ),
            ],
          ),

          _Section(
            label: 'LIBRARY',
            colors: c,
            scale: scale,
            rows: [
              _Link(
                label: 'Storage',
                trailing: '— MB',
                icon: SolarIconsOutline.folderWithFiles,
                colors: c,
                onTap: () =>
                    s.flashToast('Downloads not implemented yet'),
              ),
              _Link(
                label: 'Clear cache',
                icon: SolarIconsOutline.trashBinTrash,
                colors: c,
                onTap: () => s.flashToast('Coming soon'),
              ),
            ],
          ),

          _Section(
            label: 'ABOUT',
            colors: c,
            scale: scale,
            rows: [
              _Link(
                label: 'Version',
                trailing: '0.1.0',
                icon: SolarIconsOutline.infoCircle,
                colors: c,
                onTap: () {},
              ),
              _Link(
                label: 'Licenses',
                icon: SolarIconsOutline.document,
                colors: c,
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'sunoh.',
                  applicationVersion: '0.1.0',
                ),
              ),
              _Link(
                label: 'Debug logs',
                icon: SolarIconsOutline.notebookMinimalistic,
                colors: c,
                onTap: () => s.flashToast('Not implemented'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Pieces ──────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.colors});
  final SunohColors colors;
  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Row(
        children: [
          IconBtn(
            icon: SolarIconsOutline.altArrowLeft,
            color: c.fg,
            size: 22,
            onTap: () => context.pop(),
          ),
          const SizedBox(width: 6),
          Text('Settings',
              style: SunohType.heading(
                  fontSize: 22, color: c.fg, letterSpacing: -0.3)),
        ],
      ),
    );
  }
}

/// A section: eyebrow label + flat list of rows separated by vertical
/// whitespace. No card backdrop — convention across the app is "eyebrow then
/// rows", same as home/detail sections.
class _Section extends StatelessWidget {
  const _Section({
    required this.label,
    required this.rows,
    required this.colors,
    required this.scale,
  });
  final String label;
  final List<Widget> rows;
  final SunohColors colors;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    // Interleave a vertical gap between rows. 22 * scale at regular density
    // matches the airy rhythm picked in the earlier spacing pass.
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) children.add(SizedBox(height: 22 * scale));
      children.add(rows[i]);
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 34 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: 20 * scale),
            child: eyebrow(label, c.fgMute, size: 11, letterSpacing: 1.4),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _Link extends StatelessWidget {
  const _Link({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.colors,
    this.trailing,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final SunohColors colors;
  final String? trailing;
  @override
  Widget build(BuildContext context) {
    final c = colors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Icon(icon, size: 18, color: c.fgDim),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: SunohType.sans(fontSize: 14, color: c.fgDim)),
          ),
          if (trailing != null) ...[
            Text(trailing!,
                style: SunohType.sans(fontSize: 12.5, color: c.fgMute)),
            const SizedBox(width: 6),
          ],
          Icon(SolarIconsOutline.altArrowRight, size: 16, color: c.fgMute),
        ],
      ),
    );
  }
}

/// Compound row: "Accent" label + the 12-swatch grid. Lives inside the
/// Appearance card as a single logical row.
class _AccentRow extends StatelessWidget {
  const _AccentRow({
    required this.s,
    required this.colors,
    required this.scale,
  });
  final AppState s;
  final SunohColors colors;
  final double scale;
  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Accent',
            style: SunohType.sans(fontSize: 14, color: c.fgDim)),
        SizedBox(height: 14 * scale),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (final col in kAccentOptions)
              GestureDetector(
                onTap: () => s.setAccent(col),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: col,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: s.accent == col && !s.tintFromArt
                          ? c.fg
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.suffix,
    required this.onChange,
    required this.colors,
  });
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String suffix;
  final ValueChanged<double> onChange;
  final SunohColors colors;
  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: SunohType.sans(fontSize: 14, color: c.fgDim)),
            Text(suffix,
                style: SunohType.mono(
                    fontSize: 11, color: c.fgMute, letterSpacing: 0.4)),
          ],
        ),
        // Slider has built-in vertical padding; pull it tight to the label.
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: c.accent,
            inactiveTrackColor: c.surface,
            thumbColor: c.fg,
            overlayColor: c.accent.withValues(alpha: 0.12),
            trackHeight: 3,
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChange,
          ),
        ),
      ],
    );
  }
}

class _RadioRow<T> extends StatelessWidget {
  const _RadioRow({
    required this.label,
    required this.value,
    required this.options,
    required this.onChange,
    required this.colors,
  });
  final String label;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChange;
  final SunohColors colors;
  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SunohType.sans(fontSize: 14, color: c.fgDim)),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: c.line, width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final e in options.entries)
                GestureDetector(
                  onTap: () => onChange(e.key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: e.key == value ? c.fg : Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(e.value,
                        style: SunohType.sans(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color:
                                e.key == value ? c.bg : c.fgMute)),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChange,
    required this.colors,
  });
  final String label;
  final bool value;
  final ValueChanged<bool> onChange;
  final SunohColors colors;
  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: SunohType.sans(fontSize: 14, color: c.fgDim)),
        Switch(
          value: value,
          onChanged: onChange,
          activeThumbColor: c.bg,
          activeTrackColor: c.accent,
        ),
      ],
    );
  }
}

/// "Support sunoh." pinned card at the top of Settings. Primary tap fires
/// a UPI deep link; the smaller right-side affordance opens Buy Me A
/// Coffee in the system browser. Both fall back gracefully — UPI taps
/// copy the VPA to the clipboard if no UPI app is installed.
class _DonationCard extends ConsumerWidget {
  const _DonationCard({required this.colors, required this.accent});
  final SunohColors colors;
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: squircleDecoration(
          radius: 16,
          gradient: LinearGradient(
            colors: [
              accent.withValues(alpha: 0.85),
              accent.withValues(alpha: 0.32),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Heart medallion — circle on a slightly darker accent so
                // the icon contrast holds against the gradient backdrop.
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(SolarIconsBold.heart,
                      size: 18, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Support sunoh.',
                          style: SunohType.sans(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              letterSpacing: -0.1)),
                      const SizedBox(height: 3),
                      Text('Keep this little app alive',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SunohType.sans(
                              fontSize: 11.5,
                              color: Colors.white.withValues(alpha: 0.75))),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Two explicit, labeled CTAs so the user can see both options.
            // Previously BMC was a bare IconButton that looked like card
            // decoration; users reasonably didn't notice it.
            Row(
              children: [
                Expanded(
                  child: _DonationAction(
                    icon: SolarIconsBold.heartAngle,
                    label: 'Send a tip',
                    onTap: () => _payUpi(context, ref),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DonationAction(
                    icon: SolarIconsOutline.cupHot,
                    label: 'Buy me a coffee',
                    onTap: () => _openBmc(context, ref),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _payUpi(BuildContext context, WidgetRef ref) async {
    final s = ref.read(appStateProvider);
    // Build the URI manually — `Uri(scheme:, host:, queryParameters:)`
    // percent-encodes `@` in the VPA to `%40`, which several Indian UPI
    // apps refuse to parse. The raw `upi://pay?…` form is the canonical
    // deep link spec.
    final uri = Uri.parse(
        'upi://pay?pa=$_kUpiVpa&pn=${Uri.encodeComponent(_kUpiName)}&cu=INR');
    try {
      // Skip canLaunchUrl — it's unreliable for non-HTTP schemes on
      // Android even with the manifest <queries> entry, and returning
      // false from it was forcing us into the copy fallback even when a
      // UPI app WAS installed. externalNonBrowserApplication is the
      // documented mode for non-browser deep links.
      final ok = await launchUrl(
        uri,
        mode: LaunchMode.externalNonBrowserApplication,
      );
      if (!ok) {
        await Clipboard.setData(const ClipboardData(text: _kUpiVpa));
        s.flashToast('No UPI app — copied $_kUpiVpa');
      }
    } catch (_) {
      await Clipboard.setData(const ClipboardData(text: _kUpiVpa));
      s.flashToast('No UPI app — copied $_kUpiVpa');
    }
  }

  Future<void> _openBmc(BuildContext context, WidgetRef ref) async {
    final s = ref.read(appStateProvider);
    final uri = Uri.parse(_kBuyMeCoffeeUrl);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) s.flashToast('Couldn’t open browser');
    } catch (_) {
      s.flashToast('Couldn’t open browser');
    }
  }
}

/// Pill button used as the two CTAs inside [_DonationCard]. White-on-glass
/// look so both actions read as buttons against the accent-gradient card.
class _DonationAction extends StatelessWidget {
  const _DonationAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        // Squircle per design system — never raw BorderRadius on cards.
        decoration: squircleDecoration(
          radius: 12,
          color: Colors.white.withValues(alpha: 0.18),
          borderColor: Colors.white.withValues(alpha: 0.22),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: Colors.white),
            const SizedBox(width: 8),
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SunohType.sans(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
