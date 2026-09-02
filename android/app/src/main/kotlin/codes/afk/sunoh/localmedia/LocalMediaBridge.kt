package codes.afk.sunoh.localmedia

import android.content.ContentUris
import android.content.Context
import android.database.ContentObserver
import android.database.Cursor
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.media.MediaMetadataRetriever
import android.os.Build
import android.provider.MediaStore
import android.util.Log
import java.io.File
import java.io.FileOutputStream

/**
 * The device's own music, read from MediaStore and handed to Dart.
 *
 * ## Why this lives in Kotlin
 *
 * MediaStore is a ContentResolver API with no Dart equivalent, and the
 * available wrapper packages have a poor track record against new Android
 * releases — exactly the trap `pubspec.yaml` records for `phosphor_flutter`.
 * The query itself is small and stable, so it is cheaper to own than to
 * depend on. This follows the same bridge shape as `YtMusicBridge`.
 *
 * ## Album art
 *
 * Art is resolved once per *album*, not per song, and cached as a JPEG in the
 * app's cache directory. A library of 2000 tracks typically has a few hundred
 * albums, so this turns thousands of thumbnail decodes into a few hundred, and
 * none at all on a rescan. Dart receives a plain file path it can hand to
 * `Image.file`; songs whose album has no art get null and fall back to the
 * app's generated cover.
 *
 * `loadThumbnail` is the only supported path on Android 10+; below that the
 * album-art column still exists and is cheaper, so both are used.
 */
object LocalMediaBridge {
    private const val TAG = "LocalMediaBridge"

    /** Ignore anything shorter than this — notification tones, voice memo blips. */
    private const val MIN_DURATION_MS = 20_000L

    private const val ART_DIR = "local_album_art"
    private const val ART_SIZE = 512

    /** See [observeChanges] for why a copy needs settling time. */
    private const val CHANGE_DEBOUNCE_MS = 1_000L

    /**
     * Fires when the device's audio collection changes, so music copied onto
     * the phone shows up without a pull-to-refresh.
     *
     * Debounced, because a file copy is not one notification: MediaStore emits
     * per row, and a folder of forty tracks would otherwise queue forty scans
     * of the entire library. One rescan a second after things go quiet is what
     * the user actually wants.
     */
    private var observer: ContentObserver? = null

    fun observeChanges(context: Context, onChanged: () -> Unit) {
        if (observer != null) return
        val handler = Handler(Looper.getMainLooper())
        val debounce = Runnable { onChanged() }
        val obs = object : ContentObserver(handler) {
            override fun onChange(selfChange: Boolean, uri: Uri?) {
                handler.removeCallbacks(debounce)
                handler.postDelayed(debounce, CHANGE_DEBOUNCE_MS)
            }
        }
        context.contentResolver.registerContentObserver(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            true,
            obs,
        )
        observer = obs
        Log.i(TAG, "watching MediaStore for changes")
    }

    fun stopObserving(context: Context) {
        observer?.let { context.contentResolver.unregisterContentObserver(it) }
        observer = null
    }

