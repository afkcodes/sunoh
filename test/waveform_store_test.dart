import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:sunoh/audio/hls_download.dart';
import 'package:sunoh/audio/waveform_analyse.dart';
import 'package:sunoh/audio/waveform_store.dart';

Float32List _env(int n, double Function(int) f, {int gapFrom = -1}) {
  final out = Float32List(n);
  for (var i = 0; i < n; i++) {
    out[i] = gapFrom >= 0 && i >= gapFrom ? double.nan : f(i);
  }
  return out;
}

void main() {
  group('quantise', () {
    test('round-trips within one level and keeps gaps as NaN', () {
      final src = _env(2000, (i) => (i % 100) / 100, gapFrom: 1000);
      final q = quantiseWaveform(src);
      expect(q.length, kStoredBins);
      expect(q.sublist(0, 200).contains(kUnfilled), isFalse);
      expect(q.sublist(200).every((b) => b == kUnfilled), isTrue);
      final back = dequantiseWaveform(q);
      expect(back[250].isNaN, isTrue);
      expect(back[0], inInclusiveRange(0, 1));
    });

    test('a mostly-empty target bin stays unfilled', () {
      // 5 source bins per target bin; only the first of the last group set.
      final src = _env(2000, (_) => 0.5)..fillRange(1995, 2000, double.nan);
      src[1995] = 0.5;
      expect(quantiseWaveform(src).last, kUnfilled);
    });

    test('complete and share', () {
      final full = quantiseWaveform(_env(400, (_) => 0.3));
      expect(isCompleteWaveform(full), isTrue);
      final half = quantiseWaveform(_env(400, (_) => 0.3, gapFrom: 200));
      expect(isCompleteWaveform(half), isFalse);
      expect(filledShare(half), closeTo(0.5, 0.01));
    });
  });

  group('merge and preference', () {
    test('filled beats unfilled, newer beats older', () {
      final a = quantiseWaveform(_env(400, (_) => 0.2, gapFrom: 200));
      final b = Uint8List(400)..fillRange(0, 400, kUnfilled);
      for (var i = 150; i < 400; i++) {
        b[i] = 100;
      }
      final m = mergeWaveforms(a, b);
      expect(isCompleteWaveform(m), isTrue);
      expect(m[0], a[0]);
      expect(m[160], 100);
      expect(m[300], 100);
    });

    test('a partial engine envelope never replaces a more complete store', () {
      final stored = quantiseWaveform(_env(400, (_) => 0.4));
      final engine = _env(2000, (_) => 0.1, gapFrom: 100);
      final out = preferredWaveform(engine, stored)!;
      expect(out.any((v) => v.isNaN), isFalse);
      expect(out[399], closeTo(0.4, 0.01));
      // A complete store is kept whole: the engine's scale differs.
      expect(out[0], closeTo(0.4, 0.01));
    });

    test('a partial engine envelope fills the gaps of a partial store', () {
      final stored = quantiseWaveform(_env(400, (_) => 0.4, gapFrom: 200));
      final engine = _env(2000, (_) => 0.1, gapFrom: 1500);
      final out = preferredWaveform(engine, stored)!;
      expect(out.any((v) => v.isNaN), isTrue);
      expect(out[0], closeTo(0.1, 0.01));
      expect(out[250], closeTo(0.1, 0.01));
      expect(out[399].isNaN, isTrue);
    });

    test('a complete engine envelope is drawn as is', () {
      final engine = _env(2000, (_) => 0.7);
      final stored = quantiseWaveform(_env(400, (_) => 0.1));
      expect(identical(preferredWaveform(engine, stored), engine), isTrue);
    });

    test('nothing stored: engine passes through; nothing at all: null', () {
      final engine = _env(2000, (_) => 0.7, gapFrom: 10);
      expect(identical(preferredWaveform(engine, null), engine), isTrue);
      expect(preferredWaveform(null, null), isNull);
      expect(
        preferredWaveform(null, quantiseWaveform(_env(400, (_) => 0.5))),
        isNotNull,
      );
    });
  });

  group('WaveformStore', () {
    late Directory tmp;
    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('wf_store');
      Hive.init(tmp.path);
    });
    tearDown(() async {
      await Hive.close();
      tmp.deleteSync(recursive: true);
    });

    test('merges across plays, survives reopen, evicts oldest', () async {
      var store = WaveformStore(cap: 3);
      await store.open();
      final first = quantiseWaveform(_env(400, (_) => 0.3, gapFrom: 200));
      final second = Uint8List(400)..fillRange(0, 400, kUnfilled);
      second.fillRange(200, 400, 50);
      store.merge('a', first);
      final merged = store.merge('a', second);
      expect(isCompleteWaveform(merged), isTrue);

      await Hive.close();
      Hive.init(tmp.path);
      store = WaveformStore(cap: 3);
      await store.open();
      expect(isCompleteWaveform(store.peek('a')!), isTrue);

      store.merge('b', first);
      store.merge('c', first);
      store.merge('a', first); // a is now the freshest
      store.merge('d', first); // evicts b, the least recently used
      expect(store.peek('b'), isNull);
      expect(store.peek('a'), isNotNull);
      expect(store.peek('c'), isNotNull);
      expect(store.peek('d'), isNotNull);
    });

    test('an unopened store is inert, not an error', () {
      final store = WaveformStore();
      expect(store.peek('x'), isNull);
      expect(store.merge('x', Uint8List(400)).length, 400);
    });
  });

  group('HLS variant choice', () {
    const master = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=64000,AVERAGE-BANDWIDTH=70000,CODECS="mp4a.40.2"
64.mp4.m3u8?hdnts=x
#EXT-X-STREAM-INF:BANDWIDTH=320000,AVERAGE-BANDWIDTH=10,CODECS="mp4a.40.2"
320.mp4.m3u8?hdnts=x
#EXT-X-STREAM-INF:BANDWIDTH=128000,CODECS="mp4a.40.2"

128.mp4.m3u8?hdnts=x
''';

    test('lowest and highest by BANDWIDTH, ignoring AVERAGE-BANDWIDTH', () {
      expect(
        HlsDownloader.pickVariant(master, lowest: true),
        startsWith('64.'),
      );
      expect(HlsDownloader.pickVariant(master), startsWith('320.'));
    });

    test('a media playlist has no variants', () {
      expect(
        HlsDownloader.pickVariant('#EXTM3U\n#EXTINF:6,\nseg0.ts\n'),
        isNull,
      );
    });
  });

  group('RMS binning', () {
    test('averages energy per bin and clamps', () {
      final ms = Float32List.fromList([0.04, 0.04, 0.16, 0.16]);
      final bins = binWindows(ms, 2);
      expect(bins[0], closeTo(0.2, 1e-6));
      expect(bins[1], closeTo(0.4, 1e-6));
    });

    test('fewer windows than bins repeats rather than leaving gaps', () {
      final bins = binWindows(Float32List.fromList([0.25, 1.0]), 6);
      expect(bins.any((v) => v.isNaN), isFalse);
      expect(bins.first, closeTo(0.5, 1e-6));
      expect(bins.last, closeTo(1.0, 1e-6));
    });
  });

  test('extractAdts pulls the audio PES payload out of TS packets', () {
    Uint8List ts(int pid, bool start, List<int> payload) {
      final p = Uint8List(188)..fillRange(0, 188, 0xFF);
      p[0] = 0x47;
      p[1] = (start ? 0x40 : 0) | (pid >> 8);
      p[2] = pid & 0xFF;
      p[3] = 0x10; // payload only
      p.setRange(4, 4 + payload.length, payload);
      return p;
    }

    // PES: 00 00 01, stream id, length(2), flags(2), header length 0.
    Uint8List pes(int id, List<int> data) =>
        Uint8List.fromList([0, 0, 1, id, 0, 0, 0x80, 0x00, 0, ...data]);
    // Exact-fit payloads: a 184-byte body with no stuffing.
    final audio1 = List.generate(175, (i) => i & 0x7F);
    final audio2 = List.generate(184, (i) => 200 - (i & 0x3F));
    final b = BytesBuilder()
      ..add(ts(0x100, true, pes(0xBD, [9, 9, 9]))) // ID3 stream, ignored
      ..add(ts(0x101, true, pes(0xC0, audio1)))
      ..add(ts(0x101, false, audio2))
      ..add(ts(0x100, false, [7, 7]));
    final out = extractAdts(b.takeBytes());
    expect(out, [...audio1, ...audio2]);
  });
}
