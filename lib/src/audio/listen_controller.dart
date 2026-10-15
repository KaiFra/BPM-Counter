import 'dart:async';

import 'package:flutter/foundation.dart';

import 'audio_input.dart';
import 'detector_settings.dart';
import 'settings_store.dart';
import 'tempo_detector.dart';

enum ListenStatus { idle, starting, listening, permissionDenied, error }

enum AudioSource { microphone, phoneAudio }

/// Connects an [AudioInput] to a [TempoDetector] and exposes the results to
/// the UI.
class ListenController extends ChangeNotifier {
  ListenController({
    required this._input,
    required this._store,
    this._phoneAudioInput,
    this.sampleRate = 44100,
    this.updateInterval = const Duration(milliseconds: 500),
  });

  final AudioInput _input;
  final AudioInput? _phoneAudioInput;
  AudioInput? _runningInput;
  final SettingsStore _store;
  final int sampleRate;

  /// How often (in audio time) the tempo estimate is refreshed.
  final Duration updateInterval;

  /// Number of envelope frames kept for the live graph (~2 seconds).
  static const graphLength = 400;

  late final TempoDetector _detector = _createDetector(DetectorSettings.defaults);
  final TempoSmoother _smoother = TempoSmoother();
  StreamSubscription<Float64List>? _subscription;
  bool _disposed = false;
  int _framesAtLastEstimate = 0;

  AudioSource _source = AudioSource.microphone;
  AudioSource get source => _source;

  /// Whether the phone audio source can be offered (Android 10+).
  bool _phoneAudioAvailable = false;
  bool get phoneAudioAvailable => _phoneAudioAvailable;

  ListenStatus _status = ListenStatus.idle;
  ListenStatus get status => _status;
  bool get isListening => _status == ListenStatus.listening;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  DetectorSettings get settings => _detector.settings;

  /// Smoothed tempo, or null while there is no reliable reading.
  double? _bpm;
  double? get bpm => _bpm;

  /// Confidence of the latest estimate, 0..1.
  double _confidence = 0;
  double get confidence => _confidence;

  /// Increments on every detected beat; the UI uses it to flash.
  int _beats = 0;
  int get beats => _beats;

  double get levelDb => _detector.levelDb;

  /// 0..1 progress until the first reading is possible.
  double get warmUp {
    final needed = _detector.minSeconds * _detector.envelopeRate;
    return (_detector.framesProcessed / needed).clamp(0.0, 1.0);
  }

  Float64List get envelope => _detector.recentEnvelope(graphLength);

  TempoDetector _createDetector(DetectorSettings settings) =>
      TempoDetector(sampleRate: sampleRate.toDouble(), settings: settings);

  /// Loads the stored settings. Call once after creation.
  Future<void> init() async {
    try {
      final stored = await _store.load();
      if (_disposed) return;
      _detector.settings = stored;
      notifyListeners();
    } catch (_) {
      // Keep the defaults if storage is unavailable.
    }
    try {
      _phoneAudioAvailable = await _phoneAudioInput?.isAvailable() ?? false;
    } catch (_) {
      _phoneAudioAvailable = false;
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> updateSettings(DetectorSettings settings) async {
    final before = _detector.settings;
    _detector.settings = settings;
    if (_detector.settings == before) return;
    _framesAtLastEstimate = 0;
    _clearReading();
    notifyListeners();
    try {
      await _store.save(_detector.settings);
    } catch (_) {
      // Not being able to remember the settings is not worth an error.
    }
  }

  /// Switches between microphone and phone audio; stops listening first.
  Future<void> setSource(AudioSource source) async {
    if (source == _source) return;
    if (source == AudioSource.phoneAudio && !_phoneAudioAvailable) return;
    // stop() switches to idle right away; releasing the input may take longer.
    final stopping = stop();
    _source = source;
    _detector.reset();
    _clearReading();
    if (_status != ListenStatus.idle) _setStatus(ListenStatus.idle);
    notifyListeners();
    await stopping;
  }

  Future<void> toggle() => isListening || _status == ListenStatus.starting ? stop() : start();

  Future<void> start() async {
    if (_status == ListenStatus.listening || _status == ListenStatus.starting) return;
    final input = _source == AudioSource.phoneAudio ? _phoneAudioInput! : _input;
    _setStatus(ListenStatus.starting);
    try {
      if (!await input.requestPermission()) {
        _setStatus(ListenStatus.permissionDenied);
        return;
      }
      // The user may have stopped (or left the app) while the dialog was open.
      if (_status != ListenStatus.starting || _disposed) return;
      _runningInput = input;
      final stream = await input.start(sampleRate: sampleRate);
      if (_status != ListenStatus.starting || _disposed) {
        await input.stop();
        return;
      }
      _detector.reset();
      _smoother.reset();
      _clearReading();
      _framesAtLastEstimate = 0;
      _subscription = stream.listen(
        _onSamples,
        onError: (Object error) => _fail(error),
        onDone: () {
          // The source ended by itself, e.g. capture stopped from the status bar.
          if (isListening) {
            _subscription = null;
            _runningInput = null;
            _setStatus(ListenStatus.idle);
          }
        },
      );
      _setStatus(ListenStatus.listening);
    } on CaptureDeclinedException {
      _runningInput = null;
      _setStatus(ListenStatus.idle);
    } catch (error) {
      _fail(error);
    }
  }

  Future<void> stop() async {
    if (_status != ListenStatus.listening && _status != ListenStatus.starting) return;
    _setStatus(ListenStatus.idle);
    // Cancelling takes effect immediately; no need to wait for it.
    unawaited(_subscription?.cancel());
    _subscription = null;
    final input = _runningInput ?? _input;
    _runningInput = null;
    try {
      await input.stop();
    } catch (_) {
      // Already stopped.
    }
  }

  void _onSamples(Float64List samples) {
    _beats += _detector.addSamples(samples);
    final framesPerUpdate = (updateInterval.inMicroseconds / 1e6 * _detector.envelopeRate).round();
    if (_detector.framesProcessed - _framesAtLastEstimate >= framesPerUpdate) {
      _framesAtLastEstimate = _detector.framesProcessed;
      final estimate = _detector.estimate();
      _confidence = estimate?.confidence ?? 0;
      _bpm = _smoother.add(estimate);
    }
    notifyListeners();
  }

  void _clearReading() {
    _smoother.reset();
    _bpm = null;
    _confidence = 0;
  }

  void _fail(Object error) {
    _errorMessage = error.toString();
    _subscription?.cancel();
    _subscription = null;
    (_runningInput ?? _input).stop().catchError((_) {});
    _runningInput = null;
    _setStatus(ListenStatus.error);
  }

  void _setStatus(ListenStatus status) {
    if (_disposed) return;
    _status = status;
    if (status != ListenStatus.error) _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    _input.dispose();
    _phoneAudioInput?.dispose();
    super.dispose();
  }
}
