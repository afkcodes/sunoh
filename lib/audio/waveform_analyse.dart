// Measuring a downloaded audio file's loudness envelope off the player.
//
// The engine allows one waveform per process: opening a second file through
// mpv would replace the playing track's envelope (mpv_audio_kit README,
// section 13.5), and mpv_audio_kit 0.5.3 has no per-file analysis that avoids
// the player. So the decode happens natively (WaveformBridge.kt: Android's
// MediaExtractor + MediaCodec, on a worker thread) and hands back one
// mean-square value per short window; the binning lives here, where it is
// testable.
//
// Gaana's segments are MPEG-TS carrying ADTS AAC. The platform extractor
// normally opens concatenated TS directly; if it finds no audio track the
// ADTS elementary stream is pulled out of the TS here and tried again, which
// the extractor reads as a plain .aac file.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'waveform_store.dart';

/// Fold equal-sized [meanSquares] windows into [bins] loudness values: each
/// bin is the RMS over the windows it spans, 0..1 for full-scale PCM. Every
/// bin covers at least one window, so a clip shorter than [bins] windows
/// repeats rather than leaving gaps.
Float32List binWindows(Float32List meanSquares, int bins) {
  final out = Float32List(bins);
  final n = meanSquares.length;
  if (n == 0) return out..fillRange(0, bins, double.nan);
  for (var i = 0; i < bins; i++) {
    final from = math.min((i * n) ~/ bins, n - 1);
    final to = math.max(from + 1, ((i + 1) * n) ~/ bins);
    var sum = 0.0;
    for (var j = from; j < to; j++) {
      sum += meanSquares[j];
    }
    out[i] = math.sqrt(sum / (to - from)).clamp(0.0, 1.0);
  }
  return out;
}

/// The ADTS AAC elementary stream inside an MPEG-TS byte stream [ts].
///
/// The audio PID is found by its PES stream id (0xC0..0xDF) rather than by
/// walking PAT and PMT: HLS segments carry one audio program, and the ID3
/// timed-metadata stream next to it uses a private id that this ignores.
Uint8List extractAdts(Uint8List ts) {
  const packet = 188;
  final out = BytesBuilder(copy: false);
  int? audioPid;
  for (var at = 0; at + packet <= ts.length; at += packet) {
    if (ts[at] != 0x47) continue;
    final starts = ts[at + 1] & 0x40 != 0;
    final pid = ((ts[at + 1] & 0x1f) << 8) | ts[at + 2];
    final adaptation = (ts[at + 3] >> 4) & 0x3;
    if (adaptation & 1 == 0) continue;
    var body = at + 4;
    if (adaptation & 2 != 0) body += 1 + ts[at + 4];
    if (body >= at + packet) continue;
    if (starts) {
      if (body + 9 > at + packet) continue;
      final isPes = ts[body] == 0 && ts[body + 1] == 0 && ts[body + 2] == 1;
      if (!isPes) continue;
      final streamId = ts[body + 3];
      if (audioPid == null && streamId >= 0xC0 && streamId <= 0xDF) {
        audioPid = pid;
      }
      if (pid != audioPid) continue;
      body += 9 + ts[body + 8];
      if (body >= at + packet) continue;
    } else if (pid != audioPid) {
      continue;
    }
    out.add(Uint8List.sublistView(ts, body, at + packet));
  }
  return out.takeBytes();
}

class WaveformAnalyser {
  const WaveformAnalyser();

  static const _channel = MethodChannel('codes.afk.sunoh/waveform');

  /// The envelope of the audio file at [path], quantised for the store, or
  /// null when the platform could not decode it. Never throws: a waveform is
  /// decoration.
  Future<Uint8List?> measure(String path) async {
    try {
      var windows = await _windows(path);
      if (windows == null) {
        final adts = File('$path.aac');
        try {
          await adts.writeAsBytes(extractAdts(await File(path).readAsBytes()));
          windows = await _windows(adts.path);
        } finally {
          if (adts.existsSync()) adts.deleteSync();
        }
      }
      if (windows == null || windows.isEmpty) return null;
      return quantiseWaveform(binWindows(windows, kStoredBins));
    } catch (e) {
      debugPrint('[waveform] measure failed: ${e.runtimeType}');
      return null;
    }
  }

  /// Whether the active network is metered (mobile data, a hotspot). Unknown,
  /// or any failure, counts as metered: the caller only spends data when it
  /// is sure it is free.
  Future<bool> isMetered() async {
    try {
      return await _channel.invokeMethod<bool>('isMetered') ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Null when the extractor cannot open the file as audio (no track, or it
  /// refuses the container), which is what sends [measure] to the ADTS retry.
  Future<Float32List?> _windows(String path) async {
    try {
      return await _channel.invokeMethod<Float32List>('analyse', {
        'path': path,
      });
    } on PlatformException {
      return null;
    }
  }
}
