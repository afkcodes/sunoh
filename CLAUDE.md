# CLAUDE.md

Working agreement for this repository. Read `docs/ARCHITECTURE.md` before
changing structure, and `docs/ENGINEERING.md` before writing code. This file
is the short version and the trap list.

## What this is

`sunoh.` — a Flutter/Dart Android music app fronting YouTube Music, Gaana and
Saavn behind one interface, plus podcasts and audiobooks. No accounts, no ads,
no tracking beyond opt-out analytics. GPL-3.0 (it links MetrolistGroup's
`innertubex`).

Android is the only supported target. The YouTube path is native Kotlin, so
`flutter run` on a real Android device is the only way to exercise it —
web and desktop builds cannot resolve YouTube streams.

## Commands

```sh
flutter pub get
flutter run                                  # Android device or emulator
flutter analyze                              # see "Before finishing" below
dart fix --apply                             # mechanical lint fixes
dart format lib/path/you/touched.dart        # NOT `dart format .` — see below
flutter build apk --split-per-abi --release
```

There is no test suite yet. See `docs/ENGINEERING.md` section 9 for the order
to build one in.

## Priorities, in order

1. 60 fps on a mid-range Android phone.
2. A failure in any one feature never takes down playback.
3. The next reader understands why, not just what.

## The rules that get broken most

- **Performance is a design constraint, not a later pass.** No `BackdropFilter`
  over scrolling content. Lists past ~20 items are lazy (`.builder` /
  `.separated` / slivers). Nothing allocates, sorts, parses or formats inside
  `build()`.
- **400 lines per file, 60 per `build()`, 40 per function.** Nineteen files
  currently exceed this; they are listed in `ARCHITECTURE.md` section 9. You
  are not required to fix them, but **leave every file smaller than you found
  it** — if your change adds more than ~40 lines to an over-limit file, extract
  something first. Split along conceptual seams, never by line count.
- **Design tokens only.** Every colour from `SunohColors`, every text style
  from `SunohType`, every corner from `squircleBorder`/`squircleDecoration`/
  `squircleClip`. A raw `Color(0xFF…)` or bare `TextStyle` outside
  `lib/theme/tokens.dart` is a bug. Icons are Solar, except transport controls
  which are Phosphor Fill.
- **Dependencies point downward.** `api/` never imports `state/` or UI.
  `audio/` never imports a screen. `providers/` is wiring only.
- **Navigation is typed.** Use the `SunohNav` extension in `router/router.dart`.
  Never hand-build a path string in a screen.
- **Comments record why, including rejected alternatives.** This codebase's
  comments are its best feature. Match the density. A load-bearing comment is
  code — if the behaviour changes, the comment changes in the same commit.
- **`debugPrint`, not `print`**, for new code. Prefix with the subsystem:
  `[audio]`, `[ytmusic]`, `[downloads]`, `[deeplink]`.

## Traps

Things that look wrong and are not. Do not "fix" these without reading the
comment above them first.

- **`MiniPlayer()` is deliberately not `const`.** A `const` widget let Flutter
  compare identical references and short-circuit subtree reconciliation, which
  broke its subscription to `appStateProvider`.
- **mpv reports a mid-stream network drop as `eof`, not `error`.** The
  premature-EOF branch in `audio_handler.dart` exists for exactly that.
- **`http-header-fields` is written even when empty.** The property is global
  to the player, so a leftover YouTube User-Agent would 403 the next Saavn
  track.
- **`_restoreInProgress` and `_pendingStartPosition` guard real ordering bugs.**
  `prepareQueue` emits a track-change event before mpv loads the file, and
  `openAll(index: N)` loads index 0 first. Removing either guard silently
  corrupts resume position.
- **The router's catch-all `redirect` to `/home` is load-bearing.** Android
  hands `sunoh://playlist/abc` to go_router as bare path `/abc` before the
  deep-link dispatcher sees it.
- **`AppState.position` writes to a `ValueNotifier`, not `notifyListeners()`.**
  That is what keeps the 1 Hz tick from rebuilding every watching screen. Copy
  this pattern for any high-frequency value.
- **`flutter_native_splash` sits in `dependencies`, not `dev_dependencies`,**
  on purpose — see the comment in `pubspec.yaml`. It breaks the release build
  otherwise.
- **`phosphor_icons`, not `phosphor_flutter`.** The latter subclasses
  `IconData`, which Flutter 3.43 made final.
- **The three `onReorder` call sites do not share index semantics.**
  `apiReorderUpNext` passes `newIndex` through unadjusted because mpv's
  `playlist-move` matches `onReorder`'s convention; the other two apply the
  `List.insert` correction themselves. Do not blanket-migrate them to
  `onReorderItem` — see `ARCHITECTURE.md` section 9.

## Known debt

Do not be surprised by it, do not add to it. Full table in `ARCHITECTURE.md`
section 9.

`AppState` is 2440 lines across six concerns. Nineteen files exceed 400 lines.
The fictional placeholder catalog (`data/catalog.dart`) is still seeded in the
`AppState` constructor and `queue_screen.dart` still carries a parallel dummy
rendering path. There are no tests, zero `.select()` calls against 150 bare
`ref.watch` sites, and 90 raw `print` calls.

## Conventions

- `pubspec.yaml` is the dependency ADR log. Every dependency carries a comment
  explaining why it is there and what it cost. Add one when you add a package.
- Hive keys are namespaced by concern: `appearance.*`, `playback.*`, `search.*`,
  `privacy.*`, `updates.*`.
- Never log or transmit a token, a signed URL, or a full video id. The
  SponsorBlock 4-character hash prefix is the privacy standard to hold.
- Never write the section-sign character. Write "section 3.5".

## Commits

- Commit only when asked. Branch first if on `main`.
- The message says why, not just what.
- **No AI or tool attribution anywhere** — not in commit messages, PR bodies,
  code comments, or docs. No `Co-Authored-By` trailer, no generated-with
  footer. The work is authored as the repository owner's own.

## Before finishing

`flutter analyze` reports nothing you introduced — there are exactly three
known-failing issues (the `onReorder` deprecations above) and nothing else.
Only the files you touched formatted — **never `dart format .`**, which
rewrites 89 of 92 files because the repo predates Dart 3.11's tall-style
formatter. No file grown past 400 lines. No new
`print`/`BackdropFilter`/eager-long-list/raw-colour. Comments explaining
non-obvious decisions present. `ARCHITECTURE.md` updated if you changed a
structure it describes.

The rules above are enforced where they can be: `analysis_options.yaml`
carries the lint set, including `prefer_const_constructors`,
`cancel_subscriptions`, `close_sinks`, and `use_decorated_box`. Two more
(`unawaited_futures`, `avoid_dynamic_calls`) are staged with their unblocking
condition written into that file.
