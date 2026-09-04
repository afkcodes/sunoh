# Architecture

How sunoh. is put together, and why. This describes the app as it is, not as
it is planned to be. When you change the shape of something described here,
update this file in the same commit.

Companion documents:

- [`ENGINEERING.md`](ENGINEERING.md) — the standards all new code is held to.
- [`deeplinks/README.md`](deeplinks/README.md) — inbound URI schema.
- [`../README.md`](../README.md) — what the app does, for users.

---

## 1. The shape

```
                        ┌──────────────────────────────────────┐
   UI                   │ screens/  overlays/  player/         │
                        │ shell/    widgets/   theme/          │
                        └───────────────┬──────────────────────┘
                                        │ Riverpod
                        ┌───────────────┴──────────────────────┐
   State                │ state/app_state.dart   providers/    │
                        │ (ChangeNotifier)       (Future/TTL)  │
                        └───────┬───────────────────────┬──────┘
                                │                       │
          ┌─────────────────────┴─────┐     ┌───────────┴───────────────────┐
   Domain │ audio/audio_repo.dart     │     │ api/ sunoh_api  ytmusic_api   │
          │ audio/audio_handler.dart  │     │     lyrics/     sponsorblock  │
          └─────────────┬─────────────┘     └───────────┬───────────────────┘
                        │                               │
          ┌─────────────┴─────────────┐     ┌───────────┴───────────────────┐
   Edge   │ mpv (mpv_audio_kit)       │     │ api/stream_resolver.dart      │
          │ audio_service, Cast SDK   │     │   └→ MethodChannel → Kotlin   │
          │ Hive boxes                │     │        InnerTube + PO token   │
          └───────────────────────────┘     └───────────────────────────────┘
```

| Path | Owns |
|---|---|
| `lib/api/` | Source clients and DTOs. No Flutter imports. |
| `lib/audio/` | Playback engine, queue, downloads, persistence stores. |
| `lib/cast/` | Google Cast session and device picker. |
| `lib/data/` | Domain models plus the legacy placeholder catalog. |
| `lib/providers/` | Riverpod wiring. Thin: composition only, no logic. |
| `lib/router/` | `go_router` config, nav extension, deep-link dispatch. |
| `lib/screens/` `lib/overlays/` `lib/player/` `lib/shell/` | UI. |
| `lib/services/` | Update checker. |
| `lib/sync/` | Library sync across devices via a user-picked folder. See [`SYNC.md`](SYNC.md). |
| `lib/state/` | `AppState` — the player and library state machine. |
| `lib/theme/` | Design tokens, light and dark. The only place raw colours are defined. |
| `lib/widgets/` | Shared, screen-agnostic widgets. |
| `android/.../ytmusic/` | Kotlin InnerTube stream resolution. |
| `android/.../potoken/` | BotGuard PO-token minting in a WebView. |

**Dependency rule.** Dependencies point downward only. `api/` must never
import from `state/` or any UI directory; `audio/` must never import a
screen. `AppState` imports `api/` and `audio/`, never the reverse. The one
deliberate exception is `audio/` importing `LoopMode` from `state/app_state.dart`,
which is a shared enum and should eventually move to `data/`.

---

## 2. Startup

`main()` is staged so that **playback works as early as possible and nothing
optional can block it.**

1. **Blocking, cheap.** Hive init, `MpvAudioKit.ensureInitialized()`,
   `StreamResolver`, `DownloadManager.init()`, `SunohAudioHandler`, `AudioRepo`.
   After this line the app can play audio.
2. **Fire-and-forget.** The Cast SDK and `audio_service` (behind a hard 5 s
   timeout) are launched unawaited. Each is wrapped so a failure degrades one
   feature rather than the app: no Play Services means no Cast, a failed
   `AudioService.init` means no lockscreen controls. In-app playback survives
   both.
3. **Post-first-frame.** Deep-link wiring, YouTube region detection, and the
   PO-token WebView prewarm run from `addPostFrameCallback` so the router has
   built its initial route first.

`SunohAudioServiceBridge` may attach *after* a queue was already restored, so
`attachBridge` re-announces the current queue rather than assuming it is first.

**When you add a startup dependency**, it goes in stage 2 or 3 unless playback
genuinely cannot proceed without it.

---

## 3. State

State management is deliberately two-tier.

**`AppState` (`ChangeNotifier`, surfaced via `ChangeNotifierProvider`)** holds
what is long-lived and cross-screen: the player state machine, user settings,
the library (likes, saved collections, history, user playlists), Spotify
import, and Cast wiring.

