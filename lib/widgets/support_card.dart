// "Support sunoh." — the tip and Ko-fi card, and what its two buttons do.
//
// Lived inside settings_screen.dart until Home grew a heart icon that opens
// the same card in a sheet. Moved here rather than copied, so the UPI handle,
// the Ko-fi URL and the clipboard fallback exist once.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remixicon/remixicon.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/app_state_provider.dart';
import '../theme/tokens.dart';
import 'ui.dart';

/// Where "Support sunoh." money goes. Hardcoded — there's only one user
/// (the developer), so the values don't need to be configurable.
const _kUpiVpa = 'afkcodes@ybl';
const _kUpiName = 'Sunoh';

/// Moved from Buy Me a Coffee → Ko-fi (lower platform fees, instant payouts,
/// no merchant-of-record middleman). Same handle on both, so the swap was
/// a one-line URL change.
const _kKofiUrl = 'https://ko-fi.com/afkcodes';

/// "Support sunoh." card — pinned at the top of Settings, and the body of
/// the sheet behind Home's heart. Primary tap fires a UPI deep link; the
/// second opens Ko-fi in the system browser. Both fall back gracefully — UPI taps
/// copy the VPA to the clipboard if no UPI app is installed.
class SupportCard extends ConsumerWidget {
  const SupportCard({super.key, required this.colors, required this.accent});
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
                  child: const Icon(
                    RemixIcons.heart_3_fill,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Support sunoh.',
                        style: SunohType.sans(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          letterSpacing: -0.1,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Keep this little app alive',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SunohType.sans(
                          fontSize: 11.5,
                          color: Colors.white.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Two explicit, labeled CTAs so the user can see both options.
            // The right-side CTA used to be a bare BMC IconButton that
            // looked like card decoration; users reasonably didn't notice
            // it. Now a labeled "Buy a coffee" pill that opens Ko-fi.
            Row(
              children: [
                Expanded(
                  child: _DonationAction(
                    icon: RemixIcons.hand_heart_fill,
                    label: 'Send a tip',
                    onTap: () => _payUpi(context, ref),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DonationAction(
                    icon: RemixIcons.cup_line,
                    label: 'Buy a coffee',
                    onTap: () => _openKofi(context, ref),
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
      'upi://pay?pa=$_kUpiVpa&pn=${Uri.encodeComponent(_kUpiName)}&cu=INR',
    );
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

  Future<void> _openKofi(BuildContext context, WidgetRef ref) async {
    final s = ref.read(appStateProvider);
    final uri = Uri.parse(_kKofiUrl);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) s.flashToast('Couldn’t open browser');
    } catch (_) {
      s.flashToast('Couldn’t open browser');
    }
  }
}

/// Pill button used as the two CTAs inside [SupportCard]. White-on-glass
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
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SunohType.sans(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
