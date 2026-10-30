// The pieces the option sheets are built from: a row, a segmented control,
// a subject header and a section label.
//
// Every sheet used to carry a private copy of the same row — _MenuRow,
// _HeroMenuRow, _QueueMenuRow, _OptionRow and more — each a few pixels off
// the next in padding, icon size and label weight, which is how they drifted
// apart. The redesign gives sheets one row (a 22 icon in fgDim, the label in
// sans 15, 52 tall on the 16 gutter), and one widget is how it stays one row.
//
// The chrome around them — the card, the grabber, the title — is SunohSheet in
// sheet.dart. These sit inside it.

import 'package:flutter/material.dart';
import 'package:remixicon/remixicon.dart';

import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/motion.dart';
import '../widgets/ui.dart';

/// One option in a sheet: optional icon, label, optional subtitle, and
/// whatever sits on the right.
///
/// A selected row carries an accent check rather than a recoloured label: the
/// label stays readable at full ink, and the check is a mark the eye can find
/// down a list without reading every line.
class SheetRow extends StatelessWidget {
  const SheetRow({
    super.key,
    required this.label,
    required this.colors,
    required this.onTap,
    this.icon,
    this.iconColor,
    this.leading,
    this.subtitle,
    this.trailing,
    this.selected = false,
    this.enabled = true,
  });

  final String label;
  final SunohColors colors;
  final VoidCallback? onTap;
  final IconData? icon;

  /// Overrides the icon's fgDim — a filled heart for a liked song, say.
  final Color? iconColor;

  /// Artwork or a tile in place of the icon. Rows that lead with art grow to
  /// the list-row height so the art has room around it.
  final Widget? leading;
  final String? subtitle;
  final Widget? trailing;
  final bool selected;

  /// Disabled rows stay visible in fgMute — "Clear queue" with nothing queued
  /// still says the action exists.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final ink = enabled ? c.fg : c.fgMute;
    return Pressable(
      scale: 0.99,
      onTap: enabled ? onTap : null,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: leading == null ? 52 : 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: 12),
              ] else if (icon != null) ...[
                Icon(
                  icon,
                  size: 22,
                  color: enabled ? (iconColor ?? c.fgDim) : c.fgMute,
                ),
                const SizedBox(width: 16),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SunohType.sans(
                        fontSize: 15,
                        fontWeight: leading == null
                            ? FontWeight.w400
                            : FontWeight.w500,
                        color: ink,
                      ),
                    ),
                    if ((subtitle ?? '').isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SunohType.sans(fontSize: 13, color: c.fgDim),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 12), trailing!],
              if (selected) ...[
                const SizedBox(width: 12),
                Icon(RemixIcons.checkbox_circle_fill, size: 18, color: c.accent),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A row of equal buttons, one of them chosen — the prototype's sleep-timer
/// control. Selection inverts to ink, the same way a [SunohChip] does, so the
/// two read as one family.
class SheetSegmented extends StatelessWidget {
  const SheetSegmented({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelect,
    required this.colors,
  });

  final List<String> labels;

  /// Index into [labels]; -1 for none.
  final int selected;
  final ValueChanged<int> onSelect;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: Pressable(
              onTap: () => onSelect(i),
              child: AnimatedContainer(
                duration: SunohMotion.press,
                curve: SunohMotion.ease,
                height: 34,
                alignment: Alignment.center,
                decoration: squircleDecoration(
                  radius: SunohRadius.tile,
                  color: i == selected ? c.fg : c.surface2,
                ),
                child: Text(
                  labels[i],
                  maxLines: 1,
                  style: SunohType.sans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: i == selected ? c.bg : c.fg,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The thing a menu sheet acts on — a song, an album, an artist — as its
/// header: list-row art beside the sheet-title type.
///
/// SunohSheet's own header has no slot for artwork, and a menu without the
/// cover is a menu the eye has to read to be sure it opened the right one.
class SheetSubject extends StatelessWidget {
  const SheetSubject({
    super.key,
    required this.id,
    required this.title,
    required this.colors,
    this.imageUrl,
    this.subtitle,
    this.round = false,
  });

  final String id;
  final String? imageUrl;
  final String title;
  final String? subtitle;
  final SunohColors colors;

  /// Artists are circles everywhere else in the app, so here too.
  final bool round;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          SunohArt(
            id: id,
            imageUrl: imageUrl,
            size: 48,
            radius: round ? 999 : SunohRadius.row,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: SunohType.heading(
                    fontSize: 20,
                    color: c.fg,
                    height: 1.15,
                  ),
                ),
                if ((subtitle ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SunohType.sans(fontSize: 12.5, color: c.fgDim),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A label over a group inside a sheet ("Sort by", a preset category): the
/// app's eyebrow, on the gutter.
class SheetLabel extends StatelessWidget {
  const SheetLabel(
    this.text, {
    super.key,
    required this.colors,
    this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 8),
  });

  final String text;
  final SunohColors colors;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: eyebrow(text, colors.fgMute, size: 10.5, letterSpacing: 0.84),
  );
}
