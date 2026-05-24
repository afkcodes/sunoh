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
