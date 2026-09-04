// Lyrics state — looked up across every source in `lib/api/lyrics/`.
//
// Family key is intentionally compact (track + artist + duration) so two
// queues pointing at the same song share one fetch. The result auto-caches for
// 24 h because lyrics don't change — and because six third-party services are
// asked at once, which is not something to repeat on every sheet-open.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/lyrics/lrc_parser.dart';
import '../api/lyrics/lrclib_source.dart';
import '../api/lyrics/lyrics_repository.dart';
import '../api/lyrics/lyrics_source.dart';
import '../data/lyric_line.dart';

/// Compact, hash-friendly identity for a lyrics fetch. Two queries are equal
/// when their (lower-cased) track + artist + duration agree.
class LyricsQuery {
  const LyricsQuery({
    required this.track,
    required this.artist,
    this.album,
    this.durationSec,
    this.videoId = '',
  });
  final String track;
  final String artist;
  final String? album;
  final int? durationSec;

  /// SimpMusic matches on this rather than on the title, so it alone can never
  /// return a different edit. Empty for anything that isn't a YouTube track.
  final String videoId;

  @override
  bool operator ==(Object other) =>
      other is LyricsQuery &&
      other.track.toLowerCase() == track.toLowerCase() &&
      other.artist.toLowerCase() == artist.toLowerCase() &&
      other.album?.toLowerCase() == album?.toLowerCase() &&
      other.durationSec == durationSec &&
      other.videoId == videoId;

  @override
  int get hashCode => Object.hash(
    track.toLowerCase(),
    artist.toLowerCase(),
    album?.toLowerCase(),
    durationSec,
    videoId,
  );
}

class LyricsResult {
  const LyricsResult({
    required this.lines,
    required this.synced,
    required this.instrumental,
    required this.found,
    this.source,
  });
  final List<LyricLine> lines;

  /// True iff the lines carry real timing. False when we synthesised them from
  /// plain text — the UI uses this to decide whether to drive highlighting
  /// from playback position at all.
  final bool synced;

  /// LRCLIB explicitly marked the song as instrumental. UI shows a dedicated
  /// "instrumental" state rather than a blank screen.
  final bool instrumental;

  /// False when no source had anything. UI renders a "no lyrics yet" hint.
  final bool found;

  /// Which source won, for the credit line under the lyrics. Null for the
  /// plain-text fallback, which came from no synced source at all.
  final LyricsSource? source;

  /// True when the winning source carried per-word timings, which is what the
  /// karaoke sweep needs — a line-synced result highlights whole lines.
  bool get wordSynced => lines.any((l) => l.isWordSynced);

  static const empty = LyricsResult(
    lines: [],
    synced: false,
    instrumental: false,
    found: false,
  );
}

final lyricsProvider = FutureProvider.autoDispose
    .family<LyricsResult, LyricsQuery>((ref, query) async {
      // Keep the entry warm for a day after every consumer has unsubscribed so
      // re-opening the lyrics sheet for the same track doesn't refetch.
      final link = ref.keepAlive();
      Future.delayed(const Duration(hours: 24), link.close);

      final durationMs = (query.durationSec ?? 0) * 1000;
      final hit = await fetchLyrics(
        title: query.track,
        artist: query.artist,
        album: query.album,
        durationMs: durationMs,
        videoId: query.videoId,
      );
      if (hit != null) {
        return LyricsResult(
          lines: hit.lines,
          synced: true,
          instrumental: false,
          found: true,
          source: hit.source,
        );
      }

      // Nothing synced anywhere. LRCLIB is the only source that distinguishes
      // "instrumental" from "not on file", and it may still hold plain text
      // for a song none of the synced sources had — both are worth one more
      // look at a response it has already cached.
      final plain = await lookupLrcLib(
        title: query.track,
        artist: query.artist,
        album: query.album,
        durationSec: query.durationSec,
      );
      if (plain.instrumental) {
        return const LyricsResult(
          lines: [],
          synced: false,
          instrumental: true,
          found: true,
        );
      }
      if (plain.hasPlain) {
        return LyricsResult(
          lines: plainLyricsAsLines(
            plain.plainLyrics!,
            totalSec: query.durationSec ?? 180,
          ),
          synced: false,
          instrumental: false,
          found: true,
          source: LyricsSource.lrcLib,
        );
      }
      return LyricsResult.empty;
    });
