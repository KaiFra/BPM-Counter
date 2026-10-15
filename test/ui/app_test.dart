import 'dart:typed_data';

import 'package:bpmcounter/src/app.dart';
import 'package:bpmcounter/src/audio/detector_settings.dart';
import 'package:bpmcounter/src/audio/settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_audio_input.dart';
import '../support/signals.dart';

const phone = Size(411, 914);

Future<void> pumpApp(
  WidgetTester tester, {
  Size size = phone,
  FakeAudioInput? input,
  FakeAudioInput? phoneInput,
  SettingsStore? store,
}) async {
  tester.view.devicePixelRatio = 2.625;
  tester.view.physicalSize = size * 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    BpmApp(
      audioInput: input ?? FakeAudioInput(),
      // Unavailable by default, like on devices below Android 10.
      phoneAudioInput: phoneInput ?? FakeAudioInput(available: false),
      settingsStore: store ?? MemorySettingsStore(),
    ),
  );
  await tester.pumpAndSettle();
}

/// Taps the pad with an exact event timestamp.
Future<void> tapPadAt(WidgetTester tester, int milliseconds) async {
  final center = tester.getCenter(find.byKey(const Key('tap-pad')));
  final pointer = TestPointer(milliseconds + 1);
  await tester.sendEventToBinding(
    pointer.down(center, timeStamp: Duration(milliseconds: milliseconds)),
  );
  await tester.sendEventToBinding(pointer.up(timeStamp: Duration(milliseconds: milliseconds + 40)));
  await tester.pump();
}

String bpmText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('bpm-value'))).data!;

