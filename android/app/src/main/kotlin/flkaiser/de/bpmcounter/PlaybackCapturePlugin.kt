package flkaiser.de.bpmcounter

import android.app.Activity
import android.content.Intent
import android.media.projection.MediaProjectionConfig
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Bridge between Dart and [PlaybackCaptureService]:
 *
 * - `bpmcounter/playback_capture` (methods): `isSupported`, `start(sampleRate)` -> Boolean
 *   (false if the user declined the consent dialog), `stop`.
 * - `bpmcounter/playback_capture/audio` (events): 16-bit mono PCM chunks as byte arrays.
 */
class PlaybackCapturePlugin(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler, PlaybackCaptureService.Listener {

    private val methods = MethodChannel(messenger, "bpmcounter/playback_capture")
    private val events = EventChannel(messenger, "bpmcounter/playback_capture/audio")
    private val mainHandler = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var pendingStart: MethodChannel.Result? = null
    private var sampleRate = 44100

    init {
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> result.success(isSupported())
            "start" -> start(call.argument<Int>("sampleRate") ?: 44100, result)
            "stop" -> {
                stopService()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun isSupported() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q

    private fun start(rate: Int, result: MethodChannel.Result) {
        if (!isSupported()) {
            result.error("unsupported", "Capturing phone audio needs Android 10 or newer", null)
            return
        }
        if (pendingStart != null) {
            result.error("busy", "Already waiting for the user's consent", null)
            return
        }
        sampleRate = rate
        val manager = activity.getSystemService(MediaProjectionManager::class.java)
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            // Only the audio is used, so don't offer "share one app" (which
            // would limit the capture to that app's audio and confuse users).
            manager.createScreenCaptureIntent(MediaProjectionConfig.createConfigForDefaultDisplay())
        } else {
            manager.createScreenCaptureIntent()
        }
        pendingStart = result
        @Suppress("DEPRECATION")
        activity.startActivityForResult(intent, REQUEST_CODE)
    }

    /** Returns true if the result belonged to the capture consent dialog. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val result = pendingStart ?: return true
        pendingStart = null
        if (resultCode != Activity.RESULT_OK || data == null || !isSupported()) {
            result.success(false)
            return true
        }
        PlaybackCaptureService.listener = this
        val intent = Intent(activity, PlaybackCaptureService::class.java)
            .putExtra(PlaybackCaptureService.EXTRA_RESULT_CODE, resultCode)
            .putExtra(PlaybackCaptureService.EXTRA_RESULT_DATA, data)
            .putExtra(PlaybackCaptureService.EXTRA_SAMPLE_RATE, sampleRate)
        try {
            activity.startForegroundService(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("start_failed", e.message ?: e.toString(), null)
        }
        return true
    }

    private fun stopService() {
        activity.stopService(Intent(activity, PlaybackCaptureService::class.java))
    }

    // PlaybackCaptureService.Listener, called from the capture thread.
    override fun onAudio(pcm: ByteArray) {
        mainHandler.post { sink?.success(pcm) }
    }

    override fun onStopped(error: String?) {
        mainHandler.post {
            if (error != null) sink?.error("capture_failed", error, null) else sink?.endOfStream()
        }
    }

    // EventChannel.StreamHandler
    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    fun dispose() {
        stopService()
        if (PlaybackCaptureService.listener === this) PlaybackCaptureService.listener = null
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        pendingStart?.success(false)
        pendingStart = null
    }

    private companion object {
        const val REQUEST_CODE = 0xB9A
    }
}
