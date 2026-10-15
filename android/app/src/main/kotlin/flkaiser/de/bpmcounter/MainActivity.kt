package flkaiser.de.bpmcounter

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var playbackCapture: PlaybackCapturePlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        playbackCapture = PlaybackCapturePlugin(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        playbackCapture?.dispose()
        playbackCapture = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    // Receives the result of the screen capture consent dialog.
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (playbackCapture?.onActivityResult(requestCode, resultCode, data) == true) return
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }
}
