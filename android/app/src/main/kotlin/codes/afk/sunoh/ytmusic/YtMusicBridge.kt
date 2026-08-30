package codes.afk.sunoh.ytmusic

import android.content.Context
import android.util.Log
import codes.afk.sunoh.ytmusic.potoken.PoTokenGenerator
import com.metrolist.innertubex.InnerTube
import com.metrolist.innertubex.InnerTubeLogLevel
import com.metrolist.innertubex.InnerTubeLogger
import com.metrolist.innertubex.cipher.PlayerConfigRepository
import com.metrolist.innertubex.cipher.RemotePlayerConfigStore
import com.metrolist.innertubex.cipher.YouTubeCipherService
import com.metrolist.innertubex.extraction.AudioQuality
import com.metrolist.innertubex.extraction.ContentHints
import com.metrolist.innertubex.extraction.InnerTubeExtractor
import com.metrolist.innertubex.extraction.PoTokenResult
import com.metrolist.innertubex.extraction.TokenProvider
import com.metrolist.innertubex.extraction.TokenProviderCapabilities
import com.metrolist.innertubex.extraction.YtConfigParserImpl
import com.metrolist.innertubex.extraction.generateClientPlaybackNonce
import com.metrolist.innertubex.extraction.strategy.PoTokenProviderKind
import io.ktor.client.HttpClient
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.plugins.compression.ContentEncoding
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.serialization.kotlinx.json.json
import java.util.concurrent.TimeUnit
import kotlinx.serialization.json.Json
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * YouTube Music stream resolution, bridged to Dart over a MethodChannel.
 *
 * ## Why this lives in Kotlin
 *
 * YouTube gates its *music catalog* ("- Topic" / Art Track uploads) behind a
 * BotGuard bot check. Probing the full InnerTube client ladder confirms there
 * is no client that returns playable audio for those tracks unauthenticated —
 * every one answers LOGIN_REQUIRED / UNPLAYABLE "Sign in to confirm you're not
 * a bot", even though ordinary videos resolve fine. Clearing it requires a PO
 * token minted by running Google's obfuscated BotGuard JS, which needs a real
 * WebView. That can't be done from Dart, so the whole extraction path sits
 * here and Dart just receives a URL.
 *
 * ## Shape
 *
 * [InnerTubeExtractor] (GPL-3.0, from the Metrolist project) owns client
 * selection, cipher/n-transform, format selection and health tracking. We
 * supply the two host-owned pieces the library deliberately leaves out: the
 * WebView PO-token minter, and the HTTP client.
 *
 * SABR is explicitly refused ([ContentHints.withStreamCapabilities] with
 * `allowSabr = false`). SABR serves media over a POST + protobuf channel that
 * mpv cannot consume; by declining it we always get back a plain
 * `googlevideo.com` URL that mpv plays directly, keeping media flowing
 * upstream→device.
 */
object YtMusicBridge {
    private const val TAG = "YtMusicBridge"

    /**
     * Warm-up target. Minting the first PO token costs a WebView spin-up plus
     * BotGuard evaluation (~2-5s); doing it against a fixed, always-available
     * video at app start means the user's first real play doesn't pay it.
     * Same video Metrolist uses — the first ever YouTube upload.
     */
    private const val WARMUP_VIDEO_ID = "jNQXAC9IVRw"

    private lateinit var appContext: Context
    private val buildMutex = Mutex()

    @Volatile
    private var bundle: Bundle? = null

    private class Bundle(
        val http: HttpClient,
        val innerTube: InnerTube,
        val extractor: InnerTubeExtractor,
    )

    fun initialize(context: Context) {
        appContext = context.applicationContext
    }

    private val poTokenGenerator: PoTokenGenerator by lazy { PoTokenGenerator(appContext) }

    /**
     * Surfaces the extractor's internal decisions — which clients it tried,
     * which PO-token rule applied, why each one was rejected — into logcat.
     * Without this a failure is just "Unable to fetch stream data", which
     * says nothing about where in the ladder it died.
     *
     * The library redacts tokens and signed URLs in its own event details, so
     * this is safe to leave on.
     */
    private val logger = InnerTubeLogger { event ->
        val details = if (event.details.isEmpty()) {
            ""
        } else {
            event.details.entries.joinToString(prefix = " [", postfix = "]") {
                "${it.key}=${it.value}"
            }
        }
        val msg = event.message + details
        when (event.level) {
            InnerTubeLogLevel.DEBUG -> Log.d(event.tag, msg)
            InnerTubeLogLevel.INFO -> Log.i(event.tag, msg)
            InnerTubeLogLevel.WARN -> Log.w(event.tag, msg)
            InnerTubeLogLevel.ERROR -> Log.e(event.tag, msg)
        }
    }

