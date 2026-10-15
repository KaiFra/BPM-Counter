import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:record/record.dart';

import 'tempo_detector.dart';

/// Source of mono audio samples in the range -1..1.
abstract class AudioInput {
  /// Whether this source can be used on this device.
  Future<bool> isAvailable();

  /// Asks for the microphone permission if needed. Returns whether it is granted.
  Future<bool> requestPermission();

  /// Starts capturing. The stream ends when [stop] is called or the source
  /// stops by itself. Throws [CaptureDeclinedException] if the user cancels
  /// a system consent dialog.
  Future<Stream<Float64List>> start({required int sampleRate});

  Future<void> stop();

  Future<void> dispose();
}

/// Microphone input through the `record` plugin as raw 16-bit PCM.
///
/// Audio is only kept in memory for the analysis; nothing is written to disk.
class MicrophoneInput implements AudioInput {
  final AudioRecorder _recorder = AudioRecorder();

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> requestPermission() => _recorder.hasPermission();

  @override
  Future<Stream<Float64List>> start({required int sampleRate}) async {
    final decoder = Pcm16Decoder();
    final bytes = await _recorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
        // Speech processing would flatten exactly the dynamics we look for.
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
        androidConfig: const AndroidRecordConfig(
          // "Voice recognition" is the source Android requires to be free of
          // automatic gain control and noise reduction.
          audioSource: AndroidAudioSource.voiceRecognition,
          // Bluetooth headset handling would need extra permissions.
          manageBluetooth: false,
        ),
      ),
    );
    return bytes.map(decoder.convert);
  }

  @override
  Future<void> stop() => _recorder.stop();

  @override
  Future<void> dispose() => _recorder.dispose();
}

/// The user cancelled the system dialog that allows capturing.
class CaptureDeclinedException implements Exception {
  const CaptureDeclinedException();

  @override
  String toString() => 'Capture was declined';
}

/// The audio other apps play on this phone (Android 10+), captured by the
/// native PlaybackCaptureService. Android shows its screen capture consent
/// dialog on every start; only the audio is used.
class PhoneAudioInput implements AudioInput {
  PhoneAudioInput({
    this._methods = const MethodChannel('bpmcounter/playback_capture'),
    this._events = const EventChannel('bpmcounter/playback_capture/audio'),
    this._requestMicrophonePermission,
  });

  final MethodChannel _methods;
  final EventChannel _events;
  final Future<bool> Function()? _requestMicrophonePermission;
  AudioRecorder? _recorder;
  StreamSubscription<Object?>? _subscription;
  StreamController<Float64List>? _controller;

  @override
  Future<bool> isAvailable() async {
    try {
      return await _methods.invokeMethod<bool>('isSupported') ?? false;
    } on MissingPluginException {
      return false; // not on Android
    } on PlatformException {
      return false;
    }
  }

  // Android requires the microphone permission for capturing playback, too.
  @override
  Future<bool> requestPermission() =>
      _requestMicrophonePermission?.call() ?? (_recorder ??= AudioRecorder()).hasPermission();

  @override
  Future<Stream<Float64List>> start({required int sampleRate}) async {
    await stop();
    final decoder = Pcm16Decoder();
    final controller = StreamController<Float64List>();
    // Listen before starting so no audio (or an early error) gets lost.
    final subscription = _events.receiveBroadcastStream().listen(
      (data) => controller.add(decoder.convert(data as Uint8List)),
      onError: controller.addError,
      onDone: controller.close,
    );
    final bool started;
    try {
      started = await _methods.invokeMethod<bool>('start', {'sampleRate': sampleRate}) ?? false;
    } catch (_) {
      await subscription.cancel();
      rethrow;
    }
    if (!started) {
      await subscription.cancel();
      throw const CaptureDeclinedException();
    }
    _subscription = subscription;
    _controller = controller;
    return controller.stream;
  }

  @override
  Future<void> stop() async {
    final subscription = _subscription, controller = _controller;
    if (subscription == null) return;
    _subscription = null;
    _controller = null;
    await _methods.invokeMethod<void>('stop');
    await subscription.cancel();
    await controller?.close();
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _recorder?.dispose();
  }
}
