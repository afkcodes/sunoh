# Engineering standards

The bar for code in this repository. These are rules, not suggestions — but
every one of them is a means to an end, and the ends are, in priority order:

1. **The app stays at 60 fps on a mid-range Android phone.**
2. **A failure in one feature never takes down playback.**
3. **The next person to open the file understands why, not just what.**

Where a rule and one of those goals conflict, the goal wins and the rule gets
amended in the same PR.

---

## 1. Performance first

sunoh. targets budget and mid-range Android hardware, much of it on tile-based
(Mali/Adreno) GPUs. Performance is a design constraint, not a later pass.

### 1.1 The frame budget is 16 ms

Anything in a `build()` method runs on every frame it rebuilds. In `build()`,
**never**: allocate a list you could hoist, sort or filter a collection, parse
a string, format a date, or construct a `TextStyle` from scratch in a loop.
Hoist to a `static const`, a field, or a memoized provider.

### 1.2 Blur is banned in scrolling surfaces

`BackdropFilter` over scrolling content re-rasterizes every frame and is the
single most GPU-dependent primitive available. It was removed from the bottom
bar and replaced with an opaque bar plus a 24 px gradient scrim; the toast blur
was replaced with a solid `#141418`. Both changes were invisible and both
removed a per-frame framebuffer read-back.

Do not reintroduce `BackdropFilter` anywhere content scrolls behind it. If a
design genuinely needs frosted glass, it goes on a static, non-scrolling
surface, and the PR states the measured cost.

### 1.3 Lists must be lazy

Any list that can exceed roughly 20 items uses `ListView.builder`,
`ListView.separated`, `GridView.builder`, or a sliver. A `Column` with a
`for` loop over an API response builds and lays out every element, including
the thousand off-screen ones.

There are around 55 eager `for`-loop list constructions in `screens/` and
`overlays/` today. Do not add more; convert the ones you touch.

Bounded, known-small lists — a 3-item tab bar, a 5-row settings section — may
stay eager.

### 1.4 Rebuild the smallest possible subtree

`AppState` is one `ChangeNotifier` covering the player, settings, and the whole
library. `ref.watch(appStateProvider)` therefore rebuilds a screen when a
*toast fires* or *a like is toggled elsewhere*.

- Prefer `ref.watch(appStateProvider.select((s) => s.someField))`. There are
  currently zero `.select()` calls in the codebase and 150 bare watches — this
  is the highest-leverage perf change available, and it is cheap per site.
- Use `Consumer` or a small `ConsumerWidget` to scope the rebuild to the part
  of the tree that actually depends on the value.
- Values that change more than a few times a second do **not** go through
  `notifyListeners()`. Use a `ValueNotifier` and a `ValueListenableBuilder`.
  `AppState.position` already does exactly this via `positionTick` — copy that
  pattern.

### 1.5 Isolate expensive layers

Wrap a subtree in `RepaintBoundary` when it repaints on a different cadence
from its neighbours — the bottom bar does this so it never repaints with the
feed scrolling beneath it. `CustomPaint` gets `isComplex: true` and
`willChange: false` when its output is static, as the generated album art does.

Rasterize once, reuse many: the album-art grain is a single 96x96 tile drawn
once and tiled as a shader, replacing a per-pixel `drawCircle` loop.

### 1.6 Do not block the first frame

New startup work is fire-and-forget with a timeout unless playback genuinely
cannot proceed without it. See `ARCHITECTURE.md` section 2 for the three
stages. Anything touching the network, a WebView, or Play Services belongs in
stage 2 or 3.

### 1.7 Measure, do not guess

A PR claiming a performance improvement states what was measured and how —
DevTools timeline, a frame chart, or a before/after number. "Should be faster"
is not a justification, and neither is "this looks expensive."

---

## 2. File and function size

**Hard limits.** CI-enforceable, no exceptions without a written reason in the
file header:

| Unit | Limit |
|---|---|
| File | 400 lines |
| Widget `build()` method | 60 lines |
| Any other function | 40 lines |
| Class | 250 lines |
| Positional parameters | 3 (use named beyond that) |
| Nesting depth in `build()` | 5 |

Nineteen files currently exceed 400 lines, four of them exceed 1000. Those are
listed in `ARCHITECTURE.md` section 9.

**The rule for existing files: leave it smaller than you found it.** You are
not required to fix `detail_screens.dart` to change one row in it. You are
required not to grow it — if your change adds more than about 40 lines to a
file already over the limit, extract something first.

