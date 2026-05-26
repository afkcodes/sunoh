// LRC parser — accepts the standard `[mm:ss.xx]line` format LRCLIB returns
// and emits `LyricLine`s the existing LyricsScreen already consumes.
//
// Supports:
//   * `[mm:ss]`, `[mm:ss.xx]`, `[mm:ss.xxx]` timestamps
//   * Multiple timestamps on one line (a line shared across several beats)
//   * ID-tag lines like `[ti:Title]` / `[ar:Artist]` — skipped silently
//   * Blank / whitespace-only lines (preserved as visual gaps, matching the
//     in-app dummy data convention)
//
// Position tick in AppState is in seconds (`positionTick`), so timestamps
// are floored to seconds. Sub-second precision is lost, which is fine for
// karaoke-style line highlight — the active row still flips at the right
// beat. If we ever bump the tick to millisecond precision, switch `t` to
// store ms here without touching the screen.

import '../data/models.dart';

final RegExp _kTimestamp = RegExp(r'\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]');

List<LyricLine> parseLrc(String raw) {
  final out = <LyricLine>[];
  for (final rawLine in raw.split('\n')) {
    final line = rawLine.replaceAll('\r', '');
    final matches = _kTimestamp.allMatches(line).toList();
    if (matches.isEmpty) continue;
    // Strip every timestamp tag to get the lyric text.
    var text = line;
    for (final m in matches) {
      text = text.replaceFirst(m.group(0)!, '');
    }
    text = text.trim();
    for (final m in matches) {
      final mins = int.parse(m.group(1)!);
      final secs = int.parse(m.group(2)!);
      final t = mins * 60 + secs;
      // LRCLIB sometimes emits empty-text lines deliberately (gap markers
      // between verses). Keep them so the visual rhythm survives.
      out.add(LyricLine(t, text));
    }
  }
  out.sort((a, b) => a.t.compareTo(b.t));
  return out;
}

/// Build a synthetic [LyricLine] list from plain text (no timing info).
/// Spreads the text evenly across an estimated duration so a static
/// fallback render still looks like lyrics instead of a wall of text.
/// Active-line highlighting will be approximate — only useful when we
/// have no synced lyrics at all.
List<LyricLine> plainLyricsAsLines(String raw, {int totalSec = 180}) {
  final lines = raw
      .split('\n')
      .map((l) => l.trim())
      .toList();
  if (lines.isEmpty) return const [];
  // Drop trailing blanks but keep interior ones for verse spacing.
  while (lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }
  if (lines.isEmpty) return const [];
  final spacing = (totalSec / lines.length).clamp(2.0, 8.0);
  return [
    for (var i = 0; i < lines.length; i++)
      LyricLine((i * spacing).round(), lines[i]),
  ];
}
