package codes.afk.sunoh.auth

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.util.Log
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout

/**
 * Signs in to YouTube with Google's own web flow, in a WebView.
 *
 * There is no other way. Google publishes no OAuth scope that gives a third
 * party access to YouTube Music, so every client that offers this — Metrolist,
 * InnerTune — signs in through the web page and keeps the resulting cookie.
 * Doing it in a WebView rather than an embedded form matters: the password is
 * typed into Google's page, over Google's TLS, and this app never sees it. All
 * that comes back is the session cookie the browser would have held anyway.
 *
 * Three things are collected once the login lands:
 *
 *  - the cookie for `music.youtube.com`, which carries `SAPISID` — the value
 *    the request signature is derived from, and the marker for "actually
 *    signed in" rather than "page loaded";
 *  - `VISITOR_DATA`, which pins the session to a consistent identity;
 *  - `DATASYNC_ID`, which says *which* profile of a multi-profile Google
 *    account is active. Without it, an account with brand channels serves a
 *    different library than the one picked on screen.
 *
 * The last two only exist in `ytcfg` on a music.youtube.com page, which is why
 * the flow continues there rather than stopping at the accounts domain.
 */
class YtLoginActivity : Activity() {

    private var webView: WebView? = null

    /** Set once, so a redirect chain cannot deliver two results. */
    private var settled = false

    @Volatile private var visitorData: String = ""

    @Volatile private var dataSyncId: String = ""

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val view = WebView(this)
        webView = view
        setContentView(
            FrameLayout(this).apply {
                addView(
                    view,
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT,
                )
            },
        )

        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(view, true)

        view.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            setSupportZoom(true)
            builtInZoomControls = true
            displayZoomControls = false
        }
        // The user agent is deliberately left alone.
        //
        // Claiming to be desktop Chrome is the obvious move and it backfires:
        // Google checks the claim against the JS environment, and a desktop
        // string on a WebView that has none of desktop Chrome's surface reads
        // as evasion. That is exactly what "This browser or app may not be
        // secure" means, and spoofing the string is what earns it. The stock
        // WebView agent, honestly presented, is what gets through — this is
        // also what Metrolist does, and why its sign-in works.

        view.webViewClient = object : WebViewClient() {
            override fun onPageFinished(webView: WebView?, url: String?) {
                super.onPageFinished(webView, url)
                // Host, not substring: a sign-in URL can carry
                // "music.youtube.com" in its continue= parameter while still
                // being an accounts.google.com page with no ytcfg to read.
                val host = runCatching { Uri.parse(url).host }.getOrNull()
                if (host != "music.youtube.com") return
                probe(attempt = 0)
            }
        }

        view.loadUrl(LOGIN_URL)
    }

    /**
     * Ask the page for its config, and keep asking.
     *
     * YouTube Music is a single-page app: `onPageFinished` fires when the
     * document is done, which is well before its scripts have populated
     * `ytcfg`. A single read a moment later finds nothing, and an earlier
     * version of this treated that as "not signed in" — so a user who really
     * had signed in sat on a loaded page while the app waited for a value that
     * had already been read too early and would never be read again.
     *
     * ytcfg rather than scraping HTML: it is the same source the web client
     * reads these from.
     */
    private fun probe(attempt: Int) {
        val view = webView ?: return
        if (settled) return

        view.evaluateJavascript(CONFIG_JS) { raw ->
            val parts = unquote(raw).split('|')
            parts.getOrNull(0)?.takeIf { it.isNotBlank() }?.let { visitorData = it }
            parts.getOrNull(1)?.takeIf { it.isNotBlank() }?.let { dataSyncId = it }

            // Out of attempts is not failure. visitorData sharpens a session;
            // the cookie and the signature are what authenticate it, so a
            // session without one is worth keeping rather than discarding.
            val lastChance = attempt >= MAX_PROBES
            if (visitorData.isNotBlank() || lastChance) {
                settleIfSignedIn(giveUpOnVisitorData = lastChance)
                if (!settled && !lastChance) view.postDelayed({ probe(attempt + 1) }, PROBE_DELAY_MS)
            } else {
                view.postDelayed({ probe(attempt + 1) }, PROBE_DELAY_MS)
            }
        }
    }

    /**
     * Finish only once the cookie actually carries SAPISID. Every earlier page
     * in the flow — the account chooser, the password step, a consent screen —
     * sets cookies too, and treating any of them as success hands back a
     * session that cannot sign a single request.
     */
    private fun settleIfSignedIn(giveUpOnVisitorData: Boolean) {
        if (settled) return
        CookieManager.getInstance().flush()
        val cookie = CookieManager.getInstance().getCookie(MUSIC_URL).orEmpty()
        if (!cookie.contains("SAPISID")) {
            Log.i(TAG, "on music.youtube.com but no SAPISID cookie yet")
            return
        }
        if (visitorData.isBlank() && !giveUpOnVisitorData) return

        settled = true
        Log.i(
            TAG,
            "signed in (visitorData=${visitorData.isNotBlank()}, " +
                "dataSyncId=${dataSyncId.isNotBlank()})",
        )
        setResult(
            RESULT_OK,
            Intent().apply {
                putExtra(EXTRA_COOKIE, cookie)
                putExtra(EXTRA_VISITOR_DATA, visitorData)
                putExtra(EXTRA_DATA_SYNC_ID, dataSyncId)
            },
        )
        finish()
    }

    override fun onDestroy() {
        webView?.let { view ->
            view.stopLoading()
            (view.parent as? ViewGroup)?.removeView(view)
            view.destroy()
        }
        webView = null
        super.onDestroy()
    }

    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        val view = webView
        // Back walks the sign-in flow first. Only once there is nothing to go
        // back to does it mean "I changed my mind", which is a cancel and not
        // an error.
        if (view != null && view.canGoBack()) {
            view.goBack()
        } else {
            setResult(RESULT_CANCELED)
            super.onBackPressed()
        }
    }

    /**
     * evaluateJavascript hands back a JSON literal, so a plain string arrives
     * wrapped in quotes and `null` arrives as the four characters.
     */
    private fun unquote(raw: String?): String {
        if (raw == null || raw == "null") return ""
        return raw.removeSurrounding("\"").replace("\\\"", "\"")
    }

    companion object {
        private const val TAG = "YtLogin"
        const val EXTRA_COOKIE = "cookie"
        const val EXTRA_VISITOR_DATA = "visitorData"
        const val EXTRA_DATA_SYNC_ID = "dataSyncId"

        private const val MUSIC_URL = "https://music.youtube.com"
        private const val LOGIN_URL =
            "https://accounts.google.com/ServiceLogin" +
                "?continue=https%3A%2F%2Fmusic.youtube.com"

        private const val PROBE_DELAY_MS = 500L

        /** ~10s of retries. A slow page must not cost a completed sign-in. */
        private const val MAX_PROBES = 20

        /**
         * Both values in one call, pipe-joined — two round trips through the
         * JS bridge would have to be correlated, and there is nothing to gain
         * from reading them a frame apart.
         */
        private const val CONFIG_JS =
            "(function(){try{" +
                "return (ytcfg.get('VISITOR_DATA')||'')+'|'+(ytcfg.get('DATASYNC_ID')||'');" +
                "}catch(e){return '|';}})();"
    }
}
