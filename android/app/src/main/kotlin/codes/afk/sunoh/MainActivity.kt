package codes.afk.sunoh

import codes.afk.sunoh.localmedia.LocalMediaBridge
import codes.afk.sunoh.ytmusic.YtMusicBridge
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// audio_service requires MainActivity to extend AudioServiceActivity (which
// itself extends FlutterFragmentActivity). Without this, AudioService.init
// fails with "The Activity class declared in your AndroidManifest.xml is
// wrong or has not provided the correct FlutterEngine".
class MainActivity : AudioServiceActivity() {

    /**
     * Scope for YouTube Music resolution. Tied to the activity rather than a
     * global scope so a destroyed activity cancels in-flight extraction (each
     * call can hold a WebView).
     */
    private val ytScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /**
     * Scope for the on-device library scan. Separate from [ytScope] so a slow
     * MediaStore query on a large library cannot delay stream resolution, and
     * so a destroyed activity cancels an in-flight scan.
     */
    private val localScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        YtMusicBridge.initialize(applicationContext)

        // Stream resolution for the YouTube Music tier. Lives natively because
        // the required BotGuard PO token can only be minted by running
        // Google's JS in a WebView — see YtMusicBridge for the full rationale.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "prewarm" -> {
                        ytScope.launch {
                            runCatching { YtMusicBridge.prewarm() }
                            withContext(Dispatchers.Main) { result.success(null) }
                        }
                    }

                    "resolve" -> {
                        val videoId = call.argument<String>("videoId")
                        if (videoId.isNullOrBlank()) {
                            result.error("bad_args", "videoId is required", null)
                            return@setMethodCallHandler
                        }
                        val quality = call.argument<String>("quality") ?: "auto"
                        ytScope.launch {
                            val outcome = runCatching { YtMusicBridge.resolve(videoId, quality) }
                            withContext(Dispatchers.Main) {
                                outcome
                                    .onSuccess { result.success(it) }
                                    .onFailure {
                                        // Never surface the exception object —
                                        // library toString() redacts tokens and
                                        // signed URLs, but the message is enough
                                        // for Dart to decide on a fallback tier.
                                        result.error(
                                            "resolve_failed",
                                            it.message ?: it::class.simpleName,
                                            null,
                                        )
                                    }
                            }
                        }
                    }

                    else -> result.notImplemented()
                }
            }

        // The device's own music library. Off the main thread: a MediaStore
        // query over a few thousand tracks, resolving album art per album,
        // takes long enough to drop frames if run inline.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LOCAL_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "scan" -> {
                        localScope.launch {
                            val outcome = runCatching {
                                LocalMediaBridge.scan(applicationContext)
                            }
                            withContext(Dispatchers.Main) {
                                outcome
                                    .onSuccess { result.success(it) }
                                    .onFailure {
                                        result.error(
                                            "scan_failed",
                                            it.message ?: it::class.simpleName,
                                            null,
                                        )
                                    }
                            }
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private companion object {
        const val CHANNEL = "codes.afk.sunoh/ytmusic"
        const val LOCAL_CHANNEL = "codes.afk.sunoh/localmedia"
    }
}
