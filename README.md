# sunoh.

A quiet, editorial music-streaming app — Flutter implementation of the Claude
Design prototype (`sunoh.html`). Streams music, podcasts, and audiobooks
with a premium, dark-editorial feel.

## What's built

All screens from the design, reachable from the bottom nav + top tabs:

- **Home** — greeting, `Music / Podcasts / Audiobooks` top tabs, recent grid,
  editorial picks, daily mixes, new releases, artists, and a "Tonight" hero.
- **Podcasts** — continue listening, subscriptions, top-this-week.
- **Search** — live filtering across songs/artists/albums/podcasts, recent
  queries, and genre tiles.
- **Library** — filter chips, sort, list/grid toggle, pinned tiles.
- **Album / Playlist / Artist / Podcast** detail pages.
- **Player** — mini player + expanded player with three layouts
  (`Classic / Minimal / Immersive`), draggable scrubber, pull-to-dismiss.
- **Queue** (reorderable) and karaoke **Lyrics** (auto-scroll highlight).
- **Tweaks** sheet (tap the ⚙ on Home): theme mode, accent, tint-from-artwork,
  player layout, type pairing, density.

## Design system

- **Type**: Geist (UI), Instrument Serif (editorial moments), Geist Mono (data)
  — loaded at runtime via `google_fonts`, no bundled font files.
- **Album art**: deterministic, image-free generated covers. Each id hashes
  into a palette + one of eight shape compositions, painted on a canvas
  (`lib/widgets/album_art.dart`).
- **Theme**: dark (default) / light, with a single warm accent and an optional
  album-tinted background.

## Architecture

- `lib/data/` — models + the fictional catalog.
- `lib/state/app_state.dart` — a single `ChangeNotifier` (Provider) holding
  tweaks, navigation, and the player state machine.
- `lib/theme/tokens.dart` — colors, accents, typography.
- `lib/widgets/`, `lib/screens/`, `lib/player/`, `lib/overlays/`, `lib/shell/`.

## Run

```sh
flutter pub get
flutter run            # any connected device, or:
flutter run -d chrome  # web
```

Dependencies are unpinned to current majors (`google_fonts`, `provider`); run
`flutter pub upgrade` to refresh.

## Sources & disclaimers

`sunoh.` is a **personal, non-commercial project** built for a couple of
private users and intentionally not distributed through any app store. It is
a thin client that surfaces content from publicly available APIs and
open-source repositories. It does not host, mirror, encode, decode, or
rights-clear any audio, artwork, or metadata.

Every piece of streamable content flows directly from the public upstream to
the device at playback time. The companion proxy that the app talks to
lightly caches metadata responses on a small private server for the
project's own devices, but **no media files of any kind live on the
project's infrastructure**. Nothing is persisted, mirrored, or
redistributed.

### Copyright

All audio, cover art, names, titles, and related metadata are the property
of their respective rights-holders. The project does not claim ownership of
any third-party content. No commercial use is made of any of it; the app is
not sold, advertised, or made publicly available.

If you are a rights-holder and would like a specific reference removed from
this repository, please open an issue on GitHub and it will be addressed
promptly. The underlying content itself is not stored here — removal at the
public upstream is the durable path to it disappearing from the app.

### Code license

The code in this repository is the original work of the authors and is
licensed separately from any third-party content it references. See
`LICENSE` for the source-code terms. The license covers the code only; it
does not grant any rights in third-party media or APIs accessed through it.

