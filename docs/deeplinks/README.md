# Deep links

sunoh. accepts two URI shapes — both arrive through the same dispatcher
(`lib/router/deep_links.dart`):

| Custom scheme                   | App Link                                |
|---------------------------------|-----------------------------------------|
| `sunoh://album/<id>?source=…`   | `https://sunoh.online/album/<id>?source=…`   |
| `sunoh://playlist/<id>?source=…`| `https://sunoh.online/playlist/<id>?source=…`|
| `sunoh://artist/<id>?source=…`  | `https://sunoh.online/artist/<id>?source=…`  |
| `sunoh://song/<id>?source=…`    | `https://sunoh.online/song/<id>?source=…`    |
| `sunoh://search?q=…`            | `https://sunoh.online/search?q=…`            |
| `sunoh://share/<id>`            | `https://sunoh.online/share/<id>` (reserved) |

`source` is the provider hint (`saavn`, `gaana`, `spotify`) — the sunoh-api
detail endpoints route by it. `song` resolves through `/music/song/:id` and
auto-plays as a single-track queue.

## Android: enable App Links auto-verify

The intent-filter in `AndroidManifest.xml` already has
`android:autoVerify="true"`. For Android to skip the chooser sheet, the
file at `assetlinks.json` in this folder must be reachable at:

    https://sunoh.online/.well-known/assetlinks.json

Served as `application/json` with a 200 status, no redirects.

The fingerprint inside is the **release** keystore SHA-256 documented in
`~/.claude/projects/-home-ashish-oss/memory/sunoh-android-signing.md`. For
debug builds you'd add the debug keystore's SHA-256 as another entry in
the `sha256_cert_fingerprints` array — Play upload signing would add
Google's signing key fingerprint, but this app isn't going to Play Store.

## Smoke-testing locally

ADB can fire a deep link directly into the running app:

```sh
# custom scheme
adb shell am start -a android.intent.action.VIEW \
  -d "sunoh://album/abc123?source=saavn"

# App Link (won't open the app until assetlinks.json is live + verified,
# but useful to verify the intent-filter matches)
adb shell am start -a android.intent.action.VIEW \
  -d "https://sunoh.online/song/xyz789"
```

To inspect Android's verification state for the App Link:

```sh
adb shell pm get-app-links codes.afk.sunoh
```

Look for `sunoh.online: verified`.
