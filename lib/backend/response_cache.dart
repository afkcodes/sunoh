// Route-level response cache for the on-device backend.
//
// Why: the server hid its expensive aggregations (/music/home fans out to ~34
// upstream requests, /podcasts/home is a fan-out too) behind Redis. On the
// phone they would run on every request, cost seconds and battery, and, for
// Gaana, risk an IP ban (see gaana/request_gate.dart). So a route can declare
// a [CachePolicy] and this cache sits between the interceptor and the handler.
//
// Behaviour per key: within `fresh` serve the copy; past it but within `stale`
// serve the copy AND refresh in the background (stale-while-revalidate, so the
// home screen opens instantly after a day away); past `stale` or missing, fetch
// and wait. Failures are never stored, and concurrent identical requests share
// one Future so two widgets asking for the home feed do not double the fan-out.
//
// Persistence is one Hive box of JSON strings so a cold start shows the last
// feed instead of waiting 2-12 s. A memory map in front avoids re-reading and
// re-decoding it. Nothing here is analytics: it is a local copy of public
// catalogue data and holds no tokens or signed URLs (those routes have no
// policy).
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import 'local_backend.dart';

/// Request header that makes the cache skip its copy and fetch (pull-to-
/// refresh, retry). The fresh result still replaces the stored one.
const localRefreshHeader = 'x-local-refresh';

class CachePolicy {
  const CachePolicy({
    required this.fresh,
    Duration? stale,
    this.persist = false,
  }) : stale = stale ?? fresh;

  /// Served without any refresh while younger than this.
  final Duration fresh;

  /// Total age up to which a copy may still be served while a refresh runs.
  /// Defaults to [fresh] (no stale window).
  final Duration stale;

  /// Also keep the copy on disk so it survives a restart.
  final bool persist;
}

class _Entry {
  _Entry(this.reply, this.at);
  final LocalReply reply;
  final DateTime at;
}

typedef BoxOpener = Future<Box<String>> Function();

class ResponseCache {
  ResponseCache({
    BoxOpener? openBox,
    DateTime Function()? clock,
    int? maxEntries,
  }) : _open = openBox ?? _openDefault,
       _now = clock ?? DateTime.now,
       _maxEntries = maxEntries ?? 40;

  static const boxName = 'local_api_cache';
  static Future<Box<String>> _openDefault() => Hive.openBox<String>(boxName);

  final BoxOpener _open;
  final DateTime Function() _now;
  final int _maxEntries;

  final Map<String, _Entry> _memory = {};
  final Map<String, Future<LocalReply>> _inflight = {};
  Future<Box<String>?>? _box;

  /// method + pattern + sorted params + sorted query. Values are URI-encoded
  /// so the key is ASCII (Hive requires it) and unambiguous.
  static String keyFor(
    String method,
    String pattern,
    Map<String, String> params,
    Map<String, String> query,
  ) {
    String join(Map<String, String> m) => (m.keys.toList()..sort())
        .map((k) => '$k=${Uri.encodeComponent(m[k]!)}')
        .join('&');
    return '$method $pattern ${join(params)}?${join(query)}';
  }

  Future<LocalReply> run(
    String key,
    CachePolicy policy,
    Future<LocalReply> Function() fetch, {
    bool refresh = false,
  }) async {
    final hit = refresh ? null : await _lookup(key, policy);
    if (hit != null) {
      final age = _now().difference(hit.at);
      if (age < policy.fresh) return hit.reply;
      if (age < policy.stale) {
        // Failure here is harmless: the copy we just returned stays usable
        // until `stale` runs out.
        _load(key, policy, fetch).then<void>(
          (_) {},
          onError: (Object e) {
            debugPrint(
              '[local-api] background refresh failed (${e.runtimeType})',
            );
          },
        );
        return hit.reply;
      }
    }
    return _load(key, policy, fetch);
  }

  Future<LocalReply> _load(
    String key,
    CachePolicy policy,
    Future<LocalReply> Function() fetch,
  ) {
    final running = _inflight[key];
    if (running != null) return running;
    final f = () async {
      final reply = await fetch();
      // A partial answer (one provider blocked) would otherwise be served as
      // the full feed for the whole fresh window; the next request retries.
      if (!reply.partial) await _store(key, policy, reply);
      return reply;
    }();
    _inflight[key] = f;
    f.whenComplete(() => _inflight.remove(key)).ignore();
    return f;
  }

  Future<_Entry?> _lookup(String key, CachePolicy policy) async {
    final mem = _memory[key];
    if (mem != null || !policy.persist) return mem;
    final box = await _boxOrNull();
    final raw = box?.get(key);
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final e = _Entry(
        LocalReply(j['d'], message: j['m'] as String, source: j['s'] as String),
        DateTime.fromMillisecondsSinceEpoch(j['t'] as int),
      );
      return _memory[key] = e;
    } catch (_) {
      // Corrupt or from an older shape: drop it and fetch afresh.
      await box!.delete(key);
      return null;
    }
  }

  Future<void> _store(String key, CachePolicy policy, LocalReply r) async {
    final now = _now();
    _memory[key] = _Entry(r, now);
    if (!policy.persist) return;
    try {
      final box = await _boxOrNull();
      if (box == null) return;
      await box.put(
        key,
        jsonEncode({
          't': now.millisecondsSinceEpoch,
          'd': r.data,
          'm': r.message,
          's': r.source,
        }),
      );
      await _evict(box);
    } catch (e) {
      // Un-encodable data or a disk error: the memory copy still works.
      debugPrint('[local-api] cache write skipped (${e.runtimeType})');
    }
  }

  /// Drop the oldest entries beyond the cap. Only parses timestamps when the
  /// box is actually over the limit.
  Future<void> _evict(Box<String> box) async {
    if (box.length <= _maxEntries) return;
    final ages = <String, int>{};
    for (final k in box.keys.cast<String>()) {
      try {
        ages[k] = (jsonDecode(box.get(k)!) as Map)['t'] as int;
      } catch (_) {
        ages[k] = 0;
      }
    }
    final oldest = ages.keys.toList()
      ..sort((a, b) => ages[a]!.compareTo(ages[b]!));
    final drop = oldest.take(box.length - _maxEntries).toList();
    await box.deleteAll(drop);
    drop.forEach(_memory.remove);
  }

  Future<Box<String>?> _boxOrNull() => _box ??= () async {
    try {
      return await _open();
    } catch (e) {
      debugPrint('[local-api] cache box unavailable (${e.runtimeType})');
      return null;
    }
  }();
}
