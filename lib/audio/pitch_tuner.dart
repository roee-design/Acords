import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import 'fft_processor.dart';
import 'frequency_utils.dart';
import 'ring_buffer.dart';
import 'spectrum_frame.dart';
import 'yin_pitch.dart';

/// Live pitch reading for the standalone string tuner.
class PitchReading {
  const PitchReading({
    required this.isSilent,
    required this.inputLevel,
    this.frequencyHz,
    this.noteName,
    this.midi,
    this.centsOffset,
    this.closestStringNumber,
    this.closestStringLabel,
    this.targetNoteName,
    this.awaitingOpenString = false,
  });

  factory PitchReading.silent({double inputLevel = 0}) {
    return PitchReading(isSilent: true, inputLevel: inputLevel);
  }

  /// Sound detected but not within ±2 semitones of any open string (auto mode).
  factory PitchReading.awaitingOpenString({required double inputLevel}) {
    return PitchReading(
      isSilent: false,
      inputLevel: inputLevel,
      awaitingOpenString: true,
    );
  }

  final bool isSilent;
  final double inputLevel;
  final double? frequencyHz;
  final String? noteName;
  final int? midi;

  /// Signed cents vs open-string target. Positive = sharp.
  final double? centsOffset;
  final int? closestStringNumber;
  final String? closestStringLabel;

  /// Expected open-string note (locked string or auto-matched open string).
  final String? targetNoteName;

  /// True in auto mode when pitch is not near any open string.
  final bool awaitingOpenString;

  bool get isInTune {
    final cents = centsOffset;
    return cents != null && cents.abs() <= 5;
  }
}

/// Mic-free tuner logic: frame of samples → [PitchReading].
///
/// Two stages:
/// 1. YIN on the waveform decides *which* note is sounding. It works on the
///    period, so a low string whose fundamental the phone mic barely picks up
///    is still read in the right octave (where FFT peak-picking jumps to the
///    2nd/3rd harmonic). With a string selected the search is limited to ±8
///    semitones around it.
/// 2. The frequency is then refined on an 8192-point spectrum at that note's
///    fundamental (or 2nd/3rd harmonic ÷ k when the fundamental is weak).
///    YIN alone is biased sharp by string inharmonicity (upper partials run
///    slightly sharp), which costs several cents — too much for a tuner.
///
/// In auto mode the reading is matched to the nearest open string
/// (±2 semitones). A median over the last 3 readings steadies the needle.
class TunerPitchEstimator {
  TunerPitchEstimator({
    this.sampleRate = 44100,
    this.minHz = 70,
    this.maxHz = 700,
    this.fftSize = 8192,
  })  : _yin = YinPitchEstimator(sampleRate: sampleRate),
        _fft = FftProcessor(fftSize: fftSize, sampleRate: sampleRate.toDouble());

  final int sampleRate;
  final double minHz;
  final double maxHz;
  final int fftSize;
  final YinPitchEstimator _yin;
  final FftProcessor _fft;

  double referenceA4Hz = 440;
  List<(int stringNumber, int openMidi, String name)> openStrings = const [];
  int? targetStringNumber;

  final List<double> _recentHz = <double>[];

  int get requiredSamples => _yin.requiredSamples(minHz);

  void resetSmoothing() => _recentHz.clear();

  /// [frame]: newest samples, ideally [fftSize] long (YIN uses the tail).
  PitchReading estimate(Float32List frame, double level) {
    final target = _targetOpenString();
    double? hz;
    if (target != null) {
      final targetHz = midiToHz(target.$2, a4Hz: referenceA4Hz);
      final factor = pow(2, 8 / 12).toDouble();
      hz = _yin
          .estimate(
            frame,
            minHz: max(minHz * 0.9, targetHz / factor),
            maxHz: targetHz * factor,
          )
          ?.hz;
    } else {
      hz = _yin.estimate(frame, minHz: minHz, maxHz: maxHz)?.hz;
    }
    if (hz == null) {
      _recentHz.clear();
      return PitchReading.silent(inputLevel: level);
    }
    hz = _refineWithSpectrum(frame, hz);

    // Median of the last 3 estimates, reset when the pitch jumps (new note).
    if (_recentHz.isNotEmpty &&
        (1200 * log(hz / _recentHz.last) / ln2).abs() > 80) {
      _recentHz.clear();
    }
    _recentHz.add(hz);
    if (_recentHz.length > 3) _recentHz.removeAt(0);
    final sorted = [..._recentHz]..sort();
    final smoothHz = sorted[sorted.length ~/ 2];

    final midiFloat = 69 + 12 * (log(smoothHz / referenceA4Hz) / ln2);

    if (target != null) {
      final targetNote = _midiToNoteName(target.$2);
      return PitchReading(
        isSilent: false,
        inputLevel: level,
        frequencyHz: smoothHz,
        noteName: targetNote,
        midi: target.$2,
        centsOffset: (midiFloat - target.$2) * 100,
        closestStringNumber: target.$1,
        closestStringLabel: stringLabel(target.$1),
        targetNoteName: targetNote,
      );
    }

    final closest = _closestOpenStringWithin(midiFloat, maxSemitones: 2);
    if (closest == null) {
      return PitchReading.awaitingOpenString(inputLevel: level);
    }
    final openMidi = closest.$2;
    final targetNote = _midiToNoteName(openMidi);
    return PitchReading(
      isSilent: false,
      inputLevel: level,
      frequencyHz: smoothHz,
      noteName: targetNote,
      midi: openMidi,
      centsOffset: (midiFloat - openMidi) * 100,
      closestStringNumber: closest.$1,
      closestStringLabel: stringLabel(closest.$1),
      targetNoteName: targetNote,
    );
  }

