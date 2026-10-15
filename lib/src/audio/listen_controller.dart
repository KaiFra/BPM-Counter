import 'dart:async';

import 'package:flutter/foundation.dart';

import 'audio_input.dart';
import 'detector_settings.dart';
import 'settings_store.dart';
import 'tempo_detector.dart';

enum ListenStatus { idle, starting, listening, permissionDenied, error }

/// Connects an [AudioInput] to a [TempoDetector] and exposes the results to
/// the UI.
class ListenController extends ChangeNotifier {
  ListenController({
    required this._input,
    required this._store,
    this.sampleRate = 44100,
    this.updateInterval = const Duration(milliseconds: 500),
  });

  final AudioInput _input;
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

  Future<void> toggle() => isListening || _status == ListenStatus.starting ? stop() : start();

  Future<void> start() async {
    if (_status == ListenStatus.listening || _status == ListenStatus.starting) return;
    _setStatus(ListenStatus.starting);
    try {
      if (!await _input.requestPermission()) {
        _setStatus(ListenStatus.permissionDenied);
        return;
      }
      // The user may have stopped (or left the app) while the dialog was open.
      if (_status != ListenStatus.starting || _disposed) return;
      final stream = await _input.start(sampleRate: sampleRate);
      if (_status != ListenStatus.starting || _disposed) {
        await _input.stop();
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
          if (isListening) _setStatus(ListenStatus.idle);
        },
      );
      _setStatus(ListenStatus.listening);
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
    try {
      await _input.stop();
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
    _input.stop().catchError((_) {});
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
    super.dispose();
  }
}
