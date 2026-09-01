package codes.afk.sunoh

import android.content.Intent
import codes.afk.sunoh.auth.YtAuthBridge
import codes.afk.sunoh.auth.YtAuthStore
import codes.afk.sunoh.auth.YtLoginActivity
import codes.afk.sunoh.localmedia.LocalMediaBridge
import codes.afk.sunoh.sync.SyncBridge
import codes.afk.sunoh.ytmusic.YtMusicBridge
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result
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

    /**
     * Scope for sync file I/O. Separate again: a folder behind a cloud
     * provider can block for seconds on a cold read, and that must not sit in
     * front of stream resolution or a library scan.
     */
    private val syncScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /**
     * Held across the folder picker. SAF answers through onActivityResult, so
     * the Dart call is parked until the user has chosen, or backed out — which
     * returns null rather than an error, because cancelling a picker is a
     * normal thing to do.
     */
    private var pendingFolderResult: Result? = null

    /**
     * Held across the sign-in WebView, for the same reason as the folder
     * picker: the answer arrives through onActivityResult. Backing out of a
     * sign-in returns false rather than an error — changing your mind about
     * signing in is a normal thing to do.
     */
    private var pendingLoginResult: Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        YtMusicBridge.initialize(applicationContext)
        YtAuthBridge.restore(applicationContext)

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

        // Library sync: folder access and encryption. No network here. The app
        // writes an encrypted file into a folder the user picked, and whatever
        // syncs that folder does the moving.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SYNC_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickFolder" -> {
                        if (pendingFolderResult != null) {
                            result.error("busy", "picker already open", null)
                        } else {
                            pendingFolderResult = result
                            startActivityForResult(
                                SyncBridge.openFolderPickerIntent(),
                                SyncBridge.PICK_FOLDER_REQUEST,
                            )
                        }
                    }

                    "hasAccess" -> {
                        val tree = call.argument<String>("tree")
                        result.success(
                            tree != null && SyncBridge.hasAccess(applicationContext, tree),
                        )
                    }

                    "folderName" -> {
                        val tree = call.argument<String>("tree")
                        result.success(
                            tree?.let { SyncBridge.folderName(applicationContext, it) },
                        )
                    }

                    "generateKey" -> result.success(SyncBridge.generateKey())

                    "readAll" -> {
                        val tree = call.argument<String>("tree")
                        val key = call.argument<String>("key")
                        if (tree == null || key == null) {
                            result.error("bad_args", "tree and key required", null)
                            return@setMethodCallHandler
                        }
                        syncScope.launch {
                            val outcome = runCatching {
                                SyncBridge.readAll(applicationContext, tree)
                                    .mapNotNull { (name, bytes) ->
                                        // A file encrypted with another key is
                                        // skipped, not an error: the folder may
                                        // be shared with a different setup.
                                        SyncBridge.decrypt(bytes, key)?.let { name to it }
                                    }
                                    .toMap()
                            }
                            withContext(Dispatchers.Main) {
                                outcome.onSuccess { result.success(it) }
                                    .onFailure {
                                        result.error(
                                            "read_failed",
                                            it.message ?: "read failed",
                                            null,
                                        )
                                    }
                            }
                        }
                    }

                    "write" -> {
                        val tree = call.argument<String>("tree")
                        val name = call.argument<String>("name")
                        val key = call.argument<String>("key")
                        val bytes = call.argument<ByteArray>("bytes")
                        if (tree == null || name == null || key == null || bytes == null) {
                            result.error("bad_args", "missing argument", null)
                            return@setMethodCallHandler
                        }
                        syncScope.launch {
                            val outcome = runCatching {
                                val blob = SyncBridge.encrypt(bytes, key)
                                if (blob == null) false
                                else SyncBridge.write(applicationContext, tree, name, blob)
                            }
                            withContext(Dispatchers.Main) {
                                outcome.onSuccess { result.success(it) }
                                    .onFailure {
                                        result.error(
                                            "write_failed",
                                            it.message ?: "write failed",
                                            null,
                                        )
                                    }
                            }
                        }
                    }

                    "delete" -> {
                        val tree = call.argument<String>("tree")
                        val name = call.argument<String>("name")
                        result.success(
                            tree != null && name != null &&
                                SyncBridge.delete(applicationContext, tree, name),
                        )
                    }

                    else -> result.notImplemented()
                }
            }

        // The signed-in YouTube session. Native because the cookie is a
        // credential held in the Keystore-backed store: Dart asks for headers
        // and never holds the cookie itself. See YtAuthBridge.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUTH_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "state" -> result.success(
                        mapOf(
                            "signedIn" to YtAuthBridge.isSignedIn(),
                            "accountName" to YtAuthBridge.accountName(),
                            "visitorData" to YtAuthBridge.visitorData(),
                        ),
                    )

                    "signIn" -> {
                        if (pendingLoginResult != null) {
                            result.error("busy", "sign-in already open", null)
                        } else {
                            pendingLoginResult = result
                            startActivityForResult(
                                Intent(this, YtLoginActivity::class.java),
                                LOGIN_REQUEST,
                            )
                        }
                    }

                    "signOut" -> {
                        YtAuthBridge.signOut(applicationContext)
                        result.success(null)
                    }

                    // Recomputed per call: the SAPISIDHASH covers a timestamp,
                    // so a cached header goes stale.
                    "headers" -> result.success(YtAuthBridge.headers())

                    "setAccountName" -> {
                        val name = call.argument<String>("name").orEmpty()
                        YtAuthBridge.rename(applicationContext, name)
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == SyncBridge.PICK_FOLDER_REQUEST) {
            val pending = pendingFolderResult
            pendingFolderResult = null
            val uri = SyncBridge.treeUriFromResult(resultCode, data)
            if (uri == null) {
                pending?.success(null)
            } else {
                SyncBridge.persistTreePermission(applicationContext, uri)
                pending?.success(uri.toString())
            }
            return
        }
        if (requestCode == LOGIN_REQUEST) {
            val pending = pendingLoginResult
            pendingLoginResult = null
            val cookie = data?.getStringExtra(YtLoginActivity.EXTRA_COOKIE)
            if (resultCode != RESULT_OK || cookie.isNullOrBlank()) {
                pending?.success(false)
            } else {
                YtAuthBridge.save(
                    applicationContext,
                    YtAuthStore.Session(
                        cookie = cookie,
                        visitorData = data.getStringExtra(
                            YtLoginActivity.EXTRA_VISITOR_DATA,
                        ).orEmpty(),
                        dataSyncId = data.getStringExtra(
                            YtLoginActivity.EXTRA_DATA_SYNC_ID,
                        ).orEmpty(),
                        authUser = "0",
                        // Filled in by Dart once it has asked YouTube who this
                        // is — the name lives in a browse response, and the
                        // renderer parsing for those is all on that side.
                        accountName = "",
                    ),
                )
                pending?.success(true)
            }
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private companion object {
        const val CHANNEL = "codes.afk.sunoh/ytmusic"
        const val LOCAL_CHANNEL = "codes.afk.sunoh/localmedia"
        const val SYNC_CHANNEL = "codes.afk.sunoh/sync"
        const val AUTH_CHANNEL = "codes.afk.sunoh/ytauth"
        const val LOGIN_REQUEST = 4711
    }
}
