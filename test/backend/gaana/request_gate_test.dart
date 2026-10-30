import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunoh/backend/gaana/http.dart';
import 'package:sunoh/backend/gaana/request_gate.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.reply);
  final Future<ResponseBody> Function() reply;
  int hits = 0;
  int active = 0;
  int peak = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? s,
    Future<void>? c,
  ) async {
    hits++;
    active++;
    if (active > peak) peak = active;
    try {
      return await reply();
    } finally {
      active--;
    }
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  tearDown(() {
    useGaanaAdapter(null);
    gaanaGate = GaanaGate();
  });

  test('never more than maxInFlight requests at once', () async {
    gaanaGate = GaanaGate(maxStartsPerSecond: 1000);
    final a = _Adapter(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return ResponseBody.fromString('{}', 200);
    });
    useGaanaAdapter(a);
    await Future.wait([
      for (var i = 0; i < 12; i++) gaanaFetch({'i': i}),
    ]);
    expect(a.hits, 12);
    expect(a.peak, lessThanOrEqualTo(4));
    expect(a.peak, greaterThan(1));
  });

  test('starts are smoothed to the per-second cap', () async {
    gaanaGate = GaanaGate(maxInFlight: 50, maxStartsPerSecond: 3);
    final a = _Adapter(() async => ResponseBody.fromString('{}', 200));
    useGaanaAdapter(a);
    final sw = Stopwatch()..start();
    await Future.wait([
      for (var i = 0; i < 4; i++) gaanaFetch({'i': i}),
    ]);
    expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(900));
  });

  test('a 403 Access Denied page starts a cooldown that fails fast', () async {
    var t = DateTime(2026);
    gaanaGate = GaanaGate(clock: () => t);
    final a = _Adapter(
      () async => ResponseBody.fromString('<html>Access Denied</html>', 403),
    );
    useGaanaAdapter(a);
    await expectLater(gaanaFetch({'a': 1}), throwsA(isA<GaanaBlocked>()));
    expect(a.hits, 1);

    await expectLater(gaanaFetch({'a': 2}), throwsA(isA<GaanaBlocked>()));
    expect(a.hits, 1);

    t = t.add(const Duration(minutes: 3));
    await expectLater(gaanaFetch({'a': 3}), throwsA(isA<GaanaBlocked>()));
    expect(a.hits, 2);
  });
}
