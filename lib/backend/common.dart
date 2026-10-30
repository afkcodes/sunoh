// Port of sunoh-api src/helpers/common.ts (+ the validators it leans on).
// Shared by the on-device provider ports; names stay as in TypeScript so the
// route code can be compared line for line.
import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// snake_case / kebab-case / PascalCase to camelCase.
String toCamelCase(String str) {
  // Two passes as in TS: capitalise the char after a separator run, then
  // lower the first char.
  final joined = str.replaceAllMapped(
    RegExp(r'[^a-zA-Z0-9]+(.)'),
    (m) => m[1]!.toUpperCase(),
  );
  return joined.isEmpty
      ? joined
      : joined[0].toLowerCase() + joined.substring(1);
}

/// Any case to "Title Case Words".
String toSentenceCase(String str) {
  final words = str
      .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .replaceAll(RegExp(r'[^a-zA-Z0-9]+'), ' ')
      .toLowerCase()
      .trim()
      .split(' ');
  return words.map(capitalizeFirstLetter).join(' ');
}

/// Last path segment, or null when the URL ends in a slash.
String? extractToken(String url) => RegExp(r'([^/]+)$').firstMatch(url)?[1];

// Saavn ships the media URL DES-ECB encrypted under this static key; it is
// public knowledge (it is in the web player's JS), not a secret.
const _desKey = '38346591';
// pointycastle has no single-DES engine. DESede with all three keys equal
// collapses (encrypt-decrypt-encrypt cancels) to plain DES, hence the key is
// repeated three times below.

const _qualities = [
  ('_12', '12kbps'),
  ('_48', '48kbps'),
  ('_96', '96kbps'),
  ('_160', '160kbps'),
  ('_320', '320kbps'),
];

/// Decrypts Saavn's `encrypted_media_url`. Returns a list of
/// `{quality, link}` maps when the URL carries a known bitrate marker,
/// otherwise the bare decrypted string (the TS union `Quality`).
Object createDownloadLinks(String encryptedMediaUrl) {
  final cipher =
      PaddedBlockCipherImpl(PKCS7Padding(), ECBBlockCipher(DESedeEngine()))
        ..init(
          false,
          PaddedBlockCipherParameters(
            KeyParameter(Uint8List.fromList(utf8.encode(_desKey * 3))),
            null,
          ),
        );
  final bytes = cipher.process(
    base64.decode(base64.normalize(encryptedMediaUrl)),
  );
  final link = utf8.decode(bytes);

  for (final (id, _) in _qualities) {
    if (link.contains(id)) {
      return [
        for (final (qid, bitrate) in _qualities)
          {'quality': bitrate, 'link': link.replaceFirst(id, qid)},
      ];
    }
  }
  return link;
}

/// The path segment before an optional trailing slash, '' when absent.
String getToken(String url) => RegExp(r'/([^/]+)/?$').firstMatch(url)?[1] ?? '';

bool isValidFunction(Object? fun) => fun is Function;

bool isValidArray(Object? arr) => arr is List && arr.isNotEmpty;

bool isValidObject(Object? obj) => obj is Map;

/// `Array.isArray` (validators.ts `isArray`).
bool isArray(Object? v) => v is List;

/// validators.ts `isEmptyArray`: false for non-arrays, as in TS.
bool isEmptyArray(Object? v) => v is List && v.isEmpty;

String capitalizeFirstLetter(String str) =>
    str.isEmpty ? str : str[0].toUpperCase() + str.substring(1);

/// Runs [fn] over [items] with at most [limit] in flight. Mirrors the TS
/// quirk that no throttling happens when `limit > items.length` (everything
/// is in flight anyway).
Future<List<R>> promiseAllLimit<T, R>(
  List<T> items,
  int limit,
  Future<R> Function(T item) fn,
) async {
  final results = <Future<R>>[];
  final executing = <Future<void>>[];
  for (final item in items) {
    final p = fn(item);
    results.add(p);
    if (limit <= items.length) {
      late final Future<void> e;
      // Errors surface through Future.wait(results) below; here we only need
      // the slot freed.
      e = p.then(
        (_) => executing.remove(e),
        onError: (_) => executing.remove(e),
      );
      executing.add(e);
      if (executing.length >= limit) await Future.any(executing);
    }
  }
  return Future.wait(results);
}

const _genericTitles = {
  'title',
  'titles',
  'untitled',
  'unknown',
  'null',
  'undefined',
  'placeholder',
  'none',
};

/// False for empty, placeholder-ish or purely numeric titles. Takes Object?
/// because upstream JSON can hand over any type.
bool isValidTitle(Object? title) {
  if (title is! String) return false;
  final trimmed = title.trim();
  if (trimmed.isEmpty) return false;
  final lower = trimmed.toLowerCase();
  if (_genericTitles.contains(lower)) return false;
  if (lower == 'untitled track' || lower == 'unknown artist') return false;
  if (RegExp(r'^\d+$').hasMatch(trimmed)) return false;
  return true;
}

const _languages = [
  'hindi',
  'punjabi',
  'tamil',
  'telugu',
  'marathi',
  'gujarati',
  'bengali',
  'kannada',
  'malayalam',
  'bhojpuri',
  'rajasthani',
  'urdu',
  'haryanvi',
];

/// First known language named in [query], or null.
String? detectLanguage(String? query) {
  if (query == null || query.isEmpty) return null;
  final lower = query.toLowerCase();
  for (final l in _languages) {
    if (lower.contains(l)) return l;
  }
  return null;
}