void main() {
  group('Tap mode', () {
    testWidgets('starts empty with instructions', (tester) async {
      await pumpApp(tester);
      expect(find.text('BPM Counter'), findsOneWidget);
      expect(bpmText(tester), '–');
      expect(find.text('Tap the circle along with the beat'), findsOneWidget);
      expect(find.text('No previous session'), findsOneWidget);
    });

    testWidgets('tapping shows the tempo and stats', (tester) async {
      await pumpApp(tester);
      for (var i = 0; i < 9; i++) {
        await tapPadAt(tester, 1000 + i * 500);
      }
      expect(bpmText(tester), '120.0');
      expect(find.text('9'), findsOneWidget); // taps
      expect(find.text('Pause for 3 s to start over'), findsOneWidget);
    });

    testWidgets('reset moves the session to "previous"', (tester) async {
      await pumpApp(tester);
      for (var i = 0; i < 5; i++) {
        await tapPadAt(tester, i * 600);
      }
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      expect(bpmText(tester), '–');
      expect(
        tester.widget<Text>(find.byKey(const Key('previous-session'))).data,
        'Previous: 100.0 BPM · 5 taps · peak 100.0',
      );
    });

    testWidgets('space bar taps, escape resets', (tester) async {
      await pumpApp(tester);
      for (var i = 0; i < 4; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump(const Duration(milliseconds: 400));
      }
      expect(find.text('4'), findsOneWidget);
      expect(bpmText(tester), '150.0');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(bpmText(tester), '–');
      expect(find.textContaining('Previous: 150.0 BPM'), findsOneWidget);
    });
  });

  group('Listen mode', () {
    testWidgets('detects the tempo from the (fake) microphone', (tester) async {
      final input = FakeAudioInput();
      await pumpApp(tester, input: input);
      await tester.tap(find.text('Listen'));
      await tester.pumpAndSettle();
      expect(find.text('Tap the circle to start listening'), findsOneWidget);

      await tester.tap(find.byKey(const Key('listen-pad')));
      await tester.pump();
      expect(input.isRunning, isTrue);
      expect(find.text('STOP'), findsOneWidget);

      input.emit(drumLoop(bpm: 128, seconds: 8));
      await tester.pump(const Duration(milliseconds: 50));
      expect(bpmText(tester), '128.0');
      expect(find.textContaining('Confidence'), findsOneWidget);

      await tester.tap(find.byKey(const Key('listen-pad')));
      await tester.pump(const Duration(milliseconds: 50));
      expect(input.isRunning, isFalse);
      expect(find.text('LISTEN'), findsOneWidget);
    });

    testWidgets('switching back to tap mode releases the microphone', (tester) async {
      final input = FakeAudioInput();
      await pumpApp(tester, input: input);
      await tester.tap(find.text('Listen'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('listen-pad')));
      await tester.pump();
      expect(input.isRunning, isTrue);

      await tester.tap(find.text('Tap'));
      await tester.pumpAndSettle();
      expect(input.isRunning, isFalse);
    });

    testWidgets('going to the background releases the microphone', (tester) async {
      final input = FakeAudioInput();
      await pumpApp(tester, input: input);
      await tester.tap(find.text('Listen'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('listen-pad')));
      await tester.pump();
      expect(input.isRunning, isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump(const Duration(milliseconds: 50));
      expect(input.isRunning, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });

    testWidgets('explains a denied permission', (tester) async {
      await pumpApp(tester, input: FakeAudioInput(grantPermission: false));
      await tester.tap(find.text('Listen'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('listen-pad')));
      await tester.pump();
      expect(find.textContaining('Microphone access was denied'), findsOneWidget);
    });

    testWidgets('filter sheet changes and stores the settings', (tester) async {
      final store = MemorySettingsStore();
      await pumpApp(tester, store: store);
      await tester.tap(find.text('Listen'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('filter-summary'))).data,
        'Kick & bass · below 200 Hz · 60–200 BPM',
      );

      await tester.tap(find.byKey(const Key('open-filters')));
      await tester.pumpAndSettle();
      expect(find.text('Audio filters'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Hi-hats'));
      await tester.pumpAndSettle();
      expect(store.settings.highPassHz, 5000);
      expect(store.settings.lowPassHz, isNull);

      // Drag the low-pass slider from "Off" (right end) towards the middle.
      final lowPass = find.descendant(
        of: find.byKey(const Key('low-pass-slider')),
        matching: find.byType(Slider),
      );
      await tester.ensureVisible(lowPass);
      await tester.drag(lowPass, const Offset(-60, 0));
      await tester.pumpAndSettle();
      expect(store.settings.lowPassHz, isNotNull);
      expect(store.settings.lowPassHz!, greaterThan(store.settings.highPassHz!));

      await tester.ensureVisible(find.byKey(const Key('reset-filters')));
      await tester.tap(find.byKey(const Key('reset-filters')));
      await tester.pumpAndSettle();
      expect(store.settings, DetectorSettings.defaults);

      await tester.tapAt(const Offset(200, 20)); // outside the sheet
      await tester.pumpAndSettle();
      expect(find.text('Audio filters'), findsNothing);
    });

    testWidgets('remembers settings from the last launch', (tester) async {
      final store = MemorySettingsStore(FilterPreset.snare.applyTo(DetectorSettings.defaults));
      await pumpApp(tester, store: store);
      await tester.tap(find.text('Listen'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('filter-summary'))).data,
        startsWith('Snare & claps · 150 Hz – 3.0 kHz'),
      );
    });
  });

  group('Phone audio', () {
    Future<void> openListen(WidgetTester tester) async {
      await tester.tap(find.text('Listen'));
      await tester.pumpAndSettle();
    }

    testWidgets('the source switch only shows where capture is supported', (tester) async {
      await pumpApp(tester);
      await openListen(tester);
      expect(find.byKey(const Key('source-selector')), findsNothing);
      expect(find.byKey(const Key('source-help')), findsNothing);
    });

    testWidgets('listens to phone audio after switching', (tester) async {
      final mic = FakeAudioInput(), phone = FakeAudioInput();
      await pumpApp(tester, input: mic, phoneInput: phone);
      await openListen(tester);

      await tester.tap(find.text('Phone audio'));
      await tester.pumpAndSettle();
      expect(find.text('Play music in any app, then tap the circle'), findsOneWidget);

      await tester.tap(find.byKey(const Key('listen-pad')));
      await tester.pump(const Duration(milliseconds: 50));
      expect(phone.isRunning, isTrue);
      expect(mic.isRunning, isFalse);

      phone.emit(drumLoop(bpm: 131, seconds: 8));
      await tester.pump(const Duration(milliseconds: 50));
      expect(bpmText(tester), '131.0');

      // Switching back stops the capture.
      await tester.tap(find.text('Microphone'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(phone.isRunning, isFalse);
      expect(bpmText(tester), '–');
    });

    testWidgets('hints at blocked apps when there is no sound', (tester) async {
      final phone = FakeAudioInput();
      await pumpApp(tester, phoneInput: phone);
      await openListen(tester);
      await tester.tap(find.text('Phone audio'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('listen-pad')));
      await tester.pump(const Duration(milliseconds: 50));
      phone.emit(Float64List(44100 * 4)); // silence: capture blocked
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('blocks capture'), findsOneWidget);
    });

    testWidgets('declining the capture dialog goes back to idle', (tester) async {
      final phone = FakeAudioInput()..declineStart = true;
      await pumpApp(tester, phoneInput: phone);
      await openListen(tester);
      await tester.tap(find.text('Phone audio'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('listen-pad')));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('LISTEN'), findsOneWidget);
      expect(find.text('Play music in any app, then tap the circle'), findsOneWidget);
    });

    testWidgets('? explains the limitations', (tester) async {
      await pumpApp(tester, phoneInput: FakeAudioInput());
      await openListen(tester);
      await tester.tap(find.byKey(const Key('source-help')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('allow screen recording each time'), findsOneWidget);
      expect(find.textContaining('block this'), findsOneWidget);
      expect(find.textContaining('stops when you leave'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('Layout', () {
    const sizes = {
      'small phone': Size(320, 568),
      'phone': phone,
      'phone landscape': Size(914, 411),
      'foldable': Size(673, 841),
      'tablet landscape': Size(1280, 800),
    };
    for (final MapEntry(key: name, value: size) in sizes.entries) {
      testWidgets('renders both modes without overflow on a $name', (tester) async {
        // With the phone audio switch: the most crowded variant.
        await pumpApp(tester, size: size, phoneInput: FakeAudioInput());
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Listen'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byKey(const Key('listen-pad'))).shortestSide, greaterThan(140));
      });
    }
  });
}
