package codes.afk.sunoh.auth

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Where the YouTube session lives on this device.
 *
 * What is held here is a Google session cookie: whoever has it can act as the
 * signed-in user on YouTube. It is therefore treated as a credential rather
 * than as a setting.
 *
 *  - **Encrypted at rest with a key held in the Android Keystore.** The key
 *    material never enters the app's address space and cannot be pulled out of
 *    an `adb backup` or a copied `shared_prefs` file, which a plain
 *    SharedPreferences string can.
 *  - **Not in the Hive settings box.** That box is what library sync writes
 *    into a folder a cloud client uploads. A credential must never take that
 *    path, and keeping it in a different store means it cannot be added to the
 *    sync allow-list by accident.
 *  - **Never logged.** Not the cookie, not a prefix of it. The account name and
 *    a boolean are the only things about a session that ever reach a log line.
 *
 * `androidx.security:security-crypto` would do the same job. It is not used
 * because the platform already provides all of it, and dependency count is not
 * free while F-Droid inclusion is open — the same reasoning as SyncBridge.
 */
object YtAuthStore {

    private const val TAG = "YtAuthStore"
    private const val PREFS = "yt_auth"
    private const val KEY_ALIAS = "sunoh.yt_auth.v1"
    private const val GCM_TAG_BITS = 128
    private const val IV_BYTES = 12

    private const val K_COOKIE = "cookie"
    private const val K_VISITOR = "visitor_data"
    private const val K_DATA_SYNC = "data_sync_id"
    private const val K_AUTH_USER = "auth_user"
    private const val K_ACCOUNT = "account_name"

    /** Everything needed to speak to InnerTube as the signed-in user. */
    data class Session(
        val cookie: String,
        val visitorData: String,
        val dataSyncId: String,
        val authUser: String,
        val accountName: String,
    )

    fun save(context: Context, session: Session) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs.edit()
            .putString(K_COOKIE, seal(session.cookie))
            .putString(K_VISITOR, seal(session.visitorData))
            .putString(K_DATA_SYNC, seal(session.dataSyncId))
            .putString(K_AUTH_USER, session.authUser)
            // Shown in the UI, and not a credential on its own.
            .putString(K_ACCOUNT, session.accountName)
            .apply()
    }

    fun load(context: Context): Session? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val cookie = open(prefs.getString(K_COOKIE, null)) ?: return null
        if (cookie.isBlank()) return null
        return Session(
            cookie = cookie,
            visitorData = open(prefs.getString(K_VISITOR, null)).orEmpty(),
            dataSyncId = open(prefs.getString(K_DATA_SYNC, null)).orEmpty(),
            authUser = prefs.getString(K_AUTH_USER, null) ?: "0",
            accountName = prefs.getString(K_ACCOUNT, null).orEmpty(),
        )
    }

    /**
     * Forget the session. The Keystore key goes too, so anything that somehow
     * survives in a backup of the prefs file is undecryptable rather than
     * merely orphaned.
     */
    fun clear(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().apply()
        runCatching {
            KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
                .deleteEntry(KEY_ALIAS)
        }
    }

    private fun secretKey(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getEntry(KEY_ALIAS, null) as? KeyStore.SecretKeyEntry)?.let { return it.secretKey }
        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            "AndroidKeyStore",
        )
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                // Deliberately not setUserAuthenticationRequired: the session is
                // read on a cold start to render the home feed, long before
                // there is a UI to prompt on.
                .build(),
        )
        return generator.generateKey()
    }

    /** AES-GCM with the IV prepended, base64 for SharedPreferences. */
    private fun seal(plain: String): String? = try {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, secretKey())
        val body = cipher.doFinal(plain.toByteArray(Charsets.UTF_8))
        Base64.encodeToString(cipher.iv + body, Base64.NO_WRAP)
    } catch (e: Exception) {
        // No cookie text in the log, only that sealing failed.
        Log.w(TAG, "could not seal session value: ${e.javaClass.simpleName}")
        null
    }

    /**
     * Null on anything unreadable rather than throwing. A Keystore key can go
     * away on its own — a device restore, or the user clearing the secure
     * lock screen — and the honest response is "you are signed out", not a
     * crash on launch.
     */
    private fun open(stored: String?): String? {
        if (stored.isNullOrBlank()) return null
        return try {
            val blob = Base64.decode(stored, Base64.NO_WRAP)
            if (blob.size <= IV_BYTES) return null
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(
                Cipher.DECRYPT_MODE,
                secretKey(),
                GCMParameterSpec(GCM_TAG_BITS, blob, 0, IV_BYTES),
            )
            String(
                cipher.doFinal(blob, IV_BYTES, blob.size - IV_BYTES),
                Charsets.UTF_8,
            )
        } catch (e: Exception) {
            Log.w(TAG, "could not open session value: ${e.javaClass.simpleName}")
            null
        }
    }
}
