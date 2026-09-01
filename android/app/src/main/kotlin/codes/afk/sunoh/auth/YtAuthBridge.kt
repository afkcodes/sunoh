package codes.afk.sunoh.auth

import android.content.Context
import android.util.Log
import android.webkit.CookieManager
import java.security.MessageDigest

/**
 * The signed-in YouTube session, and the one place that turns it into request
 * headers.
 *
 * InnerTube authenticates the way the web client does: the cookie, plus an
 * `Authorization` header holding a SHA-1 over the timestamp, the `SAPISID`
 * cookie value and the origin. There is no token exchange and nothing to
 * refresh — the signature is recomputed per request from a cookie the browser
 * would hold anyway.
 *
 * Kept native rather than in Dart because the cookie lives here, in the
 * Keystore-backed store, and handing it across the method channel on every
 * request would mean copying a credential through a Dart string on every home
 * refresh. Dart asks for headers; it never holds the cookie.
 */
object YtAuthBridge {

    private const val TAG = "YtAuth"
    private const val ORIGIN = "https://music.youtube.com"

    @Volatile
    private var cached: YtAuthStore.Session? = null

    fun restore(context: Context) {
        cached = YtAuthStore.load(context)
        Log.i(TAG, "restored session: ${cached != null}")
    }

    fun isSignedIn(): Boolean = cached != null

    fun accountName(): String = cached?.accountName.orEmpty()

    fun save(context: Context, session: YtAuthStore.Session) {
        YtAuthStore.save(context, session)
        cached = session
    }

    /**
     * Record who the session belongs to, once Dart has asked YouTube. Only the
     * display name changes; the credential is left exactly as stored.
     */
    fun rename(context: Context, name: String) {
        val session = cached ?: return
        if (session.accountName == name) return
        val updated = session.copy(accountName = name)
        YtAuthStore.save(context, updated)
        cached = updated
    }

    /**
     * Sign out everywhere it counts: the stored session, the in-memory copy,
     * and the WebView cookie jar. Leaving the jar populated would let the next
     * sign-in silently resume the same account, which is not what someone who
     * just signed out asked for.
     */
    fun signOut(context: Context) {
        YtAuthStore.clear(context)
        cached = null
        runCatching {
            CookieManager.getInstance().removeAllCookies(null)
            CookieManager.getInstance().flush()
        }
        Log.i(TAG, "signed out")
    }

    /**
     * Headers for one authenticated InnerTube call, or empty when signed out —
     * in which case the caller sends exactly what it sent before, and the
     * anonymous path is unchanged.
     */
    fun headers(): Map<String, String> {
        val session = cached ?: return emptyMap()
        val sapisid = sapisidOf(session.cookie) ?: return emptyMap()
        val headers = mutableMapOf(
            "Cookie" to session.cookie,
            "Authorization" to sapisidHash(sapisid),
            "X-Goog-AuthUser" to session.authUser,
            // X-Origin has to match the origin inside the signature, or the
            // signature is checked against the wrong string and the request is
            // answered as if it were anonymous.
            "X-Origin" to ORIGIN,
            "X-Goog-Api-Format-Version" to "1",
        )
        if (session.visitorData.isNotBlank()) {
            headers["X-Goog-Visitor-Id"] = session.visitorData
        }
        // dataSyncId is deliberately NOT sent as X-Goog-PageId.
        //
        // That was a guess, and a costly one: X-Goog-PageId names a channel to
        // act as, and a dataSyncId is not a channel id. YouTube answered for an
        // identity that did not exist — an account menu with no account in it,
        // and a home feed with nothing personal on it, while every header
        // looked present and correct. It is kept in the session because
        // switching brand channels will need it, and it belongs in the request
        // context rather than in a header.
        return headers
    }

    /** `visitorData` belongs in the request context too, not just a header. */
    fun visitorData(): String = cached?.visitorData.orEmpty()

    /**
     * `SAPISIDHASH <unix seconds>_<sha1(seconds + " " + SAPISID + " " + origin)>`.
     *
     * The timestamp is inside the digest, so a captured header is only good
     * for the window YouTube allows — which is why the hash is computed per
     * request rather than stored.
     */
    private fun sapisidHash(sapisid: String): String {
        val seconds = System.currentTimeMillis() / 1000
        val digest = sha1("$seconds $sapisid $ORIGIN")
        return "SAPISIDHASH ${seconds}_$digest"
    }

    private fun sha1(input: String): String =
        MessageDigest.getInstance("SHA-1")
            .digest(input.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }

    /**
     * `SAPISID` proper, falling back to the `__Secure-3PAPISID` twin that some
     * accounts get instead. Without one of them there is nothing to sign with
     * and the session is not usable, however complete it otherwise looks.
     */
    private fun sapisidOf(cookie: String): String? {
        val pairs = cookie.split(";")
            .mapNotNull { part ->
                val bits = part.trim().split("=", limit = 2)
                if (bits.size == 2) bits[0].trim() to bits[1].trim() else null
            }
            .toMap()
        return pairs["SAPISID"]?.takeIf { it.isNotBlank() }
            ?: pairs["__Secure-3PAPISID"]?.takeIf { it.isNotBlank() }
    }
}
