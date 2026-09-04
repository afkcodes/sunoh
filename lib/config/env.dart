// Every endpoint and third-party constant the app is built against.
//
// Nothing here is hardcoded in source. Values arrive at compile time from
// `--dart-define-from-file=env.json`, and `env.json` is gitignored — so the
// backend this build talks to is not committed to a public repository. See
// `env.example.json` for the shape and `README.md` for how to build.
//
// **This is configuration, not secrecy.** A `--dart-define` value is compiled
// into the APK as a constant. Anyone holding the APK can read every URL here
// with `strings`, and anyone running the app can read them off the wire with a
// proxy. That is unavoidable — the app has to know where to connect. What this
// buys is that a public repository does not carry a private base URL, and that
// a fork or a self-hoster can point the app somewhere else without editing
// code.
//
// A missing value is empty rather than a build failure. The app is built by
// contributors who have no reason to hold a production endpoint, and it
// degrades honestly: requests against an empty base fail, and the screens that
// need them already render their own error state. The on-device library and
// the YouTube tier keep working, because neither goes through sunoh-api.
class Env {
  const Env._();

  /// sunoh-api: the catalog behind Home, Search and every detail screen.
  static const apiBase = String.fromEnvironment('SUNOH_API_BASE');

  /// The public website, used to build shareable links.
  static const webBase = String.fromEnvironment('SUNOH_WEB_BASE');

  /// Where the in-app updater looks for the release manifest.
  static const updateManifest = String.fromEnvironment('SUNOH_UPDATE_MANIFEST');

  /// Community lyrics. A public API, kept configurable so a fork can point at
  /// a mirror or its own instance.
  static const lrclibBase = String.fromEnvironment('LRCLIB_BASE');

  /// Apple Music's word-timed TTML, by way of the BetterLyrics extension's
  /// backend. Keyless, and the lead source for syllable timing.
  static const betterLyricsBase = String.fromEnvironment('BETTER_LYRICS_BASE');

  /// LyricsPlus runs on volunteer mirrors that come and go, so this is a
  /// comma-separated list rather than one host — see [LyricsPlus], which asks
  /// all of them at once and remembers whichever answered.
  static const lyricsPlusMirrors = String.fromEnvironment(
    'LYRICS_PLUS_MIRRORS',
  );

  /// A public proxy in front of Apple Music's lyrics — a second, independent
  /// route to the same TTML [betterLyricsBase] carries.
  static const paxsenixBase = String.fromEnvironment('PAXSENIX_BASE');

  /// Apple Music's own catalog search, used to turn a title into the track id
  /// the proxy above wants.
  static const appleMusicApiBase = String.fromEnvironment(
    'APPLE_MUSIC_API_BASE',
  );

  /// Apple's web player. Read only to lift the bearer token its own JS bundle
  /// carries, which is the only way to query the catalog search above.
  static const appleMusicWebBase = String.fromEnvironment(
    'APPLE_MUSIC_WEB_BASE',
  );

  /// SimpMusic's community lyrics, keyed on the YouTube video id rather than
  /// on title and artist — so it cannot hand back a different edit.
  static const simpMusicLyricsBase = String.fromEnvironment(
    'SIMPMUSIC_LYRICS_BASE',
  );

  /// Musixmatch's web-client API. Line-synced, but the largest catalog here.
  static const musixmatchBase = String.fromEnvironment('MUSIXMATCH_BASE');

  /// The key Musixmatch's web player signs its requests with.
  ///
  /// Not a secret of ours to keep — it is baked into their public JavaScript
  /// bundle, and every independent Musixmatch client has read it from there.
  /// It lives in `env.json` regardless, so this repository does not itself
  /// republish another service's signing key. A build without it simply has
  /// one fewer lyrics source; see [LyricsSource].
  static const musixmatchSecret = String.fromEnvironment('MUSIXMATCH_SECRET');

  /// SponsorBlock segment lookup. Only ever sent a 4-character hash prefix.
  static const sponsorBlockBase = String.fromEnvironment('SPONSORBLOCK_BASE');

  /// Coarse IP geolocation, used once to pick a default YouTube region.
  static const geoIpBase = String.fromEnvironment('GEOIP_BASE');

  /// YouTube's InnerTube API root.
  static const ytMusicBase = String.fromEnvironment('YTMUSIC_BASE');

  /// Names of the values this build is missing, for a one-line startup log.
  /// Not fatal — see the note above about contributor builds.
  static List<String> get missing => {
    'SUNOH_API_BASE': apiBase,
    'SUNOH_WEB_BASE': webBase,
    'SUNOH_UPDATE_MANIFEST': updateManifest,
    'LRCLIB_BASE': lrclibBase,
    'BETTER_LYRICS_BASE': betterLyricsBase,
    'LYRICS_PLUS_MIRRORS': lyricsPlusMirrors,
    'PAXSENIX_BASE': paxsenixBase,
    'APPLE_MUSIC_API_BASE': appleMusicApiBase,
    'APPLE_MUSIC_WEB_BASE': appleMusicWebBase,
    'SIMPMUSIC_LYRICS_BASE': simpMusicLyricsBase,
    'MUSIXMATCH_BASE': musixmatchBase,
    'MUSIXMATCH_SECRET': musixmatchSecret,
    'SPONSORBLOCK_BASE': sponsorBlockBase,
    'GEOIP_BASE': geoIpBase,
    'YTMUSIC_BASE': ytMusicBase,
  }.entries.where((e) => e.value.isEmpty).map((e) => e.key).toList();
}