**Riverpod `FutureProvider.autoDispose.family`** holds everything network-backed.
Cache lifetime is explicit per resource, expressed as `ref.keepAlive()` plus a
delayed `link.close()`:

| Provider | TTL | Why |
|---|---|---|
| `homeFeedProvider` | 30 min | Editorial rows, change slowly. |
| `albumProvider` / `playlistProvider` | 30 min | Stable content. |
| `searchProvider` | 5 min | Typed queries turn over fast. |
| `occasionsProvider` / `trendingSearchProvider` | 1 h | Near-static. |
| `languagesProvider` | 24 h | Effectively constant. |
| `audiobookDetailProvider` | 24 h | Avoids 50 round-trips per category scroll. |
| `ytMusicHomeProvider` | session | Large response, not autoDispose. |

Family keys carry the provider hint (`({String id, String? source})`) so a
Saavn album and a Gaana album sharing an id do not collide.

**The high-frequency tick is isolated.** `AppState.position` writes to a
`positionTick` `ValueNotifier` and does **not** call `notifyListeners()`. The
scrubber and mini player listen to that notifier directly. This is the pattern
to copy for any value that updates more than a few times a second.

---

## 4. Navigation

`StatefulShellRoute.indexedStack` with three branches — Home, Search, Library —
each with its own `GlobalKey<NavigatorState>` and its own state-preserving
navigator.

Detail routes are **duplicated into every branch** through a shared
`_detailRoutes()` factory. That is what keeps the mini player and bottom nav
visible while an album is open, and what makes Back return to the tab you
started from. Adding a detail screen means adding one entry to that factory,
not three.

The expanded player, queue, and lyrics are modal routes on the **root**
navigator, layered above the shell.

Navigation is typed. Screens call `context.openRef(...)`, `context.openYtArtist(...)`,
`context.openSection(...)` from the `SunohNav` extension in `router.dart`,
which resolves the active branch prefix. **Do not call `context.push` with a
hand-built path string from a screen** — add a method to the extension.

Two guards worth knowing:

- A top-level `redirect` bounces any path outside `/home`, `/search`,
  `/library`, `/player` to `/home`. Android hands `sunoh://playlist/abc` to
  go_router as bare path `/abc` before the deep-link dispatcher sees it;
  without the redirect that surfaces the error page.

---

## 5. Playback

The queue is handed to **mpv's internal playlist** rather than advanced
manually. That buys native auto-advance, gapless via
`setPrefetchPlaylist(true)`, and native shuffle and loop.

Each playlist entry is a placeholder URI, `sunoh-song://<id>`. mpv's `on_load`
hook resolves it to a real URL at the moment of opening. **Signed URLs are
therefore never persisted and never resolved early.**

```
AudioRepo.playQueue(songs, i)
   └→ SunohAudioHandler.setQueue        → mpv openAll([sunoh-song://…])
        └→ on_load hook fires per entry → StreamResolver.resolve(song)
             └→ real URL + optional headers → mpv opens the stream
```

`SunohAudioHandler` owns mpv and the audio session; `AudioRepo` is the thin
layer the UI drives, and is responsible for OS metadata (`MediaItem`),
SponsorBlock dispatch, and persistence. The queue mirror is rebuilt reactively
from mpv's playlist stream, never written directly — mpv is the source of
truth for order and current index.

### Stream resolution ladder

`api/stream_resolver.dart`, in strict order, first hit wins:

