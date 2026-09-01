// The shape every bottom sheet in the app shares.
//
// Sheets were being built one at a time, and had drifted: each re-declared its
// own radius, padding and handle, and each hardcoded `Color(0xFF15151A)` for
// the background. That colour is a design-system violation twice over — a raw
// value outside tokens.dart, and a dark one, so every sheet stayed dark in
// light mode. `bgSoft` is the token for exactly this surface and it is what
// this uses.
//
// A sheet rather than a dialog wherever there is a choice to make. A dialog
// interrupts and sits under the thumb's reach at the top of a tall phone; a
// sheet arrives from the edge the thumb is already near, can be dismissed by
// pushing it back where it came from, and can grow to fit its content without
// becoming a scrolling box floating in the middle of the screen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_state_provider.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';

/// Present [builder] as a sheet with the app's chrome.
///
/// [dismissible] false is for a sheet mid-operation — a download in flight has
/// nothing useful to do with a stray backdrop tap.
Future<T?> showSunohSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool dismissible = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    isDismissible: dismissible,
    enableDrag: dismissible,
    // The root navigator, not the branch one. A sheet pushed onto the shell's
    // inner navigator is painted *under* the mini player and bottom nav, which
    // are drawn over every page — so its buttons sit behind the player, which
    // is exactly where they cannot be tapped.
    useRootNavigator: true,
    builder: builder,
  );
}

/// The sheet shell: handle, optional header, body, optional actions.
class SunohSheet extends ConsumerWidget {
  const SunohSheet({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.icon,
    this.trailing,
    this.actions,
  });

  final Widget child;
  final String? title;
  final String? subtitle;

  /// Shown in an accent medallion beside the title. A sheet that names a
  /// thing is easier to recognise at a glance than one that only describes it.
  final IconData? icon;

  /// Optional control on the header's right — a close affordance, usually.
  final Widget? trailing;

  /// Buttons along the bottom. Laid out by [SheetActions].
  final Widget? actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final accent = s.resolvedAccent;
    final media = MediaQuery.of(context);

    return Padding(
      // Lifts above the keyboard when a sheet contains a field.
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          constraints: BoxConstraints(maxHeight: media.size.height * 0.88),
          decoration: squircleDecoration(
            radius: 22,
            color: c.bgSoft,
            borderColor: c.line,
          ),
          padding: const EdgeInsets.fromLTRB(0, 10, 0, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Handle(colors: c),
              if (title != null)
                _Header(
                  title: title!,
                  subtitle: subtitle,
                  icon: icon,
                  trailing: trailing,
                  colors: c,
                  accent: accent,
                ),
              // The body scrolls and the header and actions do not, so a long
              // changelog cannot push the buttons off the bottom.
              Flexible(child: SingleChildScrollView(child: child)),
              if (actions != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                  child: actions,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Handle extends StatelessWidget {
  const _Handle({required this.colors});
  final SunohColors colors;

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 34,
      height: 4,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colors.line,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.trailing,
    required this.colors,
    required this.accent,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final SunohColors colors;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 12, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 20, color: accent),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: SunohType.heading(
                    fontSize: 18,
                    color: c.fg,
                    letterSpacing: -0.3,
                  ),
                ),
                if ((subtitle ?? '').isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: SunohType.sans(
                      fontSize: 12.5,
                      color: c.fgMute,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// One or two buttons along the bottom of a sheet.
///
/// The affirmative sits on the right, where a thumb travelling up the screen
/// reaches it last — which is the correct order for something that commits.
class SheetActions extends StatelessWidget {
  const SheetActions({super.key, required this.primary, this.secondary});

  final Widget primary;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    if (secondary == null) return primary;
    return Row(
      children: [
        Expanded(child: secondary!),
        const SizedBox(width: 10),
        Expanded(child: primary),
      ],
    );
  }
}

/// A sheet button. Filled reads as the action, outlined as the way out.
class SheetButton extends ConsumerWidget {
  const SheetButton({
    super.key,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final enabled = onTap != null;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: squircleDecoration(
            radius: 999,
            color: filled ? s.resolvedAccent : Colors.transparent,
            borderColor: filled ? null : c.line,
          ),
          child: Text(
            label,
            style: SunohType.sans(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: filled ? c.onAccent : c.fg,
            ),
          ),
        ),
      ),
    );
  }
}
