# Distribution

Where sunoh can be installed from, what each route needs, and what is blocking
the ones that are not done.

The three routes have very different bars. Obtainium needs nothing from us,
IzzyOnDroid needs a request, and F-Droid needs the app to stop depending on
proprietary libraries. They are listed in that order.

---

## Obtainium — works today

[Obtainium](https://github.com/ImranR98/Obtainium) installs directly from
GitHub Releases and checks for updates itself. Nothing needs to be published or
approved: a user adds the repo URL and Obtainium does the rest.

```
https://github.com/afkcodes/sunoh
```

Requirements it places on us, all currently met:

- Releases are public, tagged `vX.Y.Z`, and not drafts or prereleases.
- Each release carries APKs as assets.
- The APKs are signed with a stable key, so updates install over each other.

`scripts/release.sh` attaches the three per-ABI splits **and** the universal
APK. Obtainium picks the split matching the device and falls back to the
universal one for anything else.

---

## IzzyOnDroid — needs a request

[IzzyOnDroid](https://apt.izzysoft.de/fdroid/) is an F-Droid-compatible
repository that mirrors APKs from GitHub Releases rather than building from
source. That distinction is the whole reason it is the realistic next step:
**no build recipe, no reproducibility work, and the app can keep its
proprietary dependencies** — they are declared as anti-features instead of
being disqualifying.

### What is already in place

- `fastlane/metadata/android/en-US/` — title, short and full descriptions,
  icon and six phone screenshots, in the layout their scraper reads.
- Public GPL-3.0 source with tagged releases.
- A universal APK per release, so there is one unambiguous artifact to mirror.

### What the request needs

Open an issue at [gitlab.com/IzzyOnDroid/repo](https://gitlab.com/IzzyOnDroid/repo/-/issues)
with:

| Field | Value |
|---|---|
| Package id | `codes.afk.sunoh` |
| Repository | `https://github.com/afkcodes/sunoh` |
| Licence | GPL-3.0 |
| Release format | GitHub Releases, tag `vX.Y.Z`, universal `app-release.apk` |
| Signing cert SHA-256 | `2cfa78b2819415529f21b4ef07193769ee8527af20001b5f7729d1f43c8df6e8` |

The fingerprint is what pins the repository to *our* signing key, so a
compromised release cannot substitute a differently-signed APK. It is a public
value, derivable from any published APK:

```sh
apksigner verify --print-certs app-release.apk
```

### Expect one anti-feature label

IzzyOnDroid runs every APK through [Exodus](https://reports.exodus-privacy.eu.org/)
and labels what it finds. With Firebase removed there is **no tracker left to
find**; the scan should come back clean.

One label remains likely: **NonFreeDep**, for Google Play Services, pulled in
by the Cast SDK. It does not block inclusion — it appears on the listing —
and stating it in the request is better than having it discovered.

---

## F-Droid — blocked on proprietary dependencies

F-Droid's main repository **builds from source on their own infrastructure**
and does not accept proprietary dependencies at all. That is a harder bar than
IzzyOnDroid's, and sunoh does not currently clear it.

### What is blocking it

Exactly one dependency, now that Firebase is gone.

| Dependency | Pulls in | Used for |
|---|---|---|
| `flutter_chrome_cast` | `com.google.android.gms:play-services-cast-framework` | Chromecast |

It is a closed-source Google library, and it cannot ship in an F-Droid build
however optional it is at runtime — the objection is to the library being in
the APK, not to whether it executes. Verified against the built APK: the only
`com.google.android.gms` packages left are `cast`, `auth`, `common`, `dynamite`
and `flags`, all pulled in by that one plugin.

### What inclusion would cost

**Chromecast.** There is no way to keep casting and be in F-Droid's main
repository: the Cast protocol requires Google's SDK, and the open
reimplementations do not handle the authenticated handshake current Chromecast
firmware demands.

### The options

1. **IzzyOnDroid only.** Costs nothing, keeps every feature, and is where most
   people looking for an F-Droid-compatible repo will find it.
2. **Both, with a `foss` flavour.** F-Droid gets a build without casting;
   GitHub and IzzyOnDroid keep the full one. Gradle flavours plus stubbing the
   plugin out of the Dart build, and two variants to keep working from then on.
3. **Drop Cast entirely.** One build everywhere, simplest to maintain, and
   F-Droid becomes straightforward. Costs casting for everyone.

This is a product decision, not a technical one, and it should be made before
any flavour work starts. Removing Firebase was the cheap half — it cost a
feature nobody uses deliberately. Cast is the half that costs something real.