  double _refineWithSpectrum(Float32List frame, double yinHz) {
    if (frame.length < fftSize ~/ 2) return yinHz;
    final spectrum = SpectrumFrame(
      magnitudes: frame.length >= fftSize
          ? _fft.computeMagnitudes(
              Float32List.sublistView(frame, frame.length - fftSize),
            )
          : _fft.computeMagnitudesOfTail(frame, frame.length),
      fftSize: fftSize,
      sampleRate: sampleRate.toDouble(),
      inputLevel: 0,
    );
    final peaks = <(int k, SpectralPeak peak)>[];
    for (final k in const [1, 2, 3]) {
      final center = yinHz * k;
      final tolerance = max(center * 0.035, spectrum.binHz * 1.5); // ~60 ¢
      final p = spectrum.peakNear(center, tolerance);
      if (p != null) peaks.add((k, p));
    }
    if (peaks.isEmpty) return yinHz;
    var strongest = peaks.first.$2.magnitude;
    for (final p in peaks) {
      strongest = max(strongest, p.$2.magnitude);
    }
    // Lowest harmonic that is clearly present: it has the least inharmonic
    // stretch and the finest relative resolution after dividing by k.
    for (final (k, p) in peaks) {
      if (p.magnitude >= strongest * 0.2) {
        final refined = p.hz / k;
        // Guard against grabbing a neighbouring partial.
        if ((1200 * log(refined / yinHz) / ln2).abs() <= 60) return refined;
      }
    }
    return yinHz;
  }

  (int stringNumber, int openMidi, String name)? _targetOpenString() {
    final target = targetStringNumber;
    if (target == null) return null;
    for (final s in openStrings) {
      if (s.$1 == target) return s;
    }
    return null;
  }

  /// Nearest catalog open string within [maxSemitones], else null.
  (int stringNumber, int openMidi, String name)? _closestOpenStringWithin(
    double midiFloat, {
    required double maxSemitones,
  }) {
    if (openStrings.isEmpty) return null;
    var best = openStrings.first;
    var bestDiff = (midiFloat - best.$2).abs();
    for (final s in openStrings) {
      final diff = (midiFloat - s.$2).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = s;
      }
    }
    if (bestDiff > maxSemitones) return null;
    return best;
  }

  static const _names = [
    'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B',
  ];

  static String _midiToNoteName(int midi) {
    final name = _names[midi % 12];
    final octave = (midi ~/ 12) - 1;
    return '$name$octave';
  }
}

/// Mic → YIN → pitch in cents relative to the target / nearest open string.
class PitchTuner {
  PitchTuner({
    this.sampleRate = 44100,
    this.fftSize = 8192,
    this.analysisIntervalMs = 60,
    this.silenceLevel = 0.008,
    this.minHz = 70,
    this.maxHz = 700,
  })  : _estimator = TunerPitchEstimator(
          sampleRate: sampleRate,
          minHz: minHz,
          maxHz: maxHz,
        ),
        _ringBuffer = AudioRingBuffer(fftSize),
        _recorder = AudioRecorder();

  final int sampleRate;
  final int fftSize;
  final int analysisIntervalMs;
  final double silenceLevel;
  final double minHz;
  final double maxHz;

  final TunerPitchEstimator _estimator;
  final AudioRingBuffer _ringBuffer;
  final AudioRecorder _recorder;

