// The unit heuristic behind every "is this URL still good?" decision.
//
// Worth pinning because getting it wrong is silent rather than loud: reading
// an epoch-seconds value as milliseconds lands in 1970, every staleness check
// then reads "already expired", and the app re-resolves on every single play
// while appearing to work.

import 'package:flutter_test/flutter_test.dart';
import 'package:sunoh/audio/url_refresh.dart';

void main() {
  group('expiryFromNumber', () {
    test('epoch milliseconds are taken as-is', () {
      final at = UrlRefreshScheduler.expiryFromNumber(1788435705000);
      expect(at, DateTime.fromMillisecondsSinceEpoch(1788435705000));
    });

    test('epoch seconds are scaled, not read as millis', () {
      // The whole point: 1788435705 as millis would be January 1970.
      final at = UrlRefreshScheduler.expiryFromNumber(1788435705)!;
      expect(at.year, greaterThan(2020));
      expect(at, DateTime.fromMillisecondsSinceEpoch(1788435705 * 1000));
    });

    test('a small number is a TTL from now', () {
      final at = UrlRefreshScheduler.expiryFromNumber(3600)!;
      final delta = at.difference(DateTime.now());
      expect(delta.inMinutes, closeTo(60, 1));
    });

    test('a TTL beyond a week is not trusted', () {
      // Ambiguous with a malformed timestamp, and nothing signs a URL for
      // longer than a week — so it is better to say "no expiry stated".
      expect(UrlRefreshScheduler.expiryFromNumber(86400 * 30), isNull);
    });

    test('nothing usable yields null rather than a guess', () {
      expect(UrlRefreshScheduler.expiryFromNumber(null), isNull);
      expect(UrlRefreshScheduler.expiryFromNumber('nonsense'), isNull);
      expect(UrlRefreshScheduler.expiryFromNumber(0), isNull);
      expect(UrlRefreshScheduler.expiryFromNumber(-5), isNull);
    });

    test('accepts the shapes JSON actually arrives in', () {
      // num from a decoded body, and a string from a query parameter.
      expect(UrlRefreshScheduler.expiryFromNumber(1788435705.0), isNotNull);
      expect(UrlRefreshScheduler.expiryFromNumber('1788435705'), isNotNull);
    });
  });

  group('parseExpiry', () {
    test('reads the lossless CDN etsp parameter', () {
      final at = UrlRefreshScheduler.parseExpiry(
        'https://cdn.example/track.flac?etsp=1788435705&hmac=abc',
      )!;
      expect(at.year, greaterThan(2020));
    });

    test('a URL with no expiry parameter yields null', () {
      expect(
        UrlRefreshScheduler.parseExpiry('https://cdn.example/a.flac'),
        isNull,
      );
    });
  });
}
