# sunoh.

A music app for Android. It plays from YouTube Music, Gaana and Saavn behind
one interface, so you search once instead of juggling apps.

No ads, no account, no tracking. GPL-3.0.

**[Download the latest release](https://github.com/afkcodes/sunoh/releases/latest)**
— take `app-arm64-v8a-release.apk` unless your phone is 32-bit. Android 7.0+.

## Features

**Sources**

- **YouTube Music** — search, the home feed with its editorial rows, moods and
  genres, playlists, albums, and artist pages with one-tap radio. It talks to
  the same InnerTube API the official client does, not a web wrapper.
- **Gaana** and **Saavn** — trending, charts, playlists and albums, with strong
  Indian-language coverage.
- Results from all three appear in one search.

**Playback**

- [mpv](https://mpv.io) as the audio engine, via `mpv_audio_kit`.
- Gapless queue, shuffle and repeat, reorderable queue.
- **SponsorBlock** on YouTube tracks — skips sponsor reads, intros, outros and
  non-music segments. Only a short hash prefix of the video id is sent, never
  the id itself.
- Equalizer, sleep timer, and Chromecast.
- Synced lyrics via [LRCLIB](https://lrclib.net).
- Media notification with a working seekbar, and full background playback.

**Library**

- Liked songs, user playlists, recently played, and offline downloads.
- Import your playlists from Spotify.
- Podcasts and audiobooks alongside music.

**Interface**

- Dark, editorial design. The accent colour follows the album art.
- Artwork requested at full resolution throughout.
- Region and interface language for YouTube can be set by hand or detected
  from your connection.

## Build

```sh
flutter pub get
flutter run
```

Release builds, split per ABI:

```sh
flutter build apk --split-per-abi --release
```

Requires the Flutter SDK (Dart `^3.11.5`) and the Android SDK. The YouTube
extraction path is native Kotlin under
`android/app/src/main/kotlin/codes/afk/sunoh/`, so a plain `flutter run` on
Android is the only supported way to exercise it.

## Architecture

Full detail in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md); the standards
new code is held to are in [`docs/ENGINEERING.md`](docs/ENGINEERING.md).

| Path | |
|---|---|
| `lib/api/` | source clients — `ytmusic_api`, `sunoh_api`, `sponsorblock`, `lrclib` |
| `lib/audio/` | playback repository, queue, settings |
| `lib/providers/` | Riverpod providers |
| `lib/screens/`, `lib/overlays/`, `lib/player/` | UI |
| `lib/router/` | `go_router` shell routes |
| `android/.../ytmusic/` | Kotlin InnerTube bridge |
| `android/.../potoken/` | BotGuard PO token minting in a WebView |

State is Riverpod, navigation is `go_router` with a `StatefulShellRoute`, and
persistence is Hive.

YouTube stream URLs are resolved just-in-time, per track, at playback. Some
tracks require a PO token, which is minted on-device in a WebView using
Google's public BotGuard endpoint — the same approach the official web client
uses.

## Credits

- [innertubex](https://github.com/MetrolistGroup/innertubex) by MetrolistGroup,
  for the InnerTube client stack. sunoh is GPL-3.0 because it links this.
- [Metrolist](https://github.com/mostafaalagamy/Metrolist), whose approach to
  the YouTube Music home feed and PO tokens this follows.
- [SponsorBlock](https://sponsor.ajay.app) and [LRCLIB](https://lrclib.net) for
  their open APIs.

## Licence

GPL-3.0. See [`LICENSE`](LICENSE).

The licence covers the code only. It grants no rights in any third-party
media, artwork, or metadata reached through the app.

## Disclaimers

sunoh is a **non-commercial** client. It is not sold, carries no advertising,
and collects no analytics. It does not host, mirror, encode, or rights-clear
any audio, artwork, or metadata.

Everything streamable flows directly from the public upstream to your device
at playback time. A small companion service caches metadata responses only;
**no media files live on the project's infrastructure**, and nothing is
mirrored or redistributed.

All audio, cover art, names and titles are the property of their respective
rights-holders. If you are a rights-holder and want a specific reference
removed from this repository, open an issue and it will be addressed promptly.
The content itself is not stored here, so removal at the public upstream is the
durable path to it disappearing from the app.
