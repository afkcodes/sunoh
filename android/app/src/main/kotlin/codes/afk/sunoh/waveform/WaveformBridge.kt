package codes.afk.sunoh.waveform

import android.content.Context
import android.net.ConnectivityManager
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteOrder
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Measures how loud an audio file is over time, without touching the player.
 *
 * The playback engine allows one waveform per process, so a second file cannot
 * be analysed through it without replacing the playing track's envelope. This
 * decodes with the platform's own MediaExtractor + MediaCodec instead and
 * returns one mean-square value per fixed window of mono PCM (0..1 for
 * full-scale). Dart folds the windows into bins; keeping that out of here
 * keeps it testable.
 */
object WaveformBridge {

    /** Frames per window, about 46 ms at 44.1 kHz: a 5 minute song is ~6500 windows. */
    private const val WINDOW = 2048

    private const val CHANNEL = "codes.afk.sunoh/waveform"

    /**
     * Decoding a song is seconds of CPU, so it has its own scope rather than
     * queueing behind stream resolution or a scan. Never cancelled: the object
     * lives as long as the process, a decode in flight is harmless to abandon,
     * and no sibling bridge cancels its scope either.
     */
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    /** Wires the `analyse` and `isMetered` calls onto [messenger]. */
    fun register(context: Context, messenger: BinaryMessenger) {
        val app = context.applicationContext
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isMetered" -> result.success(isMetered(app))
                "analyse" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.notImplemented()
                        return@setMethodCallHandler
                    }
                    scope.launch {
                        val outcome = runCatching { analyse(path) }
                        withContext(Dispatchers.Main) {
                            outcome
                                .onSuccess { result.success(it) }
                                .onFailure {
                                    result.error(
                                        if (it is NoAudio) "no_audio" else "analyse_failed",
                                        it::class.simpleName,
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

    /** True unless the OS says the active network is unmetered: unknown counts as metered. */
    private fun isMetered(context: Context): Boolean = runCatching {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        cm.isActiveNetworkMetered
    }.getOrDefault(true)

    /** Thrown when the file has no audio track the extractor can open. */
    class NoAudio : Exception()

    fun analyse(path: String): FloatArray {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            extractor.setDataSource(path)
            val track = (0 until extractor.trackCount).firstOrNull {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)
                    ?.startsWith("audio/") == true
            } ?: throw NoAudio()
            extractor.selectTrack(track)
            val format = extractor.getTrackFormat(track)
            codec = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
            codec.configure(format, null, null, 0)
            codec.start()
            return decode(extractor, codec)
        } finally {
            runCatching { codec?.stop() }
            runCatching { codec?.release() }
            extractor.release()
        }
    }

    private fun decode(extractor: MediaExtractor, codec: MediaCodec): FloatArray {
        val windows = ArrayList<Float>()
        val info = MediaCodec.BufferInfo()
        var channels = 1
        var float = false
        var energy = 0.0
        var frames = 0
        var inputDone = false
        var outputDone = false

        while (!outputDone) {
            if (!inputDone) {
                val i = codec.dequeueInputBuffer(TIMEOUT_US)
                if (i >= 0) {
                    val buf = codec.getInputBuffer(i)!!
                    val n = extractor.readSampleData(buf, 0)
                    if (n < 0) {
                        codec.queueInputBuffer(i, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        inputDone = true
                    } else {
                        codec.queueInputBuffer(i, 0, n, extractor.sampleTime, 0)
                        extractor.advance()
                    }
                }
            }
            val o = codec.dequeueOutputBuffer(info, TIMEOUT_US)
            when {
                o == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    val out = codec.outputFormat
                    channels = out.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    float = out.containsKey(MediaFormat.KEY_PCM_ENCODING) &&
                        out.getInteger(MediaFormat.KEY_PCM_ENCODING) == AudioFormat.ENCODING_PCM_FLOAT
                }

                o >= 0 -> {
                    val buf = codec.getOutputBuffer(o)!!.order(ByteOrder.nativeOrder())
                    buf.position(info.offset)
                    buf.limit(info.offset + info.size)
                    val samples = if (float) buf.asFloatBuffer() else null
                    val shorts = if (float) null else buf.asShortBuffer()
                    val total = (samples?.remaining() ?: shorts!!.remaining()) / channels
                    for (f in 0 until total) {
                        // Mono mix: the mean of the channels, as the engine's envelope is mono.
                        var mix = 0.0
                        for (c in 0 until channels) {
                            mix += samples?.get() ?: (shorts!!.get() / 32768.0f)
                        }
                        mix /= channels
                        energy += mix * mix
                        if (++frames == WINDOW) {
                            windows.add((energy / WINDOW).toFloat())
                            energy = 0.0
                            frames = 0
                        }
                    }
                    codec.releaseOutputBuffer(o, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputDone = true
                }
            }
        }
        if (frames > 0) windows.add((energy / frames).toFloat())
        return windows.toFloatArray()
    }

    private const val TIMEOUT_US = 10_000L
}
