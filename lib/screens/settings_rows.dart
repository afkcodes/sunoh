// The pieces Settings is built from: the page scaffold, a group, the ruled
// frame every row sits in, and the rows that go somewhere or flip something —
// link, navigation, toggle. The rows that pick a value are in
// settings_pickers.dart.
//
// Split from settings_screen.dart, which keeps what is on the page and in
// what order; these files know how a row looks.

part of 'settings_screen.dart';

/// The page: the solid bar, then the blocks scrolling under it, each arriving
/// in turn. A plain scroll view rather than a ListView — it is six blocks, and
/// a lazy list disposes the top ones on the way down and replays their
/// entrance on the way back up.
class _Page extends StatelessWidget {
  const _Page({required this.colors, required this.children});
  final SunohColors colors;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SubPageBar(title: 'Settings', colors: colors),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(top: 16, bottom: shellClearance(context)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i++)
                  FadeSlideIn(index: i, child: children[i]),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A group: an eyebrow label over its rows. Each row draws its own frame (see
/// [_RowFrame]), so a card that lives in a group — the update notice, the
/// background warning — sits in it without being boxed in as a row.
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
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 24 * scale, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: eyebrow(
              label,
              colors.fgMute,
              size: 10.5,
              letterSpacing: 0.84,
            ),
          ),
          ...rows,
        ],
      ),
    );
  }
}

/// What every settings row sits in: at least 56 tall, 9 above and below, and
/// a rule along the bottom. Settings is the one key/value list in the app, so
/// it is the one place rows are divided. A row that does something presses as
/// a whole, not just where its label is.
class _RowFrame extends StatelessWidget {
  const _RowFrame({required this.colors, required this.child, this.onTap});
  final SunohColors colors;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final frame = Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(vertical: 9),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.line)),
      ),
      child: child,
    );
    if (onTap == null) return frame;
    return Pressable(scale: 0.99, onTap: onTap, child: frame);
  }
}

/// A helper line under a row's label — what the setting does.
Widget _helper(String text, SunohColors c) => Padding(
  padding: const EdgeInsets.only(top: 2),
  child: Text(
    text,
    style: SunohType.sans(fontSize: 12.5, color: c.fgMute, height: 1.35),
  ),
);

class _Link extends StatelessWidget {
  const _Link({
    required this.label,
    required this.colors,
    this.onTap,
    this.trailing,
  });
  final String label;

  /// Optional: the Version row states a fact rather than going anywhere.
  /// It used to open a hidden analytics toggle, which no longer exists.
  final VoidCallback? onTap;
  final SunohColors colors;
  final String? trailing;
  @override
  Widget build(BuildContext context) {
    final c = colors;
    return _RowFrame(
      colors: c,
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: SunohType.sans(fontSize: 15, color: c.fg),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            Text(
              trailing!,
              style: SunohType.sans(fontSize: 13, color: c.fgDim),
            ),
          ],
          // No chevron on a row that goes nowhere.
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(RemixIcons.arrow_right_s_line, size: 16, color: c.fgMute),
          ],
        ],
      ),
    );
  }
}

/// Tap-row with a trailing value and a chevron — used for settings that open
/// a sub-sheet instead of toggling inline. The value sits on the right, where
/// a key/value list is read.
class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.label,
    required this.summary,
    required this.onTap,
    required this.colors,
  });
  final String label;
  final String summary;
  final VoidCallback onTap;
  final SunohColors colors;
  @override
  Widget build(BuildContext context) {
    final c = colors;
    return _RowFrame(
      colors: c,
      onTap: onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: SunohType.sans(fontSize: 15, color: c.fg)),
          // A floor under the gap. The summary is Flexible, so without this it
          // shrinks until it touches the label rather than ellipsising, and a
          // long value renders as one run-on string.
          const SizedBox(width: 16),
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: SunohType.sans(fontSize: 13, color: c.fgDim),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(RemixIcons.arrow_right_s_line, size: 16, color: c.fgMute),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChange,
    required this.colors,
    this.summary,
  });
  final String label;
  final String? summary;
  final bool value;
  final ValueChanged<bool> onChange;
  final SunohColors colors;
  @override
  Widget build(BuildContext context) {
    final c = colors;
    // The whole row flips the switch, as the prototype's rows do — a 52-wide
    // switch is a small target at the end of a long line of helper text.
    return _RowFrame(
      colors: c,
      onTap: () => onChange(!value),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: SunohType.sans(fontSize: 15, color: c.fg)),
                if (summary != null) _helper(summary!, c),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Filled both ways: Material's off state is an outlined track, the
          // one hairline control left on the screen.
          Switch(
            value: value,
            onChanged: onChange,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            activeThumbColor: c.onAccent,
            activeTrackColor: c.accent,
            inactiveThumbColor: c.fgDim,
            inactiveTrackColor: c.surface2,
            trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
          ),
        ],
      ),
    );
  }
}
