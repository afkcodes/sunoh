// Region / interface-language pickers for the YouTube Music source.
//
// A single sheet used for both lists — they're the same shape (a code to
// label map, one current selection, plus an Auto entry that clears the
// override rather than setting a value).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/yt_locale.dart';
import '../providers/app_state_provider.dart';
import '../providers/ytmusic_provider.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';

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
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
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
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.78,
        ),
        decoration: squircleDecoration(
          radius: 20,
          color: c.bgSoft,
          borderColor: c.line,
        ),
        padding: EdgeInsets.fromLTRB(0, 10, 0, 8 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 34,
                height: 4,
                decoration: BoxDecoration(
                  color: c.line,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
              child: Text(
                title,
                style: SunohType.heading(
                  fontSize: 20,
                  color: c.fg,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                blurb,
                style: SunohType.sans(
                  fontSize: 12,
                  color: c.fgMute,
                  height: 1.35,
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 8),
                children: [
                  _Option(
                    label: 'Auto',
                    // Show what auto currently resolves to, so the choice
                    // isn't a guess.
                    trailing: autoLabelOf(locale),
                    selected: selected.isEmpty,
                    colors: c,
                    accent: s.resolvedAccent,
                    onTap: () async {
                      await onPick(s, '');
                      if (context.mounted) Navigator.of(context).pop();
                    },
                  ),
                  for (final entry in options.entries)
                    _Option(
                      label: entry.value,
                      trailing: entry.key.toUpperCase(),
                      selected: selected == entry.key,
                      colors: c,
                      accent: s.resolvedAccent,
                      onTap: () async {
                        await onPick(s, entry.key);
                        if (context.mounted) Navigator.of(context).pop();
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.label,
    required this.trailing,
    required this.selected,
    required this.colors,
    required this.accent,
    required this.onTap,
  });
  final String label;
  final String trailing;
  final bool selected;
  final SunohColors colors;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: SunohType.sans(
                  fontSize: 14.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? accent : c.fg,
                ),
              ),
            ),
            Text(
              trailing,
              style: SunohType.mono(fontSize: 11, color: c.fgMute),
            ),
            const SizedBox(width: 10),
            Opacity(
              opacity: selected ? 1 : 0,
              child: Icon(Icons.check_rounded, size: 17, color: accent),
            ),
          ],
        ),
      ),
    );
  }
}