  final StreamController<PitchReading> _controller =
      StreamController<PitchReading>.broadcast();

  StreamSubscription<List<int>>? _pcmSubscription;
  DateTime? _lastAnalysisTime;
  var _isListening = false;
  var _disposed = false;
  /// Bumped on every stop/dispose so a late [start] cannot leave the mic on.
  var _sessionId = 0;
  Future<void>? _operation;

  Stream<PitchReading> get readings => _controller.stream;
  bool get isListening => _isListening;
  bool get isDisposed => _disposed;
  int? get targetStringNumber => _estimator.targetStringNumber;

  void configure({
    double referenceA4Hz = 440,
    List<(int stringNumber, int openMidi, String name)> openStrings =
        const [],
  }) {
    _estimator
      ..referenceA4Hz = referenceA4Hz
      ..openStrings = openStrings;
  }

  /// Lock tuning to an open string (`null` = auto among open strings only).
  void setTargetString(int? stringNumber) {
    _estimator
      ..targetStringNumber = stringNumber
      ..resetSmoothing();
  }

  Future<bool> ensureMicrophonePermission() async {
    final recordGranted = await _recorder.hasPermission();
    if (recordGranted) return true;
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<void> start() {
    return _enqueue(() => _startImpl());
  }

  Future<void> stop() {
    return _enqueue(() => _stopImpl());
  }

  Future<void> dispose() {
    _disposed = true;
    _sessionId++;
    return _enqueue(() async {
      await _stopImpl();
      if (!_controller.isClosed) {
        await _controller.close();
      }
      await _recorder.dispose();
    });
  }

  Future<void> _enqueue(Future<void> Function() op) {
    final previous = _operation;
    final next = () async {
      if (previous != null) {
        try {
          await previous;
        } catch (_) {}
      }
      await op();
    }();
    _operation = next;
    return next;
  }

  Future<void> _startImpl() async {
    if (_disposed) return;
    if (!await ensureMicrophonePermission()) {
      throw StateError(
        'Microphone permission was denied. Enable it in system settings.',
      );
    }
    if (_disposed) return;
    if (_isListening) return;

    final session = ++_sessionId;

    try {
      final stream = await _recorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: sampleRate,
          numChannels: 1,
          autoGain: false,
          echoCancel: false,
          noiseSuppress: false,
        ),
      );

      if (_disposed || session != _sessionId) {
        await _recorder.stop();
        return;
      }

      _ringBuffer.clear();
      _lastAnalysisTime = null;
      _isListening = true;

      _pcmSubscription = stream.listen(
        _onPcmChunk,
        onError: (Object error) {
          if (!_controller.isClosed) {
            _controller.addError(error);
          }
        },
      );

      if (!_controller.isClosed) {
        _controller.add(PitchReading.silent());
      }
    } catch (error) {
      _isListening = false;
      await _pcmSubscription?.cancel();
      _pcmSubscription = null;
      try {
        if (await _recorder.isRecording()) {
          await _recorder.stop();
        }
      } catch (_) {}
      if (_disposed || session != _sessionId) return;
      throw StateError('Microphone failed to start: $error');
    }
  }

  Future<void> _stopImpl() async {
    _sessionId++;
    _isListening = false;

    await _pcmSubscription?.cancel();
    _pcmSubscription = null;

    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
    } catch (_) {}

    _ringBuffer.clear();
    _lastAnalysisTime = null;

    if (!_disposed && !_controller.isClosed) {
      _controller.add(PitchReading.silent());
    }
  }

  void _onPcmChunk(List<int> pcmBytes) {
    if (!_isListening) return;

    _ringBuffer.writePcm16LeBytes(pcmBytes);
    if (!_ringBuffer.isFull) return;

    final now = DateTime.now();
    if (_lastAnalysisTime != null &&
        now.difference(_lastAnalysisTime!).inMilliseconds <
            analysisIntervalMs) {
      return;
    }
    _lastAnalysisTime = now;

    final frame = _ringBuffer.toOrderedFrame();
    // Level from the newest ~60 ms so the silence gate reacts quickly.
    final recent = Float32List.sublistView(
      frame,
      max(0, frame.length - _estimator.requiredSamples),
    );
    final level = frameRms(recent);

    if (level < silenceLevel) {
      _estimator.resetSmoothing();
      if (!_controller.isClosed) {
        _controller.add(PitchReading.silent(inputLevel: level));
      }
      return;
    }

    final reading = _estimator.estimate(frame, level);
    if (!_controller.isClosed) {
      _controller.add(reading);
    }
  }
}
