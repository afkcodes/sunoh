// The loaded track's real waveform, as one loudness value per bin.
//
// mpv_audio_kit decodes the file on a worker thread and hands back a mono
// envelope of about 2000 bins (`Player.stream.waveform`). Each bin becomes
// its RMS — the loudness — when the engine reports it, else the larger of
// its two peak excursions. RMS is the better read on a mastered song, whose
// peaks sit at full scale almost everywhere. A bin the analyser has not
// reached yet is NaN, so the UI can draw it as a baseline rather than as
// silence.
//
// The analyser is listener-gated by the engine, and [WaveformFeed] listens
// for the whole session rather than only while the expanded player is open.
// Gated on the player, two kinds of track lost their waveform:
//
//  - Gaana's HLS streams cannot be decoded ahead of time; their envelope
//    fills only from playback, and only while something listens. Opened
//    mid-song, the player showed what had played since it opened: a flat bar.
//  - A Saavn file armed mid-song can no longer be read from mpv's download
//    cache in one pass, so the analyser fetched the whole file a second time.
//    Armed before the file opens, it decodes the copy playback downloads.
//
// Kept out of the UI so screens never depend on the engine's types, and out
// of audio_handler.dart, which is over the size limit.
//
// What the engine reports is also remembered per song (waveform_store.dart)
// and merged back in: a stored envelope is drawn the moment its song loads,
// and a partial engine envelope never replaces a more complete stored one.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import 'waveform_store.dart';

/// Loudness per bin, 0..1, NaN where not yet analysed; null while the
/// analyser has nothing (it emits null on every track change).
Float32List? waveformPeaks(WaveformData? w) {
  if (w == null || w.bins == 0) return null;
  final rms = w.rms;
  final out = Float32List(w.bins);
  for (var i = 0; i < w.bins; i++) {
    if (w.filled[i] == 0) {
      out[i] = double.nan;
    } else {
      out[i] = rms != null ? rms[i] : math.max(w.min[i].abs(), w.max[i].abs());
    }
  }
  return out;
}

/// A waveform and the song it belongs to.
@immutable
class TrackWaveform {
  const TrackWaveform(this.songId, this.peaks);

  /// The song loaded when the engine reported it. The player matches this
  /// against its own track, so an envelope that lands before the UI has
  /// moved to the new song is kept rather than wiped, and the old song's
  /// is never drawn under the new title.
  final String? songId;
  final Float32List peaks;
}

/// The engine's waveform for the whole session, as the latest
/// [TrackWaveform] (null between a track loading and its first bins),
/// merged with what was remembered for the song.
class WaveformFeed {
  WaveformFeed(
    Stream<WaveformData?> source,
    this._loadedSongId, {
    WaveformStore? store,
  }) : _store = store ?? WaveformStore() {
    unawaited(_store.open());
    _sub = source.listen(_onData);
  }

  /// The song id of the file the engine has loaded right now.
  final String? Function() _loadedSongId;
  final WaveformStore _store;
  late final StreamSubscription<WaveformData?> _sub;

  final ValueNotifier<TrackWaveform?> current = ValueNotifier(null);

  /// The song the app says is current. It leads [_loadedSongId]: the queue
  /// moves before the engine opens the file, which is when a stored
  /// waveform can already be drawn.
  String? _wanted;

  /// The engine's latest envelope and the song it belongs to.
  TrackWaveform? _engine;

  /// Not yet written: the latest bins for [_pendingId], saved when the song
  /// changes. Progressive envelopes are written on growth, not every tick.
  Uint8List? _pending;
  String? _pendingId;

  /// How much of [_savedId] was filled when it was last written.
  String? _savedId;
  double _savedShare = 0;

  /// A progressive envelope is written again once this much more of the
  /// song is filled in.
  static const _saveEvery = 0.05;

  /// Last kind of envelope logged, so a decode logs its phases rather than
  /// every partial snapshot.
  String? _logged;

  /// The queue moved to [songId]: write out the last song's unsaved bins and
  /// draw whatever is remembered for the new one.
  void songChanged(String? songId) {
    _flush();
    _wanted = songId;
    _publish(songId);
  }

  /// A waveform measured off-engine (waveform_fetch.dart) for [songId]. It is
  /// stored, and drawn if that song is the one on screen.
  void ingest(String songId, Uint8List bytes) {
    _store.merge(songId, bytes);
    if (songId == (_wanted ?? _loadedSongId())) _publish(songId);
  }

  /// Whether [songId] already has a complete waveform on the phone.
  bool hasComplete(String songId) {
    final stored = _store.peek(songId);
    return stored != null && isCompleteWaveform(stored);
  }

  void _onData(WaveformData? w) {
    _log(w);
    final peaks = waveformPeaks(w);
    if (peaks == null) {
      _flush();
      _engine = null;
      _publish(_wanted ?? _loadedSongId());
      return;
    }
    final id = _loadedSongId();
    if (_pendingId != null && _pendingId != id) _flush();
    _engine = TrackWaveform(id, peaks);
    _publish(id);
    // A live window is a sliding view of a radio stream, not a song.
    if (id != null && !(w?.live ?? false)) _remember(id, peaks);
  }

  void _publish(String? id) {
    if (id == null) {
      current.value = null;
      return;
    }
    final engine = _engine?.songId == id ? _engine?.peaks : null;
    final drawn = preferredWaveform(engine, _store.peek(id));
    current.value = drawn == null ? null : TrackWaveform(id, drawn);
  }

  void _remember(String id, Float32List peaks) {
    final bytes = quantiseWaveform(peaks);
    final share = filledShare(bytes);
    if (_savedId != id) {
      _savedId = id;
      _savedShare = 0;
    }
    _pending = bytes;
    _pendingId = id;
    if (isCompleteWaveform(bytes) || share - _savedShare >= _saveEvery) {
      _flush();
      _savedShare = share;
    }
  }

  void _flush() {
    final bytes = _pending;
    final id = _pendingId;
    _pending = null;
    _pendingId = null;
    if (bytes == null || id == null || filledShare(bytes) == 0) return;
    _store.merge(id, bytes);
  }

  void _log(WaveformData? w) {
    final kind = switch (w) {
      null => 'reset',
      WaveformData(live: true) => 'live window',
      WaveformData(decoding: true) => 'decoding ahead',
      // Not decoding and not live: the final envelope of a decode, or one
      // growing from playback (an HLS stream). Filled bins tell them apart.
      WaveformData(:final filled) when filled.every((f) => f != 0) => 'ready',
      _ => 'filling from playback',
    };
    if (kind == _logged) return;
    _logged = kind;
    debugPrint('[waveform] $kind${w == null ? '' : ' (${w.bins} bins)'}');
  }

  Future<void> dispose() async {
    _flush();
    await _sub.cancel();
    current.dispose();
  }
}
