// The databases the lyrics lookup can ask, in the order it asks them.
//
// Ported from BitChord (https://github.com/kushagrasinghx/BitChord), GPL-3.0.

/// Declaration order is the priority order: Apple, then Musixmatch, then
/// LyricsPlus, then LRCLIB, with SimpMusic behind them.
///
/// This order is authoritative: the first source to answer wins, whether or
/// not something further down would have answered with word timings. That is
/// deliberate, and it is the reason [fetchLyrics] takes
/// `prioritiseWordSync` — turning that on lets a word-synced source further
/// down outrank a line-synced one above it.
///
/// It is off because the ranking already accounts for timing. Apple leads
/// precisely because it is per-syllable; Musixmatch outranks LyricsPlus
/// despite having only lines, because LyricsPlus runs on mirrors that are
/// mostly down and a source that usually fails is worth less than one that
/// usually answers. Letting word timing jump the queue would undo that
/// judgement every time a mirror happened to be up.
enum LyricsSource {
  /// Apple Music's TTML, per-syllable, keyless and keyed on title + artist +
  /// duration. Nothing to scrape and nothing to log in to, and the timing is
  /// the finest of anything here — which is why Apple leads.
  betterLyrics('BetterLyrics', wordSynced: true),

  /// The same Apple TTML, reached through a different host, so one of the two
  /// having a bad day doesn't cost the timing.
  paxSenix('PaxSenix', wordSynced: true),

  /// Whole lines, from the biggest lyrics database there is. Needs a signing
  /// key in `env.json`; without one it is skipped.
  musixmatch('Musixmatch', wordSynced: false),

  /// Apple's own syllable splits by way of the YouLy+ backend. Would rank
  /// higher on timing alone, but it runs on volunteer mirrors and most of
  /// them are rate-limited, out of credit or gone at any given moment.
  lyricsPlus('LyricsPlus', wordSynced: true),

  /// Whole lines only, and always up. sunoh's original and only source until
  /// this list existed.
  lrcLib('LRCLIB', wordSynced: false),

  /// Matched on the YouTube video id, so it alone can never return a
  /// different edit of the song. Last because it is geoblocked outright in
  /// some regions — including this one — and a source that answers 403 is
  /// worth having only behind the ones that answer.
  simpMusic('SimpMusic', wordSynced: true);

  const LyricsSource(this.label, {required this.wordSynced});

  /// Shown in the UI next to the lyrics, so it is clear where they came from
  /// and who to blame for a bad match.
  final String label;

  /// Whether it can return per-word timings, or only whole lines.
  final bool wordSynced;
}
