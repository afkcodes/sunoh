package codes.afk.sunoh.background

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Whether Android will let this app keep playing once it is backgrounded.
 *
 * ## Why this exists
 *
 * A user reported playback dying in the background. The foreground service was
 * being created correctly — right type, right capability, promoted while the
 * activity was visible — and Android was stripping it about thirteen seconds
 * later anyway. Nothing in the app called `stopForeground`; nothing was logged;
 * no exception was raised. The cause was a single AppOps entry on that phone:
 *
 *     RUN_ANY_IN_BACKGROUND: ignore
 *
 * That is Android's "this app is restricted" flag, and while it is set the
 * platform revokes foreground-service status on backgrounding. It is set by the
 * user under Battery > Restricted, and — the part that makes this worth
 * detecting — it is also set *silently* by the battery managers OEMs ship on
 * Motorola, Xiaomi, Samsung and OnePlus. The listener never chose it and has no
 * reason to suspect it.
 *
 * From inside the app the symptom is indistinguishable from a bug in the app:
 * the media session goes on reporting PLAYING while the audio has stopped.
 * Reading the flag turns an invisible OS setting into a sentence someone can
 * act on.
 *
 * ## Reading it
 *
 * `ActivityManager.isBackgroundRestricted` is the public reading of that flag —
 * no permission, no prompt, no hidden constant. (`OPSTR_RUN_ANY_IN_BACKGROUND`
 * itself is `@hide`, so it cannot be named directly.) It agrees with what
 * `adb shell cmd appops get <pkg> RUN_ANY_IN_BACKGROUND` prints, which is how
 * the original diagnosis was eventually made.
 */
object BackgroundPolicyBridge {
    private const val TAG = "BackgroundPolicy"
    private const val CHANNEL = "codes.afk.sunoh/background"

    /** Matches the Dart enum in `lib/audio/background_policy.dart`. */
    private const val OK = "ok"
    private const val RESTRICTED = "restricted"
    private const val UNKNOWN = "unknown"

    /**
     * `restricted` when the OS will strip our foreground service, `ok` when it
     * will not, `unknown` when the platform refuses to say.
     *
     * Deliberately not throwing: a player must not fail to start because it
     * could not read a diagnostic about itself.
     */
    fun backgroundStatus(context: Context): String {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
            ?: return UNKNOWN
        return try {
            // The public reading of the same AppOps entry. `OPSTR_RUN_ANY_IN_BACKGROUND`
            // itself is a hidden constant, but this is documented as reporting
            // exactly that state, and it matches what
            // `adb shell cmd appops get <pkg> RUN_ANY_IN_BACKGROUND` prints —
            // which is how the original diagnosis was made.
            if (Build.VERSION.SDK_INT >= 28) {
                if (am.isBackgroundRestricted) RESTRICTED else OK
            } else {
                // The restriction did not exist before Pie.
                OK
            }
        } catch (e: Exception) {
            Log.w(TAG, "could not read background restriction", e)
            UNKNOWN
        }
    }

    /**
     * Whether the app is exempt from Doze.
     *
     * Reported separately because it is a *different* setting with a similar
     * symptom, and telling someone to change the wrong one wastes their time.
     * Battery optimisation delays background work; the AppOps restriction above
     * removes the foreground service outright.
     */
    fun batteryOptimized(context: Context): Boolean {
        val power = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            ?: return false
        return !power.isIgnoringBatteryOptimizations(context.packageName)
    }

    /**
     * Opens the per-app settings page where the restriction can be lifted.
     *
     * There is no intent that deep-links to the Battery section itself, and no
     * API to request the restriction be removed — unlike battery optimisation,
     * which has [Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS]. App
     * details is as close as the platform allows, so the UI has to say which
     * switch to look for once it lands there.
     */
    fun openAppSettings(context: Context): Boolean = try {
        context.startActivity(
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.fromParts("package", context.packageName, null),
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
        true
    } catch (e: Exception) {
        Log.w(TAG, "could not open app settings", e)
        false
    }

    /** Wires `status` and `openSettings` onto [messenger]. */
    fun register(context: Context, messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(
                    mapOf(
                        "background" to backgroundStatus(context),
                        "batteryOptimized" to batteryOptimized(context),
                    ),
                )

                "openSettings" -> result.success(openAppSettings(context))
                else -> result.notImplemented()
            }
        }
    }
}
