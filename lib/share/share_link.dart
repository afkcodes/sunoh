// Share helpers — all entry points (track menu, hero menu, detail header,
// player, lyrics) funnel here so the link format stays consistent.
//
// We share the `https://sunoh.online/<kind>/<id>?source=…` form rather than
// the `sunoh://` custom scheme because:
//   - it works inside web previews / browsers / messengers that won't preview
//     custom schemes;
//   - on a phone with the app installed + assetlinks verified, Android opens
//     it directly in sunoh. via App Links — no chooser sheet;
//   - on any other surface it gracefully degrades to a normal web URL.
//
// Path schema mirrors `lib/router/deep_links.dart`:
//   /album/<id>     /playlist/<id>     /artist/<id>     /song/<id>

import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

const String _kBaseUrl = 'https://sunoh.online';

/// Build the canonical share URL for a piece of content.
///
/// `?source=…` is omitted for saavn (the backend default) so the typical
/// share URL stays clean — `https://sunoh.online/album/abc` rather than
/// `…/album/abc?source=saavn`. Non-default providers (gaana/spotify) still
/// need the hint, otherwise the API tries saavn with the wrong id.
String buildSunohShareUrl({
  required String kind,
  required String id,
  String? source,
}) {
  final s = source?.toLowerCase();
  final q = (s == null || s.isEmpty || s == 'saavn')
      ? ''
      : '?source=${Uri.encodeQueryComponent(s)}';
  return '$_kBaseUrl/${Uri.encodeComponent(kind)}/${Uri.encodeComponent(id)}$q';
}

/// Hand off a link to the OS share sheet. `title` and `subtitle` shape the
/// body of the share payload; the recipient app decides how to render it
/// (most show subject + URL).
Future<void> shareSunohLink({
  required String kind,
  required String id,
  required String title,
  String? subtitle,
  String? source,
}) async {
  final url = buildSunohShareUrl(kind: kind, id: id, source: source);
  final label = subtitle == null || subtitle.isEmpty
      ? title
      : '$title — $subtitle';
  // `Listen on sunoh.` framing keeps the share consistent across kinds and
  // gives the recipient a hint about what they're opening before they tap.
  final text = 'Listen on sunoh.: $label\n$url';
  try {
    await SharePlus.instance.share(
      ShareParams(text: text, subject: label),
    );
  } catch (e, st) {
    // The share sheet itself can throw in obscure cases (no installed
    // target apps, user cancels with a platform that surfaces an error,
    // etc.). Failing loudly here would make Share feel broken; swallow +
    // log so the user just sees nothing happen.
    debugPrint('[share] failed for $url: $e\n$st');
  }
}
