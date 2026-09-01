// What library sync is allowed to carry off this device.
//
// Sync writes an encrypted file into a folder a cloud client uploads. That is
// the right home for playlists and preferences and a catastrophic one for a
// credential, so the boundary is pinned here rather than left to whoever edits
// the allow-list next.
//
// These tests fail loudly if a future key slips in. That is the point: the
// mistake they guard against is one careless line, and it would not look
// wrong.

import 'package:flutter_test/flutter_test.dart';
import 'package:sunoh/audio/settings_store.dart';

void main() {
  group('sync allow-list', () {
    test('carries only appearance and playback preferences', () {
      // Namespaces, not a list of keys — a new appearance setting should not
      // have to come back here, and a new namespace should.
      for (final key in SyncSettings.syncableKeys) {
        expect(
          key.startsWith('appearance.') || key.startsWith('playback.'),
          isTrue,
          reason: '$key is outside the namespaces sync is allowed to carry',
        );
      }
    });

    test('carries nothing to do with a signed-in account', () {
      // The YouTube session is a Google cookie: whoever holds it can act as
      // the user. It lives in Keystore-encrypted storage on the device and
      // must never enter the settings box that sync uploads.
      const forbidden = [
        'cookie',
        'auth',
        'account',
        'session',
        'token',
        'sapisid',
        'credential',
        'password',
        'visitor',
      ];
      for (final key in SyncSettings.syncableKeys) {
        for (final word in forbidden) {
          expect(
            key.toLowerCase().contains(word),
            isFalse,
            reason: '$key looks like a credential and must not sync',
          );
        }
      }
    });

    test('carries nothing describing this particular device', () {
      // Folder choices, download paths and the sync configuration itself are
      // meaningless or harmful on another phone.
      const deviceOnly = ['local.', 'sync.', 'downloads.', 'search.'];
      for (final key in SyncSettings.syncableKeys) {
        for (final prefix in deviceOnly) {
          expect(
            key.startsWith(prefix),
            isFalse,
            reason: '$key is per-device and must not sync',
          );
        }
      }
    });

    test('the allow-list is not empty', () {
      // Otherwise the tests above pass by saying nothing.
      expect(SyncSettings.syncableKeys, isNotEmpty);
    });
  });
}