**How to split a screen.** Not by arbitrary line count, but along these seams,
in order of preference:

1. **A distinct screen** goes in its own file. `podcast_show_screen.dart` was
   correctly carved out of `detail_screens.dart`; the artist and occasion
   screens still need the same treatment.
2. **A reusable widget** goes in `widgets/`. If two screens render it, it is
   not screen-private.
3. **A private sub-widget** stays in the file only while the file is under the
   limit. Past that it moves to a sibling `_parts.dart` or its own file.
4. **Logic** — anything that is not widget construction — moves out of the
   screen entirely, into a provider, a store, or a plain Dart class.

**Never split by mechanical line count** (`foo_part1.dart`). If there is no
conceptual seam, the file has a design problem that splitting will hide.

---

## 3. Architecture rules

### 3.1 Dependencies point downward

`api/` imports nothing from `state/` or UI. `audio/` imports no screen.
`providers/` is composition only — if a provider body is more than a few lines
of wiring, the logic belongs in a class it calls.

`api/` and `data/` should not import `package:flutter/material.dart`. Needing a
`Color` or `Duration` is not a reason to; needing a widget means the code is in
the wrong layer.

### 3.2 One concern per class

`AppState` is the counter-example, not the model. New cross-cutting state gets
its own notifier or store. Do not add a sixth responsibility to `AppState` —
if you are tempted, that is the signal to extract the fifth.

The target decomposition, for when it gets done: `PlayerState`,
`LibraryState`, `SettingsState`, `SpotifyImportState`, `CastState`.

### 3.3 Isolate policy in testable classes

Behaviour with rules — when to skip a segment, when to refresh a URL, when to
prime autoplay — lives in its own class with no Flutter dependency, so it can
be tested without a widget tree. `SponsorBlockSkipper` and `UrlRefreshScheduler`
are the models here.

### 3.4 Navigation is typed

Screens call methods on the `SunohNav` extension. No hand-built path strings
in a screen; no `context.push('/home/album/$id')`. Add a method to the
extension instead, so the branch prefix stays correct.

### 3.5 Design tokens are the only source of colour and type

Every colour comes from `SunohColors`, every text style from `SunohType`, every
rounded corner from `squircleBorder` / `squircleDecoration` / `squircleClip`.

A raw `Color(0xFF…)` outside `theme/tokens.dart` or `widgets/album_art.dart`
is a bug. So is a bare `TextStyle(...)`, a `BorderRadius.circular` on a card,
or a Material icon where the app uses Solar (Phosphor for transport controls
only).

Density-aware padding multiplies by `density.scale`. It applies to vertical
padding and gaps only — never to font size or card dimensions.

---

## 4. Failure handling

The app talks to four third-party catalogs, a Cast SDK, a WebView bot-check,
and Google Play Services. Everything is allowed to fail.

- **Degrade, do not crash.** A failed section renders as absent, not as an
  error screen. A failed optional subsystem logs one line and disables one
  feature.
- **Never let a third party block playback.** SponsorBlock, lyrics, analytics,
  and artwork palette extraction are all fire-and-forget. If a lookup could
  make the user wait for audio, it is wired wrong.
- **Parse defensively.** Every upstream accessor tolerates a missing or
  reshaped key. This is not optional for InnerTube, whose renderer tree changes
  without notice.
- **Catch narrowly.** `on DioException` rather than bare `catch`. A swallowed
  exception carries a comment saying what is being swallowed and why —
  `catch (_) { }` with no comment is not acceptable.
- **No silent `null` returns from a failure path** that the caller will treat
  as "no data." Either log it or make the failure explicit in the return type.

---

## 5. Comments and documentation

This codebase's comments are its best feature. Keep the standard.

- **Document the why, never the what.** `// increment i` is noise.
  `// mpv reports a mid-stream drop as eof, not error` is the reason the next
  person does not "simplify" the branch away.
- **Record rejected alternatives.** When you chose B over A, say so and say
  why. The `BackdropFilter` removal, the `phosphor_flutter` swap, and the
  `flutter_native_splash` dependency placement are all comments that prevent a
  future regression.
- **Every non-obvious constant gets a sentence.** Why 3 tracks, why 280 ms,
  why a 60-second buffer.
- **Every file opens with a header** stating what it owns and any constraint a
  reader needs before line 1.
- **Load-bearing comments are code.** If you change the behaviour, change the
  comment in the same commit. A stale comment is worse than none.
- `dartdoc` (`///`) on every public class and method; `//` for internal notes.

---

## 6. Dart and Flutter practice

