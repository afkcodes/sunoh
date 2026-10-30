// Loading a cover from the network, and what to do when the CDN has not got
// the size we asked for.
//
// Split from `album_art.dart`, which owns the painted placeholder and the
// squircle around it. Those change when the app's look changes; this changes
// when a CDN does — and the retry below only exists because one of them
// publishes a rendition that is usually, but not always, there.

import 'dart:io' show File;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/art_urls.dart';

/// Artwork can come from the network or, for on-device music, from a JPEG the
/// local-library scan cached on disk. Everything downstream treats artwork as
/// a single string, so the distinction is made here rather than threaded
/// through every call site.
bool _isLocalArt(String url) =>
    url.startsWith('/') || url.startsWith('file://');

ImageProvider _providerFor(String url) {
  if (!_isLocalArt(url)) return CachedNetworkImageProvider(url);
  return FileImage(
    File(url.startsWith('file://') ? Uri.parse(url).toFilePath() : url),
  );
}

/// A network cover, with the smaller renditions to fall back on.
///
/// Split out of [SunohArt.build] rather than nested in it: the retry is
/// recursive, and inlining a recursive builder in a `build()` that is already
/// doing layout, shadows and cache tiering made both jobs harder to read.
class NetworkArt extends StatelessWidget {
  const NetworkArt({
    super.key,
    required this.url,
    required this.cacheTier,
    required this.placeholder,
  });

  final String url;
  final int cacheTier;

  /// The painted art, built lazily — it is the last resort and usually never
  /// runs.
  final Widget Function() placeholder;

  @override
  Widget build(BuildContext context) => _at(artUrlChain(url), 0);

  /// The image at [i] in the chain, falling through to [i] + 1 when it will
  /// not load and to the painted art when the chain runs out.
  ///
  /// Stateless on purpose: `errorBuilder` can return a whole new [Image], so
  /// walking the chain needs no `setState` and no rebuild of anything above.
  Widget _at(List<String> chain, int i) {
    if (i >= chain.length) return placeholder();
    return Image(
      // Bypass CachedNetworkImage entirely (its placeholder fires for >=1
      // frame even on memory-cache hits -> the "flicker on nav" symptom).
      // Use raw Image with CachedNetworkImageProvider so we own the
      // placeholder logic via frameBuilder:
      //   - `wasSynchronouslyLoaded: true` -> bitmap was in Flutter's
      //     ImageCache and resolved this frame -> show it immediately,
      //     no placeholder, no flicker.
      //   - `frame != null` -> first decoded frame is ready -> show it.
      //   - otherwise -> still loading from disk/net -> painted art bridges.
      // No fade animations - direct swap, which "looks instant" when cached
      // and "loads naturally" when cold.
      image: ResizeImage(
        _providerFor(chain[i]),
        width: cacheTier,
        height: cacheTier,
        policy: ResizeImagePolicy.fit,
      ),
      fit: BoxFit.cover,
      // medium = trilinear with mipmaps; low = plain bilinear. Large art is
      // drawn well above 1:1 on the full-bleed player, and bilinear made that
      // read as soft, so it keeps mipmaps.
      //
      // Small tiles don't: they're already resized to their cache tier and
      // drawn at roughly 1:1, where trilinear is visually indistinguishable
      // from bilinear. Mipmap generation is a per-image GPU cost paid as art
      // scrolls into view, and it's disproportionately expensive on
      // tile-based (Mali) GPUs - so pay it only where it shows.
      filterQuality: cacheTier >= 720
          ? FilterQuality.medium
          : FilterQuality.low,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, wasSyncLoaded) {
        if (wasSyncLoaded || frame != null) return child;
        return placeholder();
      },
      errorBuilder: (_, _, _) => _at(chain, i + 1),
    );
  }
}
