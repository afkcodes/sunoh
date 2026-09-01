package codes.afk.sunoh.sync

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.util.Base64
import android.util.Log
import androidx.documentfile.provider.DocumentFile
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Folder access and encryption for library sync.
 *
 * ## Why this is native
 *
 * Two reasons, both the same reason the YouTube and MediaStore bridges are.
 *
 * The Storage Access Framework has no Flutter equivalent worth depending on:
 * picking a tree, persisting the permission across reboots, and enumerating a
 * folder are all ContentResolver work, and the available pub wrappers have the
 * maintenance record `pubspec.yaml` already documents for one package.
 *
 * AES-GCM is in the platform via javax.crypto. Reaching for a pub crypto
 * package would add a dependency for something the OS already does, and
 * dependency count is not free while F-Droid inclusion is still open.
 *
 * ## What it does not do
 *
 * No network, no account, no Google API. The app writes an encrypted file into
 * a folder the user picked; whatever syncs that folder does the moving. sunoh
 * never learns where the folder actually lives.
 */
object SyncBridge {
    private const val TAG = "SyncBridge"

    /** AES-128-GCM. 128 bits keeps the recovery code short enough to type. */
    private const val KEY_BITS = 128
    private const val GCM_TAG_BITS = 128
    private const val IV_BYTES = 12

    /** Marks our files so a shared folder can hold other things safely. */
    const val FILE_PREFIX = "sunoh-"
    const val FILE_SUFFIX = ".sync"

    private const val MIME = "application/octet-stream"

    fun openFolderPickerIntent(): Intent =
        Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
            )
        }

    /**
     * Take a long-lived grant on the picked tree.
     *
     * Without this the permission dies with the process and the user is asked
     * to re-pick the folder on every launch.
     */
    fun persistTreePermission(context: Context, uri: Uri): Boolean = try {
        context.contentResolver.takePersistableUriPermission(
            uri,
            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
        )
        true
    } catch (e: SecurityException) {
        Log.w(TAG, "could not persist permission for $uri: ${e.message}")
        false
    }

    /** True while the saved tree is still readable — the user can revoke it. */
    fun hasAccess(context: Context, treeUri: String): Boolean = try {
        val tree = DocumentFile.fromTreeUri(context, Uri.parse(treeUri))
        tree != null && tree.exists() && tree.canWrite()
    } catch (e: Exception) {
        false
    }

    /** A display name for the folder, for the settings row. */
    fun folderName(context: Context, treeUri: String): String? = try {
        DocumentFile.fromTreeUri(context, Uri.parse(treeUri))?.name
    } catch (e: Exception) {
        null
    }

    /**
     * Every sync file in the folder, as `name -> bytes`.
     *
     * Reads *all* of them, including this device's own: each device writes only
     * its own file, so a full read is how the merge sees the others. Files that
     * fail to open are skipped rather than failing the sync — a half-synced
     * cloud folder is normal, not exceptional.
     */
    fun readAll(context: Context, treeUri: String): Map<String, ByteArray> {
        val out = HashMap<String, ByteArray>()
        val tree = DocumentFile.fromTreeUri(context, Uri.parse(treeUri))
            ?: return out
        for (file in tree.listFiles()) {
            val name = file.name ?: continue
            if (!name.startsWith(FILE_PREFIX) || !name.endsWith(FILE_SUFFIX)) {
                continue
            }
            try {
                context.contentResolver.openInputStream(file.uri)?.use {
                    out[name] = it.readBytes()
                }
            } catch (e: Exception) {
                Log.w(TAG, "skipping unreadable $name: ${e.message}")
            }
        }
        Log.i(TAG, "read ${out.size} sync file(s)")
        return out
    }

    /**
     * Write this device's file, replacing what was there.
     *
     * Deletes and recreates rather than truncating: SAF's write mode "w" does
     * not reliably truncate across providers, which leaves the tail of a longer
     * previous document appended to a shorter new one — corrupt JSON that only
     * appears once a library shrinks.
     */
    fun write(
        context: Context,
        treeUri: String,
        name: String,
        bytes: ByteArray,
    ): Boolean {
        return try {
            val tree = DocumentFile.fromTreeUri(context, Uri.parse(treeUri))
                ?: return false
            tree.findFile(name)?.delete()
            val file = tree.createFile(MIME, name) ?: return false
            context.contentResolver.openOutputStream(file.uri, "w")?.use {
                it.write(bytes)
                it.flush()
            } ?: return false
            Log.i(TAG, "wrote $name (${bytes.size} bytes)")
            true
        } catch (e: Exception) {
            Log.e(TAG, "write failed for $name: ${e.message}")
            false
        }
    }

    /** Remove this device's own file, for "stop syncing and clean up". */
    fun delete(context: Context, treeUri: String, name: String): Boolean = try {
        DocumentFile.fromTreeUri(context, Uri.parse(treeUri))
            ?.findFile(name)?.delete() ?: false
    } catch (e: Exception) {
        false
    }

    // ── Encryption ───────────────────────────────────────────────────────

    /** A fresh random key, base64 for storage. */
    fun generateKey(): String {
        val key = ByteArray(KEY_BITS / 8)
        SecureRandom().nextBytes(key)
        return Base64.encodeToString(key, Base64.NO_WRAP)
    }

    /**
     * AES-GCM, IV prepended to the ciphertext.
     *
     * A fresh random IV per write matters more than usual here: the same
     * library is re-encrypted on every change, so a fixed IV would leak which
     * parts changed between two versions of the file sitting in the cloud.
     */
    fun encrypt(plain: ByteArray, keyB64: String): ByteArray? = try {
        val key = SecretKeySpec(Base64.decode(keyB64, Base64.NO_WRAP), "AES")
        val iv = ByteArray(IV_BYTES).also { SecureRandom().nextBytes(it) }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(GCM_TAG_BITS, iv))
        iv + cipher.doFinal(plain)
    } catch (e: Exception) {
        Log.e(TAG, "encrypt failed: ${e.message}")
        null
    }

    /**
     * Returns null when the file was written with a different key, or is
     * truncated or corrupt. GCM authenticates, so a wrong key is a clean
     * failure rather than garbage output — which is what lets the caller say
     * "this folder belongs to a different setup" instead of importing rubbish.
     */
    fun decrypt(blob: ByteArray, keyB64: String): ByteArray? = try {
        if (blob.size <= IV_BYTES) {
            null
        } else {
            val key = SecretKeySpec(Base64.decode(keyB64, Base64.NO_WRAP), "AES")
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(
                Cipher.DECRYPT_MODE,
                key,
                GCMParameterSpec(GCM_TAG_BITS, blob.copyOfRange(0, IV_BYTES)),
            )
            cipher.doFinal(blob.copyOfRange(IV_BYTES, blob.size))
        }
    } catch (e: Exception) {
        // Expected whenever the key does not match; not worth an error log.
        Log.i(TAG, "decrypt failed (wrong key or corrupt file)")
        null
    }

    /** Request code for the folder picker, matched in onActivityResult. */
    const val PICK_FOLDER_REQUEST = 0x5117

    fun treeUriFromResult(resultCode: Int, data: Intent?): Uri? =
        if (resultCode == Activity.RESULT_OK) data?.data else null

    /** Only used for logging; a tree uri is long and mostly opaque. */
    fun shortUri(uri: String): String =
        try {
            Uri.decode(DocumentsContract.getTreeDocumentId(Uri.parse(uri)))
        } catch (e: Exception) {
            uri.takeLast(24)
        }
}
