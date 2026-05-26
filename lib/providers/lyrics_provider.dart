// Lyrics state — fetched from LRCLIB, parsed into LyricLine[].
//
// Family key is intentionally compact (track + artist + duration) so two
// queues pointing at the same song share one fetch. Result auto-caches for
// 24 h because lyrics don't change — and LRCLIB asks integrators to be
// gentle with the catalog.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/lrclib.dart';
import '../audio/lrc_parser.dart';
import '../data/models.dart';

/// Compact, hash-friendly identity for a lyrics fetch. Two queries are
/// equal when their (lower-cased) track + artist + duration agree.
class LyricsQuery {
  const LyricsQuery({
    required this.track,
    required this.artist,
    this.album,
    this.durationSec,
  });
  final String track;
  final String artist;
  final String? album;
  final int? durationSec;

  @override
  bool operator ==(Object other) =>
      other is LyricsQuery &&
      other.track.toLowerCase() == track.toLowerCase() &&
      other.artist.toLowerCase() == artist.toLowerCase() &&
      other.album?.toLowerCase() == album?.toLowerCase() &&
      other.durationSec == durationSec;

  @override
  int get hashCode => Object.hash(
        track.toLowerCase(),
        artist.toLowerCase(),
        album?.toLowerCase(),
        durationSec,
      );
}

class LyricsResult {
  const LyricsResult({
    required this.lines,
    required this.synced,
    required this.instrumental,
    required this.found,
  });
  final List<LyricLine> lines;

  /// True iff the lines carry real per-line timing (from LRC). False when
  /// we synthesised them from plain text — the UI uses this to decide
  /// whether to drive active-line highlighting from playback position.
  final bool synced;

  /// LRCLIB explicitly marked the song as instrumental. UI shows a
  /// dedicated "instrumental" state rather than a blank screen.
  final bool instrumental;

  /// False when the catalog had nothing for us (404 + fuzzy miss). UI
  /// renders a "no lyrics yet" hint.
  final bool found;

  static const empty = LyricsResult(
    lines: [],
    synced: false,
    instrumental: false,
    found: false,
  );
}

final _lrcLibClientProvider = Provider((_) => LrcLibClient());

final lyricsProvider =
    FutureProvider.autoDispose.family<LyricsResult, LyricsQuery>(
  (ref, query) async {
    // Keep the entry warm for a day after every consumer has unsubscribed
    // so re-opening the lyrics sheet for the same track doesn't refetch.
    final link = ref.keepAlive();
    Future.delayed(const Duration(hours: 24), link.close);

    final client = ref.read(_lrcLibClientProvider);
    final r = await client.fetch(
      trackName: query.track,
      artistName: query.artist,
      albumName: query.album,
      durationSec: query.durationSec,
    );
    if (!r.found) return LyricsResult.empty;
    if (r.instrumental) {
      return const LyricsResult(
        lines: [],
        synced: false,
        instrumental: true,
        found: true,
      );
    }
    if (r.hasSynced) {
      final lines = parseLrc(r.syncedLyrics!);
      return LyricsResult(
        lines: lines,
        synced: lines.isNotEmpty,
        instrumental: false,
        found: true,
      );
    }
    if (r.hasPlain) {
      return LyricsResult(
        lines: plainLyricsAsLines(r.plainLyrics!,
            totalSec: query.durationSec ?? 180),
        synced: false,
        instrumental: false,
        found: true,
      );
    }
    return LyricsResult.empty;
  },
);
