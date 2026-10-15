import 'dart:async';
import 'dart:typed_data';

import 'package:bpmcounter/src/audio/audio_input.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const methods = MethodChannel('bpmcounter/playback_capture');
const events = EventChannel('bpmcounter/playback_capture/audio');

/// Stands in for the native PlaybackCapturePlugin.
class FakeNative {
  FakeNative() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call);
      return switch (call.method) {
        'isSupported' => supported,
        'start' => consent,
        _ => null,
      };
    });
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (arguments, sink) => this.sink = sink,
        onCancel: (arguments) {
          sink = null;
          cancels++;
        },
      ),
    );
  }

  final calls = <MethodCall>[];
  bool supported = true;
  bool consent = true;
  MockStreamHandlerEventSink? sink;
  int cancels = 0;

  List<String> get methodNames => [for (final c in calls) c.method];
}

Uint8List pcm(List<int> samples) {
  final data = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(i * 2, samples[i], Endian.little);
  }
  return data.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeNative native;
  late PhoneAudioInput input;

  setUp(() {
    native = FakeNative();
    input = PhoneAudioInput(requestMicrophonePermission: () async => true);
  });

  tearDown(() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(methods, null);
    messenger.setMockStreamHandler(events, null);
  });

  test('availability comes from the native side', () async {
    expect(await input.isAvailable(), isTrue);
    native.supported = false;
    expect(await input.isAvailable(), isFalse);
  });

  test('is unavailable where the native side is missing (iOS, tests)', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      methods,
      null,
    );
    expect(await PhoneAudioInput().isAvailable(), isFalse);
  });

  test('streams decoded PCM from the capture', () async {
    final stream = await input.start(sampleRate: 48000);
    expect(native.calls.last.method, 'start');
    expect(native.calls.last.arguments, {'sampleRate': 48000});

    final received = <Float64List>[];
    stream.listen(received.add);
    native.sink!.success(pcm([16384, -32768]));
    native.sink!.success(pcm([0]));
    await pumpEventQueue();
    expect(received, [
      [0.5, -1.0],
      [0.0],
    ]);
  });

  test('declining the consent dialog throws and stops listening', () async {
    native.consent = false;
    await expectLater(input.start(sampleRate: 44100), throwsA(isA<CaptureDeclinedException>()));
    expect(native.cancels, 1);
    expect(native.sink, isNull);
  });

  test('stop ends the native capture and the stream', () async {
    final stream = await input.start(sampleRate: 44100);
    final done = Completer<void>();
    stream.listen(null, onDone: done.complete);
    await input.stop();
    expect(native.methodNames, contains('stop'));
    expect(native.cancels, 1);
    await done.future;
  });

  test('capture stopped by the system ends the stream', () async {
    final stream = await input.start(sampleRate: 44100);
    final done = Completer<void>();
    stream.listen(null, onDone: done.complete);
    native.sink!.endOfStream();
    await done.future;
  });

  test('native errors reach the stream', () async {
    final stream = await input.start(sampleRate: 44100);
    final error = Completer<Object>();
    stream.listen(null, onError: (Object e) => error.complete(e));
    native.sink!.error(code: 'capture_failed', message: 'boom');
    expect(await error.future, isA<PlatformException>());
  });

  test('stop without start does nothing', () async {
    await input.stop();
    expect(native.methodNames, isNot(contains('stop')));
  });
}
