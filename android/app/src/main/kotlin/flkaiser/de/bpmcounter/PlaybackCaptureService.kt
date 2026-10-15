package flkaiser.de.bpmcounter

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioPlaybackCaptureConfiguration
import android.media.AudioRecord
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.annotation.RequiresApi

/**
 * Captures the audio other apps play (Android 10+, AudioPlaybackCapture).
 *
 * Android only allows this inside a foreground service of type
 * "mediaProjection", after the user accepted the screen capture dialog.
 * The audio is passed on in memory and never stored.
 */
class PlaybackCaptureService : Service() {

    interface Listener {
        fun onAudio(pcm: ByteArray)
        fun onStopped(error: String?)
    }

    companion object {
        const val EXTRA_RESULT_CODE = "resultCode"
        const val EXTRA_RESULT_DATA = "resultData"
        const val EXTRA_SAMPLE_RATE = "sampleRate"
        private const val CHANNEL_ID = "playback_capture"
        private const val NOTIFICATION_ID = 1

        @Volatile
        var listener: Listener? = null
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var session: Any? = null // CaptureSession, typed loosely for API < 29

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            stopSelf()
            return START_NOT_STICKY
        }
        startCapture(intent)
        return START_NOT_STICKY
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun startCapture(intent: Intent) {
        // Must run before getMediaProjection() on Android 14+.
        startForeground(
            NOTIFICATION_ID,
            buildNotification(),
            ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION,
        )
        (session as? CaptureSession)?.close()
        session = null
        try {
            val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, 0)
            val data = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(EXTRA_RESULT_DATA, Intent::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(EXTRA_RESULT_DATA)
            } ?: throw IllegalStateException("Missing capture consent")
            val sampleRate = intent.getIntExtra(EXTRA_SAMPLE_RATE, 44100)
            val manager = getSystemService(MediaProjectionManager::class.java)
            val projection = manager.getMediaProjection(resultCode, data)
                ?: throw IllegalStateException("Screen capture was not allowed")
            val newSession = CaptureSession(projection, sampleRate)
            session = newSession
            newSession.start()
        } catch (e: Exception) {
            finish(e.message ?: e.toString())
        }
    }

    /** Ends the capture, informs Dart and stops the service. Main thread only. */
    private fun finish(error: String?) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) (session as? CaptureSession)?.close()
        session = null
        listener?.onStopped(error)
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        if (session != null) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) (session as? CaptureSession)?.close()
            session = null
            listener?.onStopped(null)
        }
        super.onDestroy()
    }

    private fun buildNotification(): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Phone audio analysis", NotificationManager.IMPORTANCE_LOW),
        )
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE,
        )
        return Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("BPM Counter")
            .setContentText("Analysing phone audio")
            .setContentIntent(open)
            .setOngoing(true)
            .build()
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private inner class CaptureSession(
        private val projection: MediaProjection,
        private val sampleRate: Int,
    ) {
        private var record: AudioRecord? = null
        private var thread: Thread? = null

        @Volatile
        private var running = false

        @Volatile
        private var closed = false

        private val callback = object : MediaProjection.Callback() {
            // The user stopped sharing (status bar chip or notification).
            override fun onStop() = ended(null)
        }

        // RECORD_AUDIO is requested by the Dart side before starting.
        @SuppressLint("MissingPermission")
        fun start() {
            projection.registerCallback(callback, mainHandler)
            val config = AudioPlaybackCaptureConfiguration.Builder(projection)
                .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
                .addMatchingUsage(AudioAttributes.USAGE_GAME)
                .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN)
                .build()
            val format = AudioFormat.Builder()
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setSampleRate(sampleRate)
                .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                .build()
            val minBuffer = AudioRecord.getMinBufferSize(
                sampleRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
            )
            val newRecord = AudioRecord.Builder()
                .setAudioFormat(format)
                .setBufferSizeInBytes(maxOf(minBuffer * 2, 16384))
                .setAudioPlaybackCaptureConfig(config)
                .build()
            if (newRecord.state != AudioRecord.STATE_INITIALIZED) {
                newRecord.release()
                throw IllegalStateException("Audio capture could not be initialised")
            }
            record = newRecord
            newRecord.startRecording()
            running = true
            thread = Thread({ readLoop(newRecord) }, "playback-capture").also { it.start() }
        }

        private fun readLoop(record: AudioRecord) {
            val buffer = ByteArray(4096) // ~46 ms at 44.1 kHz
            while (running) {
                val read = record.read(buffer, 0, buffer.size)
                when {
                    read > 0 -> listener?.onAudio(buffer.copyOf(read))
                    read < 0 -> {
                        if (running) ended("Audio capture failed ($read)")
                        return
                    }
                }
            }
        }

        private fun ended(error: String?) {
            mainHandler.post { if (session === this) finish(error) }
        }

        fun close() {
            if (closed) return
            closed = true
            running = false
            try {
                record?.stop() // unblocks read()
            } catch (ignored: IllegalStateException) {
                // Not recording (anymore).
            }
            thread?.let { if (it !== Thread.currentThread()) it.join(500) }
            record?.release()
            record = null
            projection.unregisterCallback(callback)
            projection.stop()
        }
    }
}