    /**
     * Every audio file MediaStore considers music, newest first.
     *
     * Returns plain maps rather than a typed model because the only consumer
     * is a MethodChannel, which flattens to maps anyway.
     */
    fun scan(context: Context): List<Map<String, Any?>> {
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.ALBUM_ID,
            MediaStore.Audio.Media.ARTIST_ID,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.DATA,
            MediaStore.Audio.Media.TRACK,
            MediaStore.Audio.Media.YEAR,
            MediaStore.Audio.Media.DATE_ADDED,
            // GENRE arrived in API 30 and minSdk is 24, so it is asked for
            // only where it exists. Querying a column the platform does not
            // have throws rather than returning null.
            *(
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    arrayOf(MediaStore.Audio.Media.GENRE)
                } else {
                    emptyArray()
                }
            ),
        )

        // IS_MUSIC excludes ringtones, alarms and notifications, which
        // otherwise flood a library with three-second files.
        val selection =
            "${MediaStore.Audio.Media.IS_MUSIC} != 0 AND " +
                "${MediaStore.Audio.Media.DURATION} >= ?"
        val args = arrayOf(MIN_DURATION_MS.toString())
        val order = "${MediaStore.Audio.Media.DATE_ADDED} DESC"

        val out = ArrayList<Map<String, Any?>>()
        // Album id -> resolved art path (or null when the album has none).
        // Held across the whole scan so each album is resolved at most once.
        val artByAlbum = HashMap<Long, String?>()

        val cursor: Cursor? = context.contentResolver.query(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            projection,
            selection,
            args,
            order,
        )

        if (cursor == null) {
            Log.w(TAG, "MediaStore query returned no cursor")
            return emptyList()
        }

        cursor.use { c ->
            val idCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val titleCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val artistCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val albumCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
            val albumIdCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM_ID)
            val artistIdCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST_ID)
            val durationCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
            val dataCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
            val trackCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media.TRACK)
            val yearCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media.YEAR)
            val addedCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_ADDED)
            // getColumnIndex, not OrThrow: absent below API 30 by design.
            val genreCol = c.getColumnIndex(MediaStore.Audio.Media.GENRE)

            while (c.moveToNext()) {
                val id = c.getLong(idCol)
                val path = c.getString(dataCol)
                // A row whose file is gone is a stale MediaStore entry — common
                // after an SD card swap. Playing one is a guaranteed failure, so
                // drop it rather than surface a track that cannot start.
                if (path.isNullOrEmpty() || !File(path).exists()) continue

                val albumId = c.getLong(albumIdCol)
                // Album art first, then the file's own embedded picture. A
                // track MediaStore never indexed art for is common with loose
                // files, and falling back means they show a cover instead of
                // the painted placeholder.
                val art = artByAlbum.getOrPut(albumId) {
                    albumArtPath(context, albumId) ?: embeddedArtPath(context, albumId, path)
                }

                out.add(
                    mapOf(
                        "id" to id.toString(),
                        "title" to (c.getString(titleCol) ?: "Unknown"),
                        "artist" to (c.getString(artistCol) ?: ""),
                        "album" to (c.getString(albumCol) ?: ""),
                        "albumId" to albumId.toString(),
                        "artistId" to c.getLong(artistIdCol).toString(),
                        // Dart works in seconds everywhere; MediaStore in ms.
                        "durationSec" to (c.getLong(durationCol) / 1000).toInt(),
                        "path" to path,
                        "track" to c.getInt(trackCol),
                        "year" to c.getInt(yearCol),
                        "dateAdded" to c.getLong(addedCol),
                        "genre" to (
                            if (genreCol >= 0) c.getString(genreCol) else null
                        ),
                        "artPath" to art,
                    )
                )
            }
        }

        Log.i(TAG, "scan complete: ${out.size} tracks, ${artByAlbum.size} albums")
        return out
    }

    /**
     * Path to a cached JPEG of the album's art, or null when it has none.
     *
     * Cached on disk so a rescan — which happens on every cold start — costs
     * one `exists()` per album instead of a decode.
     */
    private fun albumArtPath(context: Context, albumId: Long): String? {
        if (albumId <= 0) return null
        val dir = File(context.cacheDir, ART_DIR).apply { mkdirs() }
        val file = File(dir, "$albumId.jpg")
        if (file.exists()) return if (file.length() > 0) file.absolutePath else null

        return try {
            val bitmap = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val uri = ContentUris.withAppendedId(
                    MediaStore.Audio.Albums.EXTERNAL_CONTENT_URI,
                    albumId,
                )
                context.contentResolver.loadThumbnail(
                    uri,
                    android.util.Size(ART_SIZE, ART_SIZE),
                    null,
                )
            } else {
                @Suppress("DEPRECATION")
                val uri = ContentUris.withAppendedId(
                    Uri.parse("content://media/external/audio/albumart"),
                    albumId,
                )
                context.contentResolver.openFileDescriptor(uri, "r")?.use { fd ->
                    android.graphics.BitmapFactory.decodeFileDescriptor(fd.fileDescriptor)
                }
            } ?: return markMissing(file)

            FileOutputStream(file).use { out ->
                bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, 85, out)
            }
            file.absolutePath
        } catch (e: Exception) {
            // Missing art throws rather than returning null on most devices.
            // Write a zero-byte marker so the next scan skips the attempt
            // instead of paying for the same exception again.
            markMissing(file)
        }
    }

    /**
     * The picture embedded in the file itself, cached like album art.
     *
     * MediaStore only indexes album art it has decided an album has, which
     * leaves loose files — a single dropped in Download, anything with tags
     * MediaStore did not group — showing the painted placeholder despite
     * carrying a perfectly good cover.
     *
     * Cached under the same album id and marked missing the same way, so a
     * file with no embedded picture costs one retriever open, once, ever.
     * MediaMetadataRetriever is expensive enough that paying it per scan would
     * be felt on a large library.
     */
    private fun embeddedArtPath(context: Context, albumId: Long, path: String): String? {
        val dir = File(context.cacheDir, ART_DIR).apply { mkdirs() }
        val file = File(dir, "embedded-$albumId.jpg")
        if (file.exists()) return if (file.length() > 0) file.absolutePath else null

        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(path)
            val bytes = retriever.embeddedPicture ?: return markMissing(file)
            FileOutputStream(file).use { out -> out.write(bytes) }
            file.absolutePath
        } catch (e: Exception) {
            markMissing(file)
        } finally {
            runCatching { retriever.release() }
        }
    }

    /** Zero-byte file meaning "this album has no art"; see [albumArtPath]. */
    private fun markMissing(file: File): String? {
        runCatching { file.createNewFile() }
        return null
    }
}
