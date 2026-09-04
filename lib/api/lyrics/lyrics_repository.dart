// Where the player gets its lyrics.
//
// Ported from BitChord (https://github.com/kushagrasinghx/BitChord), GPL-3.0.
//
// Every enabled source is asked *at the same time*, but their answers are
// taken in priority order: the loop awaits them one at a time in that
// sequence, so a lower-priority source finishing first never preempts one
// still pending ahead of it. Asked one after another instead, a miss on each
// source would cost its own round trip before the next was even tried, and a
// track with no lyrics anywhere would spend most of a minute finding that out
// with six of them. Run together, a miss costs whatever the slowest source
// still being waited on took.
//
// The first source in [LyricsSource]'s order to answer wins. See that enum for
// why the order is authoritative rather than word timing — in short, the
// ranking already weighs timing against how often a source actually answers.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/lyric_line.dart';
import 'background_vocals.dart';
import 'better_lyrics.dart';
import 'lrclib_source.dart';
import 'lyrics_plus.dart';
import 'lyrics_source.dart';
import 'musixmatch.dart';
import 'paxsenix.dart';
import 'simpmusic_lyrics.dart';

/// Lyrics, and which source they turned out to come from.
class LyricsHit {
  const LyricsHit(this.source, this.lines);
  final LyricsSource source;
  final List<LyricLine> lines;
}

/// Looks the track up across every source in [sources] at once.
///
/// [videoId] is only used by SimpMusic, which is the one source keyed on the
/// exact track rather than on its title; an empty id simply skips it.
///
/// [prioritiseWordSync] decides what happens once *something* has come back.
/// Off — the default — the highest-priority source's own answer is taken
/// as-is, word-synced or not: priority is priority, and second-guessing it
/// after it has already answered is not what "first" was supposed to mean. On,
/// a merely line-synced answer is kept as a fallback while the search carries
/// on through the rest of the order looking for a word-synced one.
Future<LyricsHit?> fetchLyrics({
  required String title,
  required String artist,
  required int durationMs,
  String videoId = '',
  String? album,
  Set<LyricsSource> sources = const {...LyricsSource.values},
  bool prioritiseWordSync = false,
}) async {
  final order = LyricsSource.values.where(sources.contains).toList();
  if (order.isEmpty || title.trim().isEmpty) return null;

  // Started together, before anything is awaited. Each future is guarded so a
  // thrown error resolves to a miss rather than an unhandled rejection while
  // the loop is still waiting on a source ahead of it.
  final racing = <LyricsSource, Future<List<LyricLine>?>>{
    for (final source in order)
      source: _fetch(source, title, artist, durationMs, videoId, album)
          .catchError((Object e) {
            debugPrint('[lyrics] ${source.label} failed: $e');
            return null;
          }),
  };

  LyricsHit? lineSynced;
  for (final source in order) {
    final lines = await racing[source];
    if (lines == null || lines.isEmpty) continue;

    if (lines.any((l) => l.isWordSynced)) return _hit(source, lines);
    if (!prioritiseWordSync) return _hit(source, lines);
    lineSynced ??= _hit(source, lines);
  }
  return lineSynced;
}

Future<List<LyricLine>?> _fetch(
  LyricsSource source,
  String title,
  String artist,
  int durationMs,
  String videoId,
  String? album,
) => switch (source) {
  LyricsSource.betterLyrics => fetchBetterLyrics(
    title: title,
    artist: artist,
    durationMs: durationMs,
    album: album,
  ),
  LyricsSource.lyricsPlus => fetchLyricsPlus(
    title: title,
    artist: artist,
    durationMs: durationMs,
    album: album,
  ),
  LyricsSource.paxSenix => fetchPaxSenix(
    title: title,
    artist: artist,
    durationMs: durationMs,
    album: album,
  ),
  LyricsSource.simpMusic => fetchSimpMusicLyrics(
    videoId: videoId,
    durationMs: durationMs,
  ),
  LyricsSource.lrcLib => fetchLrcLib(
    title: title,
    artist: artist,
    durationMs: durationMs,
    album: album,
  ),
  LyricsSource.musixmatch => fetchMusixmatch(
    title: title,
    artist: artist,
    durationMs: durationMs,
  ),
};

/// Whichever source won, its lines get the same last pass: the answering vocal
/// split off the lead so it can be drawn under it. Done here rather than in
/// each parser because most sources write it as a bracket and only TTML knows
/// it structurally — the split leaves that one's own alone.
LyricsHit _hit(LyricsSource source, List<LyricLine> lines) {
  debugPrint('[lyrics] ${source.label} answered with ${lines.length} lines');
  return LyricsHit(source, withBackgroundVocals(lines));
}
