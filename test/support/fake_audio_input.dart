import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bpmcounter/src/audio/audio_input.dart';

/// An [AudioInput] driven by the test instead of a microphone.
class FakeAudioInput implements AudioInput {
  FakeAudioInput({this.grantPermission = true});

  bool grantPermission;
  int permissionRequests = 0;
  int? startedWithSampleRate;
  bool disposed = false;
  StreamController<Float64List>? _controller;

  bool get isRunning => _controller != null;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return grantPermission;
  }

  @override
  Future<Stream<Float64List>> start({required int sampleRate}) async {
    startedWithSampleRate = sampleRate;
    _controller = StreamController<Float64List>();
    return _controller!.stream;
  }

  /// Delivers [samples] in microphone-sized chunks.
  void emit(Float64List samples, {int chunk = 4096}) {
    for (var i = 0; i < samples.length; i += chunk) {
      _controller!.add(Float64List.sublistView(samples, i, math.min(samples.length, i + chunk)));
    }
  }

  void fail(Object error) => _controller!.addError(error);

  @override
  Future<void> stop() async {
    final controller = _controller;
    _controller = null;
    await controller?.close();
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await stop();
  }
}