    /**
     * Bridges our ported WebView minter onto the library's [TokenProvider]
     * contract. Returning `null` is a valid answer — the extractor then walks
     * its client ladder looking for one that doesn't need a token, which is
     * what keeps a dead/hung WebView from being fatal.
     */
    private val tokenProvider = object : TokenProvider {
        override val capabilities = TokenProviderCapabilities(
            providers = setOf(PoTokenProviderKind.WEB_BOTGUARD),
            usesWebView = true,
        )

        override suspend fun getPoToken(
            videoId: String,
            visitorData: String,
            cookie: String?,
        ): PoTokenResult? =
            poTokenGenerator.getWebClientPoToken(videoId, visitorData)?.let { token ->
                PoTokenResult(
                    playerRequestToken = token.playerRequestPoToken,
                    streamingDataToken = token.streamingDataPoToken,
                    visitorData = visitorData,
                )
            }

        override suspend fun close() = poTokenGenerator.close()
    }

    private suspend fun bundle(): Bundle {
        bundle?.let { return it }
        return buildMutex.withLock {
            bundle?.let { return@withLock it }
            // The library takes a caller-owned HttpClient and assumes this
            // exact shape. Two settings are load-bearing:
            //
            //  - ContentNegotiation/json: every InnerTube call does
            //    `.body<SomeResponse>()`, which without a JSON converter
            //    throws before the response is ever inspected.
            //  - expectSuccess = false: InnerTubeX does its own status
            //    validation and transient-retry handling, and *reads*
            //    non-2xx player responses (that's how it distinguishes a bot
            //    check from a dead client). Ktor's default would throw on
            //    them instead, collapsing every client in the ladder into an
            //    indistinguishable IllegalStateException.
            val http = HttpClient(OkHttp) {
                expectSuccess = false
                install(ContentNegotiation) {
                    json(
                        Json {
                            ignoreUnknownKeys = true
                            explicitNulls = false
                            encodeDefaults = true
                        },
                    )
                }
                install(ContentEncoding) {
                    gzip(0.9F)
                    deflate(0.8F)
                }
                engine {
                    config {
                        connectTimeout(30, TimeUnit.SECONDS)
                        readTimeout(60, TimeUnit.SECONDS)
                        retryOnConnectionFailure(true)
                    }
                }
            }
            val innerTube = InnerTube(httpClient = http)
            // `PlayerConfigRepository.disabled()` = no on-disk cache of player
            // configs. RemotePlayerConfigStore still fetches them at runtime,
            // which is what lets cipher changes heal without an app release;
            // we just re-fetch per process instead of persisting.
            val configStore = RemotePlayerConfigStore(
                httpClient = http,
                repository = PlayerConfigRepository.disabled(),
                logger = logger,
            )
            val cipher = YouTubeCipherService(http, configStore, logger)
            val extractor = InnerTubeExtractor(
                configParser = YtConfigParserImpl(http, innerTube, configStore, logger),
                cipherService = cipher,
                innerTube = innerTube,
                tokenProvider = tokenProvider,
                logger = logger,
            )
            Bundle(http, innerTube, extractor).also { bundle = it }
        }
    }

    /** Spin up the WebView + mint a first token so the first play is fast. */
    suspend fun prewarm() {
        runCatching { bundle().extractor.prewarm() }
            .onFailure { Log.w(TAG, "extractor prewarm failed: ${it.message}") }
        runCatching { poTokenGenerator.getWebClientPoToken(WARMUP_VIDEO_ID, "") }
            .onFailure { Log.w(TAG, "potoken prewarm failed: ${it.message}") }
    }

    /**
     * Resolve [videoId] to a directly-playable audio URL.
     *
     * @param quality one of `auto` / `high` / `data`, mirroring the app's
     *   existing stream-quality setting.
     * @return a map for the MethodChannel result, or throws on failure.
     */
    suspend fun resolve(videoId: String, quality: String): Map<String, Any?> {
        val hints = ContentHints(wantVideo = false)
            .withStreamCapabilities(
                allowHls = false,
                allowSabr = false,
                allowBoundedRange = true,
            )
        val stream = bundle().extractor.extract(
            videoId = videoId,
            hints = hints,
            audioQuality = when (quality) {
                "high" -> AudioQuality.HIGH
                "data" -> AudioQuality.LOW
                else -> AudioQuality.AUTO
            },
            clientPlaybackNonce = generateClientPlaybackNonce(),
        ) ?: error("no playable stream for $videoId")

        // Guard the SABR refusal: if the library ever hands one back despite
        // allowSabr=false, fail loudly here rather than passing mpv a URL it
        // will silently fail to open.
        check(stream.sabrBootstrap == null) { "SABR stream is not playable by mpv" }

        val url = stream.audioUrl ?: error("stream had no audio url")
        return mapOf(
            "url" to url,
            "headers" to stream.headers,
            "itag" to stream.itag,
            "mimeType" to stream.mimeType,
            "bitrate" to stream.bitrate,
            "contentLength" to stream.contentLengthBytes,
            "loudnessDb" to stream.loudnessDb,
            "clientName" to stream.clientName,
            "expiresAtMs" to stream.expiresAt?.toEpochMilliseconds(),
            // mpv drives its own range requests; surfaced so Dart can log /
            // adapt if we hit throttling on unranged reads.
            "requireBoundedRange" to stream.requireBoundedRange,
            "rangeChunkSizeBytes" to stream.rangeChunkSizeBytes,
            "useRangeChunks" to stream.useRangeChunks,
        )
    }
}
