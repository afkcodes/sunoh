// Settings → Music Languages picker. Multi-select bottom sheet matching
// the RN app's UX: the `{name, value}` list from `/music/languages`, each
// toggle-able. Selection is persisted via AppState.
//
// A wrap of chips rather than a column of rows with checks: it is an option
// set, every option is one short word, and a dozen of them fit on one screen
// as chips where they needed a scrolling list as rows. Selection reads the
// way it does on every other chip in the app — the chosen ones invert to ink.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_state_provider.dart';
import '../providers/languages_provider.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';
import 'sheet.dart';

Future<void> showLanguageSheet(BuildContext context) =>
    showSunohSheet<void>(context, builder: (_) => const _LanguageSheet());

class _LanguageSheet extends ConsumerWidget {
  const _LanguageSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final async = ref.watch(languagesProvider);

    return SunohSheet(
      title: 'Music languages',
      subtitle:
          'Pick what shows up on Home and feeds back into radios + '
          'recommendations.',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: async.when(
          loading: () => Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: c.fgMute,
                ),
              ),
            ),
          ),
          error: (e, _) =>
              _Note(text: 'Couldn’t load languages.\n$e', colors: c),
          data: (langs) {
            if (langs.isEmpty) {
              return _Note(text: 'No languages available.', colors: c);
            }
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final lang in langs)
                  SunohChip(
                    label: lang.name,
                    selected: s.selectedLanguages.contains(lang.value),
                    colors: c,
                    onTap: () => s.toggleLanguage(lang.value),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text, required this.colors});
  final String text;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Text(
      text,
      style: SunohType.sans(fontSize: 13, color: colors.fgDim, height: 1.4),
    ),
  );
}
