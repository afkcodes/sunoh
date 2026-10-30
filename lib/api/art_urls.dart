// Asking Google's image CDNs for a bigger rendition than they volunteered.
//
// Every YouTube artwork URL arrives sized for the surface InnerTube thinks is
// asking — 60px for a search row, 120 for a playlist row, 544 for an album
// header — and the client then scales it up to fill a phone screen. That is
// what made covers look blocky however large the display surface was.
//
// The sizes are part of the URL and the CDNs honour a rewrite, so the fix is
// string surgery rather than a different request. What makes it worth its own
// file is that there are three unrelated URL grammars in play and handling
// only some of them is invisible: the art still loads, just small.
//
// Split out of `ytmusic_renderers.dart` because the widget layer needs
// [artUrlChain] too, and a `part of` a private library cannot be imported.

/// Largest square dimension worth requesting.
///
/// Measured against the CDN: cover art tops out at 1200x1200 and any larger
/// request returns the identical bytes, so asking for more just makes the URL
/// look ambitious. 1200 also covers the expanded player's full-bleed artwork
/// at 3x density.
const int kMaxArtSize = 1200;

/// A video frame's native size once it stops being a thumbnail crop.
///
/// Not square, and deliberately not squared: these are 16:9 stills from music
/// videos, and forcing them to [kMaxArtSize] would claim a height the file
/// does not have.
const int _kFrameWidth = 1280;
const int _kFrameHeight = 720;

/// `=s576` — square shorthand, no modifiers.
final _square = RegExp(r'=s(\d+)');

/// `=w544-h544-l90-rj`, and the cropped avatar form `=w60-c-h60-k-c`.
///
/// The optional `-c-` is why this is one pattern and not two. Without it the
/// match failed on every channel avatar in the tree and artist rows kept the
/// 60px image InnerTube offers — the smallest thing the CDN serves, drawn at
/// list-row size on a 3x screen.
final _sized = RegExp(r'=w(\d+)(-c)?-h(\d+)');

/// `https://i.ytimg.com/vi/<videoId>/hqdefault.jpg?sqp=…&rs=…`
///
/// The video-frame CDN, which has no size parameter at all: the rendition is
/// the filename. `sqp`/`rs` are a signed crop request for that specific
/// rendition, so they are dropped rather than carried over — they would not
/// verify against a different one.
final _frame = RegExp(
  r'^(https?://i\.ytimg\.com/vi(?:_webp)?/)([A-Za-z0-9_-]{6,})/[A-Za-z0-9_]+\.(?:jpg|webp)',
);

/// `https://is1-ssl.mzstatic.com/image/thumb/.../600x600bb.jpg`
///
/// Apple's CDN (iTunes / Apple Podcasts artwork, which PodcastIndex feeds
/// often point at) takes the size as the last path segment and renders any
/// size up to the master, so the rewrite cannot 404 the way a ytimg
/// rendition can. The `bb`/`sr`/`cc` suffix is a crop mode and is kept.
final _apple = RegExp(
  r'^(https?://[^/]*mzstatic\.com/.*/)(\d+)x(\d+)([a-z-]*\.(?:jpg|png|webp))$',
);

/// Ask for a larger rendition of [url], and report the size it will now be.
///
/// The size is rewritten in place so any trailing modifiers survive, and the
/// aspect ratio comes from the URL itself rather than the JSON, so wide artist
/// banners are not squared into a portrait crop.
///
/// Returns the url plus the size it will actually be, so callers can label it
/// honestly. A label that lags the rewrite matters: `FeedItem.artwork` picks
/// the highest number in the list, so a stale one would have it choose the
/// smaller image.
/// A Gaana CDN cover asked for at `size_xxl` (see the Gaana mapper).
final _gaanaXxl = RegExp(r'gaanacdn\.com/.*/size_xxl(_\d+)?\.[a-z]+$');

(String, int?, int?) upscaleArtUrl(String url, int? width, int? height) {
  if (width != null && width >= kMaxArtSize) return (url, width, height);

  // Frames first: a ytimg URL carries no `=s`/`=w` to confuse the others, but
  // checking it first keeps the cheap regexes off the long signed query.
  final frame = _frame.firstMatch(url);
  if (frame != null) {
    return (
      '${frame.group(1)}${frame.group(2)}/maxresdefault.jpg',
      _kFrameWidth,
      _kFrameHeight,
    );
  }

  final apple = _apple.firstMatch(url);
  if (apple != null) {
    return (
      '${apple.group(1)}${kMaxArtSize}x$kMaxArtSize${apple.group(4)}',
      kMaxArtSize,
      kMaxArtSize,
    );
  }

  final square = _square.firstMatch(url);
  if (square != null) {
    return (
      url.replaceRange(square.start, square.end, '=s$kMaxArtSize'),
      kMaxArtSize,
      kMaxArtSize,
    );
  }

  final sized = _sized.firstMatch(url);
  if (sized != null) {
    final w0 = int.tryParse(sized.group(1)!) ?? 0;
    final h0 = int.tryParse(sized.group(3)!) ?? 0;
    final h = (w0 > 0 && h0 > 0)
        ? (kMaxArtSize * h0 / w0).round()
        : kMaxArtSize;
    final crop = sized.group(2) ?? '';
    return (
      url.replaceRange(sized.start, sized.end, '=w$kMaxArtSize$crop-h$h'),
      kMaxArtSize,
      h,
    );
  }

  return (url, width, height);
}

/// [url] followed by every smaller rendition to try if it will not load.
///
/// Only ytimg needs this. `maxresdefault.jpg` is the 1280x720 master and it
/// only exists when the upload was at least that big — 233 of 237 sampled
/// playlist tracks, so a real win with a real tail. Without a fallback those
/// four rows would drop straight to the painted placeholder, which is a
/// visibly worse result than the 400px frame they have today.
///
/// `sddefault` (640x480) and `hqdefault` (480x360) are 4:3 and letterbox a
/// widescreen still, which is why they are a fallback and not the first
/// choice. `hqdefault` is the one YouTube has always generated for every
/// video, so the chain ends there.
///
/// Everything else returns a single-element list: the googleusercontent forms
/// above are resizes of one stored image, so a rewritten size cannot 404 when
/// the original would not have.
List<String> artUrlChain(String url) {
  // Gaana's 1200px size_xxl, with its 800px and 400px renditions behind it
  // in case a cover was never rendered that large.
  if (_gaanaXxl.hasMatch(url)) {
    return [
      url,
      url.replaceFirst('size_xxl', 'size_xl'),
      url.replaceFirst('size_xxl', 'size_l'),
    ];
  }
  final frame = _frame.firstMatch(url);
  if (frame == null) return [url];
  final base = '${frame.group(1)}${frame.group(2)}';
  return [
    url,
    if (url != '$base/sddefault.jpg') '$base/sddefault.jpg',
    if (url != '$base/hqdefault.jpg') '$base/hqdefault.jpg',
  ];
}
