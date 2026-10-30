// Tells the listener when Android will cut playback off, and where to fix it.
//
// Renders nothing at all in the normal case. This is not a settings row that
// happens to be empty sometimes — it is a diagnosis, and it only earns space on
// the screen when there is something wrong that the app cannot fix for itself.
//
// See `audio/background_policy.dart` for what is being detected and why. The
// short version: a single AppOps flag makes Android strip our foreground
// service on backgrounding, playback stops with no error anywhere, and the
// media session goes on claiming it is playing. OEM battery managers set it
// without asking, so the person affected has no idea it is on.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/background_policy.dart';
import '../providers/background_policy_provider.dart';
import '../theme/tokens.dart';
import 'ui.dart';

class BackgroundWarning extends ConsumerWidget {
  const BackgroundWarning({super.key, required this.colors});

  final SunohColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final policy = ref.watch(backgroundPolicyProvider);
    // `unknown` stays silent deliberately. A warning shown to somebody whose
    // playback works perfectly well teaches them to ignore warnings.
    if (policy != BackgroundPolicy.restricted) return const SizedBox.shrink();

    final c = colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: squircleDecoration(radius: 16, color: c.surface),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Playback will stop in the background',
              style: SunohType.sans(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: c.fg,
              ),
            ),
            const SizedBox(height: 6),
            // Names the exact switch. There is no intent that deep-links to the
            // Battery section, so the button lands on App info and the listener
            // has to find the rest themselves — which they can only do if they
            // are told what they are looking for.
            Text(
              'Android is set to restrict this app, so music stops a few '
              'seconds after you leave the app or lock the screen. Some phones '
              'turn this on by themselves.\n\n'
              'Open App info → Battery, then choose Unrestricted.',
              style: SunohType.sans(fontSize: 12, color: c.fgDim, height: 1.45),
            ),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: () =>
                  ref.read(backgroundPolicyProvider.notifier).openSettings(),
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: squircleDecoration(radius: 17, color: c.surface2),
                child: Text(
                  'Open App info',
                  style: SunohType.sans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: c.fg,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
