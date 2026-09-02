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
    'SPONSORBLOCK_BASE': sponsorBlockBase,
    'GEOIP_BASE': geoIpBase,
    'YTMUSIC_BASE': ytMusicBase,
  }.entries.where((e) => e.value.isEmpty).map((e) => e.key).toList();
}