0. **Local download** — skipped when `network: true` (the Cast receiver
   cannot reach the phone's `file://` paths).
1. **YouTube** — native channel. Bails immediately on failure; no other tier
   can serve a YouTube id.
2. **Resolver cache** — with a 60 s pre-expiry safety buffer.
3. **Inline `mediaUrls`** — zero round-trips, skipped on `forceRefresh`.
4. **`/music/song/:id`** — also the source of enriched metadata.
5. **`/music/song/:id/stream`** — Gaana re-sign, last resort.

Podcasts branch out at step 4 to `/podcasts/episode/:id`, because `/music/song/`
returns 400 for podcast ids.

### Signed-URL expiry

Two layers, in `audio/url_refresh.dart`:

- **Pre-emptive** — the expiry is parsed out of the resolved URL and a refresh
  is scheduled about 5 minutes ahead of it.
- **Reactive** — mpv reports a mid-stream network drop as `eof`, not `error`.
  An `eof` at `position < duration - 3 s` is treated as premature and triggers
  the same refresh.

Both swap the entry with `player.replace(currentIndex, media)`, which re-fires
`on_load`. A 2-minute throttle prevents loops when the API issues short-lived
URLs.

### Restore

Two ordering hazards, both guarded, both easy to reintroduce:

- `_restoreInProgress` suppresses persistence during `restore()`. `prepareQueue`
  emits a track-change event *before* mpv has loaded the file, so persisting at
  that moment writes position 0 over the saved seek target.
- `_pendingStartPosition` is keyed by song id. `openAll(index: N)` loads index 0
  first and only then jumps to N, so an unkeyed pending seek would be consumed
  by the wrong track.

---

## 6. YouTube Music

The split between Dart and Kotlin is driven by one fact: **`/youtubei/v1/player`
is BotGuard-gated for the music catalog; `/search` and `/browse` are not.**

- **Search and browse: Dart** (`api/ytmusic_api.dart`). Plain unauthenticated
  `WEB_REMIX` requests. No reason to cross a platform channel.
- **Stream resolution: Kotlin** (`android/.../ytmusic/YtMusicBridge.kt`).
  Needs a PO token minted by running Google's obfuscated BotGuard JS in a real
  WebView, which Dart cannot do. Uses MetrolistGroup's `innertubex` — this is
  why the app is GPL-3.0.

SABR is explicitly refused, so the result is always a plain `googlevideo.com`
URL mpv can open rather than a POST/protobuf channel it cannot.

The returned URL is signed against the client that minted it, so
`ResolvedStream.httpHeaders` carries the matching User-Agent into mpv's
`http-header-fields`. That property is **written even when empty**, because it
is global to the player — a leftover YouTube User-Agent breaks the next
Saavn track.

InnerTube responses are a deeply nested, positional renderer tree. Every
accessor in `ytmusic_api.dart` is defensive by design: an upstream shape change
should cost one missing row, never an exception.

---

## 6a. Android Auto

The car never renders our Flutter UI. Android Auto connects to the exported
`MediaBrowserService` that `audio_service` already provides, walks a tree of
`MediaItem`s, and draws its own driver-distraction-compliant screens from them.
So everything reachable in the car is expressed as MediaItems, in
`audio/auto_browse.dart`.

Three things are required, and all three are load-bearing:

1. `res/xml/automotive_app_desc.xml` claiming the `media` capability.
2. The `com.google.android.gms.car.application` meta-data pointing at it.
   Without this the app is invisible in the car, however correct the service is.
3. `playFromMediaId` / `playFromSearch` in the session's `systemActions`.
   Without them the car draws the tree but tapping a row does nothing.

**Root**: the library first — Downloads, Liked Songs, Recently Played,
Playlists — then the three home feeds, Music, Podcasts and Audiobooks, mirroring
the phone's Home tabs. Downloads leads deliberately: a car is where the network
drops mid-song, and downloaded tracks are the only tier that survives it.

**Feeds** (`audio/auto_feeds.dart`) address sections by position, not heading:
headings are server-supplied free text, unstable between requests, and routinely
contain the colons and hashes the id format uses as separators.

**Layout is uniform list, everywhere.** Home sections interleave collections and
songs; hinting browsable content as a grid makes the car render collections as
full-width artwork tiles between compact song rows, and the list visibly
stutters between two row heights. Nodes opt into a grid only where their
children are all one kind.

**A row that cannot be routed is dropped, and a section of only such rows is
not listed at all.** Upstream adds item types without notice — an unhandled one
renders as blank space in the car, which reads as a network failure with no way
to tell. That guard is also how the gaps get found: `/music/home` carries
`radio_station` and `channel` rows, and until both were handled the filter was
quietly hiding four whole sections.

**Radio stations are playable rows, not browsable ones.** A station has no
track list to open, so making the driver drill in to reach a play button is the
interaction Android Auto asks apps to avoid. They also cannot be addressed by
id alone: Saavn's quick-stations ship an empty `id` and key off the name, so
the seed FeedItem has to survive to the tap. Stations are therefore indexed
against a container's *seeds* (`sunoh:x:<container>#<index>`), separately from
the songs in the same container, which form the queue.

**Media ids** are the whole contract, defined once in `audio/auto_media_id.dart`
and never built by hand. `playFromMediaId` arrives with an id and nothing else,
possibly in a fresh process, so the id carries everything needed to rebuild
what the user tapped: `sunoh:s:<container>#<index>` addresses a track *by
position in its container*, so tapping row four of a playlist starts that
playlist at row four rather than playing one orphaned song.

**Everything must resolve cold.** The MediaBrowserService is a foreground
service Android restarts independently of the Flutter UI, and Android Auto
remembers the user's browse position across reconnects — so it will ask for a
collection whose parent this process never served. Any browse path that
depends on an in-memory cache being warm renders as empty in the car and
nowhere else. `test/auto_browse_test.dart` pins this case.

**Failure is always empty, never a throw.** An exception out of a browse
callback surfaces as a hard error in the car and can wedge the browse stack;
an empty list is recoverable by backing out.

---

## 7. Persistence

Four Hive boxes, opened lazily, each with the same cold-start shape:
`isBoxOpen` check, `openBox`, and on corruption `deleteBoxFromDisk` then retry.

| Box | Store | Contents |
|---|---|---|
| `playback` | `PlaybackStateStore` | Queue, index, position, source label and ref. |
| `settings` | `SettingsStore` | Namespaced keys: `appearance.*`, `playback.*`, `search.*`, `privacy.*`, `updates.*`. |
| `library` | `LibraryStore` | Likes, saved collections, history, user playlists, subscriptions, episode progress. |
| `downloads` | `DownloadStore` | Offline entries and their state. |

Writes are tiered: `persistAll()` serializes the whole queue and is called on
track change, queue mutation, and lifecycle pause. `persistCurrentPosition()`
is a single-key write, called at most every 5 seconds.

---

## 8. Cross-cutting behaviours

**Endless autoplay** primes when at most 3 tracks remain after the current one
— not on the last track, which left the round-trip no headroom. Results are
deduped three ways, including a normalized `title | primary artist | duration`
key that catches `"Gehra Hua"` versus `"Gehra Hua (From \"Dhurandhar\")"`.
`wasPlaying` and the original queue length are captured before the fetch so a
user who paused mid-flight is not force-restarted.

**SponsorBlock** sends only a 4-character SHA-256 prefix of the video id.
Policy — which categories count, minimum segment length, not re-skipping a
segment the user deliberately seeks back into — lives entirely in
`audio/sponsorblock_skipper.dart`.

**Cast** makes the phone a remote control: the receiver fetches the URL itself
and mpv goes silent. `AudioRepo` routes transport commands to whichever backend
currently owns playback.

**Deep links** run two paths — `app_links` for the real dispatch, and the
router redirect described in section 4 as a safety net. The dispatcher is
deliberately tolerant: an unknown path becomes a toast, never a crash, because
links arrive from untrusted sources.

---

## 9. Known debt

Tracked honestly so it is not rediscovered. See `ENGINEERING.md` for the
standards these violate.

| Item | Where | Impact |
|---|---|---|
| `AppState` is 2440 lines and owns six unrelated concerns | `state/app_state.dart` | Hard to test, hard to reason about, every screen watching it rebuilds on any change. |
| Oversized files | 19 files above 500 lines; `detail_screens.dart` at 1793 | Navigation and review cost. |
| Placeholder catalog still live | `data/catalog.dart`, seeded in the `AppState` constructor; parallel `_DummyQueueBody` in `queue_screen.dart` | Two rendering paths for one screen; fictional data reachable in production. |
| Thin test coverage | only `test/auto_browse_test.dart` + `test/auto_media_id_test.dart` (30 tests) | The Android Auto surface is covered; the rest of the app is not. |
| `.select()` never used | 150 `ref.watch` call sites, 0 selects | Whole screens rebuild on unrelated `AppState` changes. |
| 90 raw `print(` calls | across `lib/` | Ships log noise in release builds. |
| Compile-time base URL | `api/client.dart` | No runtime environment switch. |
| Saavn artist radio 400s server-side | `/music/radio/<stationId>` | The whole "Recommended Artist Stations" shelf. The car falls back to `/music/recommend`; the **phone does not**, so its radio tiles still fail. Fix belongs in sunoh-api. |

**The `onReorder` migration is done.** All three sites are on `onReorderItem`
and `flutter analyze` reports nothing. The two conventions that made it
non-mechanical now live in `state/reorder.dart` rather than in comments:

- `movedItem` takes `onReorderItem`'s already-adjusted index, so
  `AppState.reorderQueue` and `AppState.moveSongInUserPlaylist` no longer
  carry their own `List.insert` correction.
- `mpvMoveTarget` puts the adjustment *back*, because mpv's
  `playlist-move from to` wants a before-removal index — which is what
  `AppState.apiReorderUpNext` had been relying on the old callback for.

`test/reorder_test.dart` drives both through the framework's own adjustment
rule for every drag on a five-item list, so the pair is checked against what
`ReorderableList` actually does rather than against a restatement of it.
