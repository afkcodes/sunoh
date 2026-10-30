// Waveforms remembered per song, so a track's shape is there the moment it
// loads instead of filling in behind the playhead every time.
//
// Gaana streams are HLS, which the engine cannot decode ahead: its envelope
// only grows as the song plays. Remembering what was heard means a song
// played halfway twice ends up complete, and the fetch-ahead pass
// (waveform_fetch.dart) can fill one in before the first play.
//
// Stored small on purpose: 400 bins, one byte each (~400 B a song). The
// scrubber folds the envelope to a hundred-odd bars, so the engine's 2000 bins
// would be mostly invisible detail. Byte 255 means "not analysed", so a
// partial envelope round-trips and a later pass can fill the gaps — filled
// beats unfilled when two envelopes are merged. A float per bin with NaN for
// the gap was rejected: four times the size for precision nothing draws.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

/// Bins kept per song.
const kStoredBins = 400;

/// The "not analysed yet" byte. Levels use 0..254.
const kUnfilled = 255;

/// Fold a [peaks] envelope (0..1, NaN = not analysed) into [bins] bytes.
///
/// A target bin counts as filled only when at least half of the source bins
/// under it are: a progressive envelope's frontier bin is mostly empty, and
/// averaging its few filled bins would draw a dip that is not in the song.
/// Loudness combines as RMS of RMS, the correct way to join energies.
Uint8List quantiseWaveform(Float32List peaks, {int bins = kStoredBins}) {
  final out = Uint8List(bins)..fillRange(0, bins, kUnfilled);
  final n = peaks.length;
  if (n == 0) return out;
  for (var i = 0; i < bins; i++) {
    final from = (i * n) ~/ bins;
    final to = math.max(from + 1, ((i + 1) * n) ~/ bins);
    var energy = 0.0;
    var filled = 0;
    for (var j = from; j < to && j < n; j++) {
      final v = peaks[j];
      if (v.isNaN) continue;
      energy += v * v;
      filled++;
    }
    if (filled * 2 < to - from) continue;
    final rms = math.sqrt(energy / filled).clamp(0.0, 1.0);
    out[i] = (rms * 254).round();
  }
  return out;
}

/// Back to loudness 0..1 with NaN for the gaps, the shape the scrubber reads.
Float32List dequantiseWaveform(Uint8List bytes) {
  final out = Float32List(bytes.length);
  for (var i = 0; i < bytes.length; i++) {
    out[i] = bytes[i] == kUnfilled ? double.nan : bytes[i] / 254;
  }
  return out;
}

/// True when no bin is missing.
bool isCompleteWaveform(Uint8List bytes) =>
    bytes.isNotEmpty && !bytes.contains(kUnfilled);

/// Share of bins that are filled, 0..1.
double filledShare(Uint8List bytes) {
  if (bytes.isEmpty) return 0;
  var n = 0;
  for (final b in bytes) {
    if (b != kUnfilled) n++;
  }
  return n / bytes.length;
}

/// Combine an earlier [stored] envelope with a new [incoming] one: a filled
/// bin beats an unfilled one, and where both are filled the newer wins.
///
/// A complete [stored] envelope is kept against an incomplete [incoming] one.
/// The engine's progressive envelope sits on a different scale and time axis
/// (its length is estimated from the bitrate for HLS), so laying its bins
/// over a measured whole song drew a tall frontier up to the playhead and a
/// near-floor remainder after it.
Uint8List mergeWaveforms(Uint8List? stored, Uint8List incoming) {
  if (stored == null || stored.length != incoming.length) return incoming;
  if (isCompleteWaveform(stored) && !isCompleteWaveform(incoming)) {
    return stored;
  }
  final out = Uint8List.fromList(stored);
  for (var i = 0; i < incoming.length; i++) {
    if (incoming[i] != kUnfilled) out[i] = incoming[i];
  }
  return out;
}

/// What to draw for the loaded song given the engine's [engine] envelope and
/// the [stored] one: a complete engine envelope is the best there is and is
/// drawn at its own resolution; a complete stored one beats a partial engine
/// one outright; otherwise the partial is merged over what was remembered, so
/// a half-filled engine envelope never replaces a more complete stored one. Null when there is nothing for either.
Float32List? preferredWaveform(Float32List? engine, Uint8List? stored) {
  if (engine != null && !engine.any((v) => v.isNaN) && engine.isNotEmpty) {
    return engine;
  }
  if (stored == null) return engine;
  if (engine == null || isCompleteWaveform(stored)) {
    return dequantiseWaveform(stored);
  }
  return dequantiseWaveform(mergeWaveforms(stored, quantiseWaveform(engine)));
}

/// Hive-backed store: song id to its bytes, plus an LRU order list.
class WaveformStore {
  WaveformStore({this.cap = 300});

  /// Songs kept. At ~400 B each the box stays around 120 KB.
  final int cap;

  static const _boxName = 'waveforms';
  static const _orderKey = '_lru';

  Box<dynamic>? _box;

  /// Open the box. Failure leaves the store inert (every read null) rather
  /// than throwing: a waveform is decoration and must never reach playback.
  Future<void> open() async {
    try {
      _box = await Hive.openBox<dynamic>(_boxName);
    } catch (e) {
      debugPrint('[waveform] store unavailable: $e');
    }
  }

  List<String> get _order {
    final raw = _box?.get(_orderKey);
    return raw is List ? raw.cast<String>().toList() : <String>[];
  }

  /// The stored bytes for [songId], or null. Synchronous once opened, so the
  /// feed can publish in the same turn a track changes.
  Uint8List? peek(String songId) {
    final v = _box?.get(songId);
    return v is Uint8List && v.length == kStoredBins ? v : null;
  }

  /// Merge [incoming] into whatever is stored for [songId], mark it most
  /// recently used and evict past [cap]. Returns the merged bytes.
  Uint8List merge(String songId, Uint8List incoming) {
    final merged = mergeWaveforms(peek(songId), incoming);
    final box = _box;
    if (box == null) return merged;
    final order = _order
      ..remove(songId)
      ..add(songId);
    final evicted = <String>[];
    while (order.length > cap) {
      evicted.add(order.removeAt(0));
    }
    box.put(songId, merged);
    box.put(_orderKey, order);
    if (evicted.isNotEmpty) box.deleteAll(evicted);
    return merged;
  }
}
