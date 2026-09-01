// Round-trip tests for the Android Auto media-id codec.
//
// These ids are the only context `playFromMediaId` gets — possibly in a fresh
// process, hours later, from a head unit that persisted them. If encode and
// decode disagree by one character the car plays the wrong thing, and nothing
// in the phone UI would ever reveal it.

import 'package:flutter_test/flutter_test.dart';
import 'package:sunoh/audio/auto_media_id.dart';

void main() {
  group('collection ids', () {
    test('round-trips a plain id', () {
      final id = AutoMediaId.collection(
        kind: 'album',
        id: 'abc',
        source: 'saavn',
      );
      final ref = AutoMediaId.parseCollection(id);
      expect(ref, isNotNull);
      expect(ref!.kind, 'album');
      expect(ref.id, 'abc');
      expect(ref.source, 'saavn');
    });

    test('round-trips an empty source (local content)', () {
      final id = AutoMediaId.collection(kind: 'user', id: 'pl1');
      final ref = AutoMediaId.parseCollection(id)!;
      expect(ref.kind, 'user');
      expect(ref.id, 'pl1');
      expect(ref.source, isEmpty);
    });

    // The reason this codec exists. Upstream browse ids are not ours to
    // control and some carry colons; a positional split would hand back a
    // different collection than the user tapped.
    test('round-trips an id containing colons', () {
      final id = AutoMediaId.collection(
        kind: 'playlist',
        id: 'VL:PL:xyz',
        source: 'youtube',
      );
      final ref = AutoMediaId.parseCollection(id)!;
      expect(ref.kind, 'playlist');
      expect(ref.id, 'VL:PL:xyz', reason: 'inner colons must survive');
      expect(ref.source, 'youtube');
    });

    test('rejects ids that are not collections', () {
      expect(AutoMediaId.parseCollection('sunoh:t:liked'), isNull);
      expect(AutoMediaId.parseCollection('sunoh:s:x#1'), isNull);
      expect(AutoMediaId.parseCollection('garbage'), isNull);
      expect(AutoMediaId.parseCollection(''), isNull);
    });

    test('rejects a truncated collection id', () {
      expect(AutoMediaId.parseCollection('sunoh:c:album'), isNull);
    });
  });

  group('track ids', () {
    test('round-trips container and index', () {
      final id = AutoMediaId.track('sunoh:t:liked', 4);
      final ref = AutoMediaId.parseTrack(id)!;
      expect(ref.containerId, 'sunoh:t:liked');
      expect(ref.index, 4);
    });

    test('round-trips over a collection container', () {
      final container = AutoMediaId.collection(kind: 'user', id: 'pl1');
      final ref = AutoMediaId.parseTrack(AutoMediaId.track(container, 0))!;
      expect(ref.containerId, container);
      expect(ref.index, 0);
    });

    test('a container containing # does not truncate the index', () {
      final ref = AutoMediaId.parseTrack(AutoMediaId.track('od#d', 12))!;
      expect(ref.containerId, 'od#d');
      expect(ref.index, 12);
    });

    test('rejects malformed track ids', () {
      expect(AutoMediaId.parseTrack('sunoh:s:no-hash'), isNull);
      expect(AutoMediaId.parseTrack('sunoh:s:c#notanumber'), isNull);
      expect(AutoMediaId.parseTrack('sunoh:s:c#-1'), isNull);
      expect(AutoMediaId.parseTrack('sunoh:c:album:a:b'), isNull);
      expect(AutoMediaId.parseTrack('garbage'), isNull);
    });
  });

  group('classification', () {
    test('containers are tabs and collections, never tracks', () {
      expect(AutoMediaId.isContainer('sunoh:t:liked'), isTrue);
      expect(AutoMediaId.isContainer('sunoh:c:user:pl1:'), isTrue);
      expect(AutoMediaId.isContainer('sunoh:s:sunoh:t:liked#0'), isFalse);
      expect(AutoMediaId.isContainer('garbage'), isFalse);
    });

    test('a track id is not mistaken for a collection', () {
      // Track ids embed their container verbatim, so a naive prefix check
      // would classify a track inside a collection as a collection.
      final container = AutoMediaId.collection(kind: 'user', id: 'pl1');
      final track = AutoMediaId.track(container, 2);
      expect(AutoMediaId.isTrack(track), isTrue);
      expect(AutoMediaId.isCollection(track), isFalse);
    });
  });
}
