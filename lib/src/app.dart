import 'package:flutter/material.dart';

import 'audio/audio_input.dart';
import 'audio/listen_controller.dart';
import 'audio/settings_store.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart';

class BpmApp extends StatefulWidget {
  const BpmApp({super.key, this.audioInput, this.phoneAudioInput, this.settingsStore});

  /// Overridable for tests; default to the device microphone and the
  /// captured phone audio.
  final AudioInput? audioInput;
  final AudioInput? phoneAudioInput;
  final SettingsStore? settingsStore;

  @override
  State<BpmApp> createState() => _BpmAppState();
}

class _BpmAppState extends State<BpmApp> {
  late final ListenController _listenController = ListenController(
    input: widget.audioInput ?? MicrophoneInput(),
    phoneAudioInput: widget.phoneAudioInput ?? PhoneAudioInput(),
    store: widget.settingsStore ?? PreferencesSettingsStore(),
  )..init();

  @override
  void dispose() {
    _listenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BPM Counter',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      darkTheme: buildTheme(),
      themeMode: ThemeMode.dark,
      home: HomePage(listenController: _listenController),
    );
  }
}
