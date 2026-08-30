package codes.afk.sunoh.ytmusic.potoken

import android.util.Log

/**
 * Verbose PO-token logging switch.
 *
 * Upstream (Metrolist) gates its noisiest WebView/BotGuard traces behind
 * `BuildConfig.DEBUG`. Flutter's AGP setup doesn't generate a BuildConfig for
 * this module by default, so we use a plain constant instead. Keep it `false`
 * in anything you ship: the verbose paths can echo BotGuard challenge material
 * into logcat, and PO tokens are credentials.
 */
internal const val POTOKEN_VERBOSE = false

/**
 * Minimal stand-in for the Timber API surface used by the ported PO-token
 * files (`Timber.tag(TAG).d/i/w/e(...)`).
 *
 * The upstream sources are lifted essentially verbatim so they stay easy to
 * diff against Metrolist when BotGuard changes. Rather than rewrite ~34 call
 * sites — and risk a transcription error in code we can't easily test — we
 * shim the two-call shape onto android.util.Log. Same package, so dropping
 * the `timber.log.Timber` import is all it takes.
 */
internal object Timber {
    fun tag(tag: String): Logger = Logger(tag)

    class Logger(private val tag: String) {
        fun d(message: String) {
            if (POTOKEN_VERBOSE) Log.d(tag, message)
        }

        fun i(message: String) = Log.i(tag, message).let { }

        fun w(message: String) = Log.w(tag, message).let { }

        fun e(message: String) = Log.e(tag, message).let { }

        fun e(t: Throwable, message: String) = Log.e(tag, message, t).let { }

        fun w(t: Throwable, message: String) = Log.w(tag, message, t).let { }
    }
}
