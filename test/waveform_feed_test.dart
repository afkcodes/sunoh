import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';
import 'package:sunoh/audio/waveform_peaks.dart';
import 'package:sunoh/audio/waveform_store.dart';

const _bins = 2000;

/// An engine envelope with the first [filled] bins analysed.
WaveformData _partial(int filled) => WaveformData(
  duration: const Duration(minutes: 3),
  min: Float32List(_bins),
  max: Float32List(_bins),
  rms: Float32List.fromList(List.filled(_bins, 0.4)),
  filled: Uint8List.fromList([
    for (var i = 0; i < _bins; i++) i < filled ? 1 : 0,
  ]),
);

void main() {
  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('wf_feed');
    Hive.init(dir.path);
  });
  tearDown(() async {
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  test('a measured waveform survives the next engine emission', () async {
    final src = StreamController<WaveformData?>.broadcast(sync: true);
    const loaded = 'bang-song';
    final feed = WaveformFeed(src.stream, () => loaded);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    feed.songChanged('bang-song');
    src.add(null);
    src.add(_partial(100));
    src.add(_partial(300));
    src.add(_partial(400));
    var shown = feed.current.value!;
    expect(shown.songId, 'bang-song');
    expect(shown.peaks.where((v) => v.isNaN), isNotEmpty);

    feed.ingest(
      'bang-song',
      Uint8List(kStoredBins)..fillRange(0, kStoredBins, 90),
    );
    shown = feed.current.value!;
    expect(shown.peaks.any((v) => v.isNaN), isFalse);

    src.add(_partial(140));
    shown = feed.current.value!;
    expect(shown.songId, 'bang-song');
    expect(shown.peaks.any((v) => v.isNaN), isFalse);
    // The measured song is drawn as measured: the engine's frontier bins
    // (a different scale and time axis for HLS) do not replace any of it.
    expect(shown.peaks.every((v) => (v - 90 / 254).abs() < 1e-6), isTrue);
    await feed.dispose();
    await src.close();
  });
}
