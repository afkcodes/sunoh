// Applies SponsorBlock segments during playback.
//
// Kept out of AudioRepo and AppState so the policy — which segments count,
// when to jump, how not to fight the user — lives in one testable place.

import '../api/dto.dart';
import '../api/sponsorblock.dart';

class SponsorBlockSkipper {
  SponsorBlockSkipper({required SponsorBlockClient client}) : _client = client;

  final SponsorBlockClient _client;

  /// Off until the user's persisted setting is restored, so we never skip
  /// on the strength of a default the user has already turned off.
  bool enabled = false;

  Set<String> categories = kDefaultSponsorBlockCategories;

  String? _videoId;
  List<SkipSegment> _segments = const [];

  /// Segments already jumped. Prevents an immediate re-skip when the user
  /// deliberately seeks back into one — the point is to skip filler once,
  /// not to make part of a track unreachable.
  final Set<String> _applied = <String>{};

  /// A skip lands the play head at `segment.end`; mpv then reports a few
  /// positions around there. Without a margin the *next* adjacent segment
  /// can trigger before the first one is recorded as applied.
  static const _kEnterMargin = Duration(milliseconds: 500);

  /// Below this a jump is more disruptive than the segment it removes.
  static const _kMinSegment = Duration(seconds: 1);

  /// Segments for the track now loading, if any. Safe to call for every
  /// track — non-YouTube sources short-circuit without a request.
  Future<void> onTrackChanged(FeedItem? song) async {
    _segments = const [];
    _applied.clear();
    _videoId = null;

    if (song == null) return;
    if (!enabled || song.source != 'youtube') {
      // Logged so the three ways this stays quiet — switched off, wrong
      // source, or genuinely no segments — are distinguishable.
      // ignore: avoid_print
      print('[sponsorblock] skip check off for ${song.id} '
          '(enabled=$enabled source=${song.source})');
      return;
    }

    _videoId = song.id;
    // ignore: avoid_print
    print('[sponsorblock] looking up ${song.id}\u2026');
    final segments =
        await _client.segmentsFor(song.id, categories: categories);

    // The track may have changed while the request was in flight.
    if (_videoId != song.id) {
      // ignore: avoid_print
      print('[sponsorblock] dropped stale result for ${song.id}');
      return;
    }
    _segments = segments;
    // `print`, not `debugPrint`: the audio layer's diagnostics need to
    // survive release builds — that's where playback issues actually get
    // reported from. Logged even when empty, since "no segments" and "the
    // lookup never ran" look identical otherwise.
    // ignore: avoid_print
    print('[sponsorblock] ${song.id}: ${segments.length} segment(s)'
        '${segments.isEmpty ? '' : ' — ${segments.join(', ')}'}');
  }

  /// Where to seek to, or null to keep playing.
  ///
  /// Returns the end of the segment [position] currently falls inside.
  Duration? skipTargetFor(Duration position) {
    if (!enabled || _segments.isEmpty) return null;
    for (final seg in _segments) {
      if (seg.length < _kMinSegment) continue;
      if (_applied.contains(seg.uuid)) continue;
      if (position >= seg.start &&
          position < seg.end - _kEnterMargin) {
        _applied.add(seg.uuid);
        // ignore: avoid_print
        print('[sponsorblock] skipping $seg');
        return seg.end;
      }
    }
    return null;
  }

  void clear() {
    _segments = const [];
    _applied.clear();
    _videoId = null;
  }
}
