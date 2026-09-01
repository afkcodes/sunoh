// The signed-in YouTube account, as app state.
//
// Signing in is not a setting — it changes what every YouTube request returns,
// so the feeds have to be thrown away and re-fetched on both sign-in and
// sign-out. That invalidation is the reason this is a notifier rather than a
// bare FutureProvider: something has to own the "and now refetch everything"
// step, and doing it at each call site would mean forgetting it at one.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../api/yt_auth_channel.dart';
import '../api/ytmusic_api.dart';
import 'ytmusic_provider.dart';

class YtAuthController extends ChangeNotifier {
  YtAuthController(this._ref, {YtAuthChannel? channel})
    : _channel = channel ?? YtAuthChannel.instance;

  final Ref _ref;
  final YtAuthChannel _channel;

  YtAccount _account = YtAccount.signedOut;
  YtAccount get account => _account;

  bool get isSignedIn => _account.signedIn;

  bool _busy = false;
  bool get isBusy => _busy;

  /// Read the stored session. Safe to call repeatedly.
  Future<void> restore() async {
    _account = await _channel.state();
    notifyListeners();
    // A session with no name yet is one that has never been confirmed against
    // YouTube — either it was just created, or the name lookup failed last
    // time. Asking again is cheap and doubles as a liveness check.
    if (_account.signedIn && _account.name.isEmpty) {
      await _refreshName();
    }
  }

  Future<bool> signIn() async {
    if (_busy) return false;
    _busy = true;
    notifyListeners();
    try {
      final ok = await _channel.signIn();
      if (!ok) return false;
      _account = await _channel.state();
      await _refreshName();
      _invalidateFeeds();
      return true;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    if (_busy) return;
    _busy = true;
    notifyListeners();
    try {
      await _channel.signOut();
      _account = YtAccount.signedOut;
      _invalidateFeeds();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Ask YouTube who this is, and keep the answer.
  ///
  /// A null answer is not treated as a failed sign-in. It means only that the
  /// name could not be read — a renderer moved, the call timed out, the
  /// account has no display name — and none of that says the cookie cannot
  /// authenticate. An earlier version signed out here, which turned a parsing
  /// bug into a session that appeared to sign in and then silently undid
  /// itself, with the row still reading "Sign in".
  ///
  /// The session stays; the row says "Signed in" without a name.
  Future<void> _refreshName() async {
    final name = await _ref.read(ytMusicApiProvider).accountName();
    if (name == null) {
      debugPrint('[ytauth] signed in, but could not read the account name');
      return;
    }
    await _channel.setAccountName(name);
    _account = YtAccount(
      signedIn: true,
      name: name,
      visitorData: _account.visitorData,
    );
    notifyListeners();
  }

  /// Every YouTube feed is now answering for a different identity.
  void _invalidateFeeds() {
    _ref.invalidate(ytMusicHomeProvider);
    _ref.invalidate(ytMusicLibraryProvider);
  }
}

final ytAuthProvider = ChangeNotifierProvider<YtAuthController>(
  (ref) => YtAuthController(ref)..restore(),
);
