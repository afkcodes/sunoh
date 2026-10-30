// Burst protection for gaana.com / apiv2.gaana.com.
//
// Why: Gaana's firewall bans an IP for ~10 minutes ("403 Access Denied", an
// HTML page) after roughly 60+ requests in a few seconds. A cold /music/home
// sends 31. The server hid that behind one shared egress IP and a cache; on a
// phone the ban lands on the user's own connection and breaks Gaana for them.
// So every Gaana request passes through this gate: at most [maxInFlight] at
// once, at most [maxStartsPerSecond] starts in any rolling second, and after a
// ban page is seen, calls fail fast for [cooldown] instead of prolonging it.
import 'dart:async';

import 'package:flutter/foundation.dart';

class GaanaGate {
  GaanaGate({
    this.maxInFlight = 4,
    this.maxStartsPerSecond = 10,
    this.cooldown = const Duration(minutes: 2),
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final int maxInFlight;
  final int maxStartsPerSecond;
  final Duration cooldown;
  final DateTime Function() _now;

  int _inFlight = 0;
  final List<DateTime> _starts = [];
  DateTime? _coolUntil;
  Completer<void>? _slotFree;

  // Waiters take their turn one at a time so the limits are checked in order.
  Future<void> _turn = Future.value();

  bool get coolingDown {
    final until = _coolUntil;
    if (until == null) return false;
    if (_now().isBefore(until)) return true;
    _coolUntil = null;
    return false;
  }

  /// Called when Gaana answered with its ban page.
  void tripped() {
    if (coolingDown) return;
    _coolUntil = _now().add(cooldown);
    debugPrint(
      '[gaana] blocked by Gaana (403); pausing its requests for '
      '${cooldown.inMinutes} min',
    );
  }

  /// Runs [task] under the limits, or returns null without running it when
  /// Gaana is in cooldown (checked again after queueing, so requests already
  /// waiting when the ban arrives do not each hit it once more).
  Future<T?> run<T>(Future<T> Function() task) async {
    if (coolingDown) return null;
    final prev = _turn;
    final mine = Completer<void>();
    _turn = mine.future;
    try {
      await prev;
      while (_inFlight >= maxInFlight) {
        await (_slotFree ??= Completer<void>()).future;
      }
      await _smooth();
      if (coolingDown) return null;
      _inFlight++;
    } finally {
      mine.complete();
    }
    try {
      return await task();
    } finally {
      _inFlight--;
      final w = _slotFree;
      _slotFree = null;
      if (w != null && !w.isCompleted) w.complete();
    }
  }

  Future<void> _smooth() async {
    const window = Duration(seconds: 1);
    _starts.removeWhere((t) => _now().difference(t) >= window);
    if (_starts.length >= maxStartsPerSecond) {
      final wait = window - _now().difference(_starts.first);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
      _starts.removeWhere((t) => _now().difference(t) >= window);
    }
    _starts.add(_now());
  }
}

/// The one gate every Gaana call shares.
GaanaGate gaanaGate = GaanaGate();
