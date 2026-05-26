// Settings → Music Languages picker. Multi-select bottom sheet matching
// the RN app's UX: list of `{name, value}` rows from `/music/languages`,
// each toggle-able. Selection is persisted via AppState.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../providers/app_state_provider.dart';
import '../providers/languages_provider.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';

Future<void> showLanguageSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useRootNavigator: true,
    builder: (_) => const _LanguageSheet(),
  );
}

class _LanguageSheet extends ConsumerWidget {
  const _LanguageSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final accent = s.resolvedAccent;
    final async = ref.watch(languagesProvider);
    final topInset = MediaQuery.of(context).padding.bottom;
    // Sheet height = 70% of screen so a long language list scrolls but
    // doesn't fill the whole screen.
    final maxH = MediaQuery.of(context).size.height * 0.7;

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
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 6, 22, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Music Languages',
                      style: SunohType.heading(
                          fontSize: 18, color: c.fg, letterSpacing: -0.2)),
                  const SizedBox(height: 4),
                  Text(
                      'Pick what shows up on Home and feeds back into radios + recommendations.',
                      style:
                          SunohType.sans(fontSize: 12, color: c.fgMute)),
                ],
              ),
            ),
            Container(
                height: 0.5,
                color: c.line,
                margin: const EdgeInsets.symmetric(horizontal: 12)),
            Flexible(
              child: async.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                      child:
                          CircularProgressIndicator(strokeWidth: 2)),
                ),
                error: (e, _) => Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
                  child: Text('Couldn’t load languages.\n$e',
                      style: SunohType.sans(
                          fontSize: 13, color: c.fgMute)),
                ),
                data: (langs) {
                  if (langs.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('No languages available.',
                          style: SunohType.sans(
                              fontSize: 13, color: c.fgMute)),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: langs.length,
                    separatorBuilder: (_, _) => Container(
                      height: 0.5,
                      color: c.line.withValues(alpha: 0.5),
                      margin:
                          const EdgeInsets.symmetric(horizontal: 22),
                    ),
                    itemBuilder: (context, i) {
                      final lang = langs[i];
                      final selected =
                          s.selectedLanguages.contains(lang.value);
                      return InkWell(
                        onTap: () => s.toggleLanguage(lang.value),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 22, vertical: 14),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(lang.name,
                                    style: SunohType.sans(
                                        fontSize: 14,
                                        fontWeight: selected
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                        color: selected ? accent : c.fg)),
                              ),
                              if (selected)
                                Icon(SolarIconsBold.checkCircle,
                                    size: 18, color: accent),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
