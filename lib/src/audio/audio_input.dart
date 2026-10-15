import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import 'tempo_detector.dart';

/// Source of mono audio samples in the range -1..1.
abstract class AudioInput {
  /// Asks for the microphone permission if needed. Returns whether it is granted.
  Future<bool> requestPermission();

  /// Starts capturing. The stream ends when [stop] is called.
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