- `const` constructors everywhere they are valid — with one caveat this repo
  learned the hard way: a `const` widget that must react to a notifier can have
  its subtree reconciliation short-circuited. `MiniPlayer()` is deliberately
  non-const for this reason, and says so.
- Prefer `StatelessWidget` and `ConsumerWidget`. Reach for `StatefulWidget`
  only for animation controllers, focus nodes, text controllers, or genuinely
  local UI state.
- Dispose everything: controllers, focus nodes, stream subscriptions, timers.
  A `late final AnimationController` needs a matching `dispose()`.
- Prefer composition to inheritance. Widget subclasses of widget subclasses are
  a smell.
- Use sealed classes, records, and exhaustive `switch` expressions. The codebase
  already uses records for provider family keys (`({String id, String? source})`) —
  keep that.
- Name booleans as predicates: `isPlaying`, `hasExpired`, `shouldRefresh`.
- No `dynamic` where a type is knowable. `Map<String, dynamic>` at an API
  boundary is fine; `dynamic` in a signature is not.
- `async`/`await` over raw `.then()`. Mark intentional fire-and-forget with
  `unawaited(...)` so it is visibly deliberate rather than a missing await.

---

## 7. Logging

Ninety raw `print(` calls currently ship in release builds. New code does not
add to that.

- Use `debugPrint`, which is release-stripped and rate-limited, not `print`.
- The existing `// ignore: avoid_print` + `print` pattern in `main.dart` and the
  audio layer is intentional — those lines must survive to logcat for
  field diagnosis of startup and playback. Do not extend that exemption to new
  code without a reason.
- Prefix every log with its subsystem in brackets: `[audio]`, `[ytmusic]`,
  `[downloads]`, `[deeplink]`. Grep-ability is the point.
- Never log a token, a signed URL, a full video id, or anything from
  `google-services.json`.

---

## 8. Privacy

The app has no accounts and no user identity, and that is a feature. Protect it.

- Do not add a network call that transmits anything identifying. SponsorBlock's
  4-character hash prefix is the standard to hold: send the minimum that makes
  the feature work.
- Analytics is opt-out and must stay that way. Events carry no free-text user
  content beyond the existing search-term event, and no ids that could
  reconstruct a listening history off-device.
- New third-party SDKs need a stated justification. Each one is a tracking
  surface and an APK-size cost.

---

## 9. Testing

There is no `test/` directory. That is the largest gap in the project and the
reason large refactors feel risky.

The order to fix it in, highest value first:

1. **Pure logic, no Flutter.** `SponsorBlockSkipper`, `UrlRefreshScheduler`,
   `StreamResolver`'s tier ladder and quality picker, `lrc_parser`, the
   autoplay dedup key, `FeedItem.displaySubtitle`. These are fast, stable, and
   already isolated enough to test today.
2. **Stores**, against an in-memory Hive box: round-trip and corruption-recovery
   for each of the four.
3. **DTO parsing**, against captured real responses for each source. This is
   where upstream shape changes will bite.
4. **Widget tests** for the design system — that tokens resolve, that density
   scales padding and not type.

New pure-logic classes ship with tests. Bug fixes in logic ship with a test
that fails before the fix.

---

## 10. Before you commit

- `flutter analyze` reports nothing you introduced. There are exactly three
  known-failing issues today — the `onReorder` deprecations tracked in
  `ARCHITECTURE.md` section 9. Anything beyond those three is yours to fix.
  When they are migrated, this becomes a flat zero and this note goes away.
- Formatting: **do not run `dart format .` across the repo.** This codebase
  predates Dart 3.11's "tall style" formatter, and a repo-wide run rewrites 89
  of 92 files, burying every real diff. Format only the files you touched
  (`dart format lib/path/you/edited.dart`), or land the whole-repo migration
  as its own commit that changes nothing else. That migration is worth doing
  once, deliberately, on a quiet branch — it is not worth doing accidentally
  inside a feature PR.
- No file you touched grew past 400 lines.
- No new raw `print`, no new `BackdropFilter` over scrolling content, no new
  eager list over ~20 items, no new raw colour or `TextStyle`.
- Comments explaining any non-obvious decision you made are in the diff.
- `ARCHITECTURE.md` is updated if you changed a structure it describes.
- The commit message says why, not just what. No AI or tool attribution.

---

## 11. Amending this document

These standards describe a target, and parts of the codebase predate them.
That is expected and fine. What is not fine is quietly ignoring a rule.

To change a rule: change it here, in a commit that says why, alongside the code
that motivated it.
