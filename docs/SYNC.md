# Library sync

Keeping liked songs, playlists and settings the same across two phones, with
no account, no server of ours, and no cloud SDK in the app.

The app writes an encrypted file into a folder the user picks with the system
picker. Whatever syncs that folder — Syncthing, Nextcloud, a Drive folder —
moves it. sunoh never learns where the folder actually lives.

---

## Why not a cloud API

Google Drive sync means the Drive REST API, which means Google Sign-In, which
means Google Play Services. That would contradict "No account. No sign-in,
ever." in the README, the disclaimer and the store listing; add a second
proprietary Google dependency immediately after removing one; and take F-Droid
from a single removable blocker to two, one of which could never be removed if
sync were a core feature.

The Storage Access Framework gets the same outcome with none of that. The cost
is that sync happens when the folder syncs rather than on our schedule, which
for a music library is not a real cost.

**Unverified:** whether Google Drive specifically can be picked as a tree. Its
Android provider has historically been poor at `OPEN_DOCUMENT_TREE`. The design
works regardless with any folder-syncing app; only "Drive" as the answer
depends on it.

---

## One file per device

Each device writes `sunoh-<deviceId>.sync` and reads **every** `.sync` file in
the folder.

This is the load-bearing decision. Two devices never write the same file, so
there is no locking problem and no last-writer-clobbers — the failure mode
every "one shared JSON in a cloud folder" design hits. A third device works for
free, and a device joining later gets everything from whichever file it reads,
because each file carries the merged state after its owner last synced.

---

## Merging

`lib/sync/sync_merge.dart`. A collection is a set of records keyed by id, each
carrying when it was last touched and whether that touch was an addition or a
removal. Merging takes the newest record per id.

**Deletions have to be represented, not merely absent.** Unliking a song on one
phone removes it there; a union with the other phone puts it back, and it comes
back on both. That tombstone is the reason the whole file exists.

Rules worth knowing:

- **Ties go to the deletion.** An earlier version kept "whichever record is
  mine", so two devices merging the same pair reached opposite answers and
  wrote both back, flipping an item's state forever. Ties are same-millisecond
  coincidence; resurrection is the failure that matters.
- **Items with no record survive.** That is a library from before sync existed.
  Dropping it to fix a bookkeeping gap would be deleting the user's data to
  tidy our own.
- **Tombstones prune on a 90-day window.** They cannot be kept forever or
  dropped eagerly: a device offline longer than the window still holds the
  item, sees no tombstone, and re-adds it. The window is the honest statement
  of how long a phone can be away and still have its deletions respected.
- **Episode progress merges on furthest position**, not newest write. Resuming
  earlier than you actually reached is the annoying failure; hearing a few
  seconds twice is not.
- **User playlists merge per playlist on `updatedAt`**, not per song. Per-song
  merging needs a record per song per playlist and still would not know what to
  do about order. Losing the older of two same-playlist edits is
  understandable; a silently interleaved track order is not.

Metadata sits **beside** the collections in the `library` box rather than
inside them, so the stored shapes are exactly what they always were. Nothing
needed migrating, and a build without sync reads the same data unchanged.

---

## What syncs

Liked songs, saved albums, playlists and artists, user playlists, podcast
subscriptions, episode progress, and the appearance and playback settings.

**Deliberately excluded**, so it is a decision rather than an oversight:

| Not synced | Why |
|---|---|
| Downloads | Entries hold absolute paths meaningless on another device, and the audio is far too large. A future version could sync the *intent* and let each device fetch its own copy. |
| Playback queue and position | Per-device state. Syncing it makes two phones fight over what is playing. |
| History | Nothing is ever explicitly removed from it, so it needs no tombstones. |
| Search recents | A local convenience that carries what you typed. The last thing that should be copied into a shared folder. |

Settings sync as one blob with a single timestamp rather than per key.
Per-key merging needs a timestamp per key and a migration to add them, for a
conflict that barely arises.

---

## Encryption

AES-128-GCM, done natively in `SyncBridge.kt` with `javax.crypto`. A pub crypto
package would add a dependency for something the platform already does, and
dependency count is not free while F-Droid inclusion is open.

The key is generated once, shown to the user as a recovery code, and entered on
the second device. It is never sent anywhere and cannot be recovered — the
screen says so rather than burying it. A fresh random IV per write matters more
than usual here: the same library is re-encrypted on every change, so a fixed
IV would leak which parts changed between two versions sitting in the cloud.

GCM authenticates, so a file written with a different key fails cleanly rather
than decrypting to garbage. That is what lets a shared folder hold an unrelated
setup's files without either one importing the other's rubbish.

---

## Failure handling

Everything degrades quietly, because a folder behind a cloud client is
routinely half-written, unmounted or revoked:

- A file that will not decrypt is skipped, not an error.
- A file that will not parse is skipped. One bad file must not fail the sync.
- A file from a newer format version is skipped rather than partially imported.
- A revoked folder grant becomes a state the UI describes and offers to fix,
  not an exception.
- Settings arriving in a payload are filtered against an allow-list. The file
  comes out of a directory the user controls, so it is treated as untrusted
  input rather than as our own data coming home.

---

## Layout

| Path | |
|---|---|
| `lib/sync/sync_merge.dart` | Records, tombstones, merge rules. No Flutter import; the most-tested file here. |
| `lib/sync/sync_payload.dart` | The document format and the N-way fold. |
| `lib/sync/sync_service.dart` | Read, merge, apply, write. |
| `lib/sync/sync_channel.dart` | Dart side of the bridge. |
| `android/.../sync/SyncBridge.kt` | SAF folder access and AES-GCM. |
| `lib/screens/sync_screen.dart` | Setup, recovery code, status. |

---

## Status

Built and unit-tested; **not yet verified on two real devices**. The merge
rules have 13 tests covering the cases a two-phone setup actually produces, but
the round trip through a real synced folder — two phones, one folder, edits on
both — has not been run.
