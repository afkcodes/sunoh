# sunoh.

A quiet, editorial music-streaming app — Flutter implementation of the Claude
Design prototype (`sunoh.html`). Streams music, radio, and podcasts with a
premium, dark-editorial feel.

## What's built

All screens from the design, reachable from the bottom nav + top tabs:

- **Home** — greeting, `Music / Radio / Podcasts` top tabs, recent grid,
  editorial picks, daily mixes, new releases, artists, and a "Tonight" hero.
- **Radio** — on-air hero, a draggable FM **dial** (87–108 MHz) with station
  pins, saved stations, and category tiles.
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

`sunoh.` is a **personal, non-commercial project** built for two private users
and intentionally not distributed through any app store. It is a thin client
that surfaces content from publicly accessible APIs and open-source services
— it does not host, mirror, encode, decode, or rights-clear any audio,
artwork, or metadata.

Every piece of streamable content flows directly from its upstream source to
the device at playback time:

| Surface | Upstream | Hosted by |
|---|---|---|
| Music search / streaming | JioSaavn, Gaana (public HTTP APIs) | Their respective owners |
| Spotify playlist import | Spotify Web API + Spotify embed page | Spotify; matched against Saavn for playback |
| Podcasts | [PodcastIndex.org](https://podcastindex.org) (open directory) | The respective podcast publishers |
| Internet radio | [radio-browser.info](https://www.radio-browser.info/) catalogue, surfaced via the open-source [`sunoh-radio`](https://github.com/afkcodes/sunoh-radio) proxy | The respective broadcasters |
| Audiobooks | [cozyaudiobooks.com](https://cozyaudiobooks.com) (a community WordPress site) | cozyaudiobooks.com and the original rights-holders |

The companion API ([`sunoh-api`](https://github.com/afkcodes/sunoh-api))
proxies and lightly caches these upstream calls on a small private VPS for
the project owner's own devices. It does **not** persist or redistribute any
audio. No media files of any kind live on the project's servers.

### Copyright

All audio, cover art, artist names, episode titles, chapter audio, and
related metadata are the property of their respective rights-holders. The
project does not claim ownership of any third-party content. No commercial
use is made of any of it; the app is not sold, advertised, or made publicly
available.

If you are a rights-holder and would like content removed from a surface of
this app:

1. **For the underlying content** — please contact the upstream source listed
   in the table above (Saavn, Spotify, PodcastIndex, radio-browser.info,
   cozyaudiobooks.com). Removing content there removes it from this app
   automatically since nothing is mirrored locally.
2. **For a specific reference in this repository** — open an issue on the
   GitHub repo and the relevant reference will be removed promptly.

### Code license

The code in this repository is the original work of the authors and is
licensed separately from the third-party content it references. See `LICENSE`
for the source-code terms. The license covers the code only; it does not
grant any rights in third-party media or APIs accessed through it.

