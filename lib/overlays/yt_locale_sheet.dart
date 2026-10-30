// Region / interface-language pickers for the YouTube Music source.
//
// A single sheet used for both lists — they're the same shape (a code to
// label map, one current selection, plus an Auto entry that clears the
// override rather than setting a value). Rows rather than chips: each option
// carries its code on the right, and Auto carries what it resolves to, which
// a chip has nowhere to put.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/yt_locale.dart';
import '../providers/app_state_provider.dart';
import '../providers/ytmusic_provider.dart';
import '../theme/tokens.dart';
import 'sheet.dart';
import 'sheet_row.dart';

/// Pick the YouTube region (`gl`). This is the one that matters — it
/// decides which charts and home rows come back.
Future<void> showYtRegionSheet(BuildContext context) => _show(
  context,
  title: 'YouTube region',
  blurb:
      'Shifts the editorial rows YouTube returns. Charts and Top '
      'artists ignore this and follow your connection instead, so '
      'those stay local wherever you set this.',
  options: kYtRegions,
  selectedOf: (s) => s.ytCountryOverride,
  autoLabelOf: (locale) => kYtRegions[locale.country] ?? locale.country,
  onPick: (s, code) => s.setYtCountry(code),
);

/// Pick the YouTube interface language (`hl`). Affects the wording of
/// section headings YouTube sends, not which music is returned.
Future<void> showYtLanguageSheet(BuildContext context) => _show(
  context,
  title: 'YouTube language',
  blurb:
      'The language YouTube labels its sections in. It does not '
      'filter which music you get — use Music languages for that.',
  options: kYtLanguages,
  selectedOf: (s) => s.ytLanguageOverride,
  autoLabelOf: (locale) => kYtLanguages[locale.language] ?? locale.language,
  onPick: (s, code) => s.setYtLanguage(code),
);

Future<void> _show(
  BuildContext context, {
  required String title,
  required String blurb,
  required Map<String, String> options,
  required String Function(dynamic s) selectedOf,
  required String Function(YtLocale locale) autoLabelOf,
  required Future<void> Function(dynamic s, String code) onPick,
}) {
  return showSunohSheet<void>(
    context,
    builder: (_) => _YtLocaleSheet(
      title: title,
      blurb: blurb,
      options: options,
      selectedOf: selectedOf,
      autoLabelOf: autoLabelOf,
      onPick: onPick,
    ),
  );
}

class _YtLocaleSheet extends ConsumerWidget {
  const _YtLocaleSheet({
    required this.title,
    required this.blurb,
    required this.options,
    required this.selectedOf,
    required this.autoLabelOf,
    required this.onPick,
  });

  final String title;
  final String blurb;
  final Map<String, String> options;
  final String Function(dynamic s) selectedOf;
  final String Function(YtLocale locale) autoLabelOf;
  final Future<void> Function(dynamic s, String code) onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final locale = ref.watch(ytLocaleProvider);
    final selected = selectedOf(s);

    Future<void> pick(String code) async {
      await onPick(s, code);
      if (context.mounted) Navigator.of(context).pop();
    }

    // Eighteen-odd entries apiece: short enough to build in one go inside
    // the sheet's own scroll view rather than as a lazy list.
    return SunohSheet(
      title: title,
      subtitle: blurb,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SheetRow(
            label: 'Auto',
            // Show what auto currently resolves to, so the choice isn't a
            // guess.
            trailing: _Code(autoLabelOf(locale), colors: c),
            selected: selected.isEmpty,
            colors: c,
            onTap: () => pick(''),
          ),
          for (final entry in options.entries)
            SheetRow(
              label: entry.value,
              trailing: _Code(entry.key.toUpperCase(), colors: c),
              selected: selected == entry.key,
              colors: c,
              onTap: () => pick(entry.key),
            ),
        ],
      ),
    );
  }
}

class _Code extends StatelessWidget {
  const _Code(this.text, {required this.colors});
  final String text;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: SunohType.mono(fontSize: 12.5, color: colors.fgMute));
}
