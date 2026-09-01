// The signed-in YouTube session, as seen from Dart.
//
// Dart never holds the cookie. It asks the native side for the headers of one
// request and forgets them: the credential stays in the Keystore-backed store
// on the other side of the channel, and the SAPISIDHASH covers a timestamp, so
// a header set is only good for one call anyway.
//
// Every method degrades to "signed out" rather than throwing. Being signed in
// is an enhancement to a client that works fine without one, and no failure
// here should be able to take out the anonymous path.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What the app knows about the signed-in account. Nothing here is secret.
class YtAccount {
  const YtAccount({
    this.signedIn = false,
    this.name = '',
    this.visitorData = '',
  });

  final bool signedIn;

  /// Display name, empty until it has been asked for. Shown in Settings so
  /// there is never any doubt about which account the home feed belongs to.
  final String name;

  /// Pins requests to one identity. Needed in the request context as well as
  /// in a header, which is why it comes back to Dart at all.
  final String visitorData;

  static const signedOut = YtAccount();
}

class YtAuthChannel {
  YtAuthChannel._();
  static final YtAuthChannel instance = YtAuthChannel._();

  static const MethodChannel _channel = MethodChannel('codes.afk.sunoh/ytauth');

  bool get _supported => defaultTargetPlatform == TargetPlatform.android;

  Future<YtAccount> state() async {
    if (!_supported) return YtAccount.signedOut;
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>('state');
      if (raw == null) return YtAccount.signedOut;
      return YtAccount(
        signedIn: raw['signedIn'] == true,
        name: (raw['accountName'] ?? '').toString(),
        visitorData: (raw['visitorData'] ?? '').toString(),
      );
    } on PlatformException catch (e) {
      debugPrint('[ytauth] state failed: ${e.code}');
      return YtAccount.signedOut;
    }
  }

  /// Opens Google's sign-in page. False when the user backed out, which is a
  /// normal outcome and not an error.
  Future<bool> signIn() async {
    if (!_supported) return false;
    try {
      return await _channel.invokeMethod<bool>('signIn') ?? false;
    } on PlatformException catch (e) {
      debugPrint('[ytauth] signIn failed: ${e.code}');
      return false;
    }
  }

  Future<void> signOut() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('signOut');
    } on PlatformException catch (e) {
      debugPrint('[ytauth] signOut failed: ${e.code}');
    }
  }

  /// Headers for one authenticated InnerTube call. Empty when signed out, in
  /// which case the caller sends what it always sent.
  Future<Map<String, String>> headers() async {
    if (!_supported) return const {};
    try {
      final raw = await _channel.invokeMapMethod<String, String>('headers');
      return raw ?? const {};
    } on PlatformException catch (e) {
      debugPrint('[ytauth] headers failed: ${e.code}');
      return const {};
    }
  }

  Future<void> setAccountName(String name) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('setAccountName', {'name': name});
    } on PlatformException catch (e) {
      debugPrint('[ytauth] setAccountName failed: ${e.code}');
    }
  }
}
