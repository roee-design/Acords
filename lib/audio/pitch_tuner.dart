import 'dart:async';
import 'dart:math';

import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import 'fft_processor.dart';
import 'frequency_utils.dart';
import 'ring_buffer.dart';

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

/// Mic → FFT → estimated pitch in cents relative to nearest note.
class PitchTuner {
  PitchTuner({
    this.sampleRate = 44100,
    this.fftSize = 8192,
    this.analysisIntervalMs = 60,
    this.silenceLevel = 0.008,
    this.minHz = 70,
    this.maxHz = 700,
  })  : _fftProcessor = FftProcessor(
          fftSize: fftSize,
          sampleRate: sampleRate.toDouble(),
        ),
        _ringBuffer = AudioRingBuffer(fftSize),
        _recorder = AudioRecorder();

  final int sampleRate;
  final int fftSize;
  final int analysisIntervalMs;
  final double silenceLevel;
  final double minHz;
  final double maxHz;

  final FftProcessor _fftProcessor;
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
  double _referenceA4Hz = 440;

  /// Optional open-string MIDI hints (6→1) from the catalog.
  List<(int stringNumber, int openMidi, String name)> _openStrings = const [];

  /// When set, cents are vs this open string and pitch search focuses nearby.
  int? _targetStringNumber;

  Stream<PitchReading> get readings => _controller.stream;
  bool get isListening => _isListening;
  bool get isDisposed => _disposed;
  int? get targetStringNumber => _targetStringNumber;

  void configure({
    double referenceA4Hz = 440,
    List<(int stringNumber, int openMidi, String name)> openStrings =
        const [],
  }) {
    _referenceA4Hz = referenceA4Hz;
    _openStrings = openStrings;
  }

  /// Lock tuning to an open string (`null` = auto among open strings only).
  void setTargetString(int? stringNumber) {
    _targetStringNumber = stringNumber;
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
    final level = frameRms(frame);
    final magnitudes = _fftProcessor.computeMagnitudes(frame);

    if (level < silenceLevel) {
      if (!_controller.isClosed) {
        _controller.add(PitchReading.silent(inputLevel: level));
      }
      return;
    }

    final reading = _estimatePitch(magnitudes, level);
    if (!_controller.isClosed) {
      _controller.add(reading);
    }
  }

  PitchReading _estimatePitch(List<double> magnitudes, double level) {
    final target = _targetOpenString();
    // Locked string: search near target Hz. Auto: broad peak then match open strings.
    final peak = target != null
        ? _findFrequencyNearTarget(magnitudes, target.$2)
        : _findDominantFrequency(magnitudes);
    if (peak == null) {
      return PitchReading.silent(inputLevel: level);
    }

    final hz = peak;
    // MIDI float from Hz (A4 = reference) — used for cent deviation vs open string.
    final midiFloat = 69 + 12 * (log(hz / _referenceA4Hz) / ln2);

    if (target != null) {
      // Locked string: cents relative to that open MIDI.
      final targetNote = _midiToNoteName(target.$2);
      return PitchReading(
        isSilent: false,
        inputLevel: level,
        frequencyHz: hz,
        noteName: targetNote,
        midi: target.$2,
        centsOffset: (midiFloat - target.$2) * 100,
        closestStringNumber: target.$1,
        closestStringLabel: stringLabel(target.$1),
        targetNoteName: targetNote,
      );
    }

    // Auto mode: match only the 6 open strings (±2 semitones).
    final closest = _closestOpenStringWithin(midiFloat, maxSemitones: 2);
    if (closest == null) {
      return PitchReading.awaitingOpenString(inputLevel: level);
    }

    final openMidi = closest.$2;
    final targetNote = _midiToNoteName(openMidi);
    return PitchReading(
      isSilent: false,
      inputLevel: level,
      frequencyHz: hz,
      noteName: targetNote,
      midi: openMidi,
      centsOffset: (midiFloat - openMidi) * 100,
      closestStringNumber: closest.$1,
      closestStringLabel: stringLabel(closest.$1),
      targetNoteName: targetNote,
    );
  }

  (int stringNumber, int openMidi, String name)? _targetOpenString() {
    final target = _targetStringNumber;
    if (target == null) return null;
    for (final s in _openStrings) {
      if (s.$1 == target) return s;
    }
    return null;
  }

  /// Peak-pick in 70–700 Hz; prefer fundamental when a strong harmonic is detected.
  double? _findDominantFrequency(List<double> magnitudes) {
    final binWidth = sampleRate / fftSize;
    final minBin = max(1, (minHz / binWidth).floor());
    final maxBin = min(magnitudes.length - 1, (maxHz / binWidth).ceil());

    var bestBin = -1;
    var bestEnergy = 0.0;
    for (var bin = minBin; bin <= maxBin; bin++) {
      final e = magnitudes[bin];
      if (e > bestEnergy) {
        bestEnergy = e;
        bestBin = bin;
      }
    }

    if (bestBin < 0 || bestEnergy <= 0) return null;

    var hz = _refineBinToHz(magnitudes, bestBin, binWidth);

    // If this looks like a harmonic of a lower fundamental in range, shift down.
    // For low strings (<160 Hz), require H1/H2/H3 support before accepting.
    for (var divisor = 2; divisor <= 4; divisor++) {
      final candidateHz = hz / divisor;
      if (candidateHz < minHz) break;
      final fundEnergy = _neighborhoodPeak(
        magnitudes,
        candidateHz,
        halfWidthHz: 8,
        minBin: minBin,
        maxBin: maxBin,
        binWidth: binWidth,
      );
      final supportRatio = candidateHz < 160 ? 0.22 : 0.35;
      if (fundEnergy > bestEnergy * supportRatio) {
        final supported = candidateHz < 160
            ? _hasLowStringHarmonicSupport(
                magnitudes,
                candidateHz,
                minBin: minBin,
                maxBin: maxBin,
                binWidth: binWidth,
              )
            : true;
        if (supported) {
          hz = candidateHz;
          break;
        }
      }
    }

    if (hz < 160 &&
        !_hasLowStringHarmonicSupport(
          magnitudes,
          hz,
          minBin: minBin,
          maxBin: maxBin,
          binWidth: binWidth,
        )) {
      // Weak-mic low fundamentals often hide under H2/H3; rebuild from overtones.
      final rebuilt = _rebuildLowFundamentalFromHarmonics(
        magnitudes,
        hz,
        minBin: minBin,
        maxBin: maxBin,
        binWidth: binWidth,
      );
      if (rebuilt != null) {
        hz = rebuilt;
      }
    }

    return hz.clamp(minHz, maxHz);
  }

  /// When a string is locked: look near its open Hz (and harmonics → fundamental).
  double? _findFrequencyNearTarget(
    List<double> magnitudes,
    int targetMidi,
  ) {
    final targetHz = midiToHz(targetMidi, a4Hz: _referenceA4Hz);
    final binWidth = sampleRate / fftSize;
    final minBin = max(1, (minHz / binWidth).floor());
    final maxBin = min(magnitudes.length - 1, (maxHz / binWidth).ceil());

    // Guitar fundamentals are often weak; always score H1/H2/H3 and map back.
    // Low strings (<160 Hz) especially need the full harmonic series.
    var bestScore = 0.0;
    double? bestFundamental;

    for (final harmonic in [1, 2, 3]) {
      final centerHz = targetHz * harmonic;
      if (centerHz < minHz || centerHz > maxHz) continue;

      // Wide window so a very flat/sharp string still locks (±3 semitones).
      final windowHz = targetHz * 0.2;
      final startBin = max(
        minBin,
        ((centerHz - windowHz) / binWidth).floor(),
      );
      final endBin = min(
        maxBin,
        ((centerHz + windowHz) / binWidth).ceil(),
      );

      var localBestBin = -1;
      var localBestEnergy = 0.0;
      for (var bin = startBin; bin <= endBin; bin++) {
        final e = magnitudes[bin];
        if (e > localBestEnergy) {
          localBestEnergy = e;
          localBestBin = bin;
        }
      }
      if (localBestBin < 0 || localBestEnergy <= 0) continue;

      // Prefer lower harmonics slightly (fundamental clarity).
      // For low strings, boost H2/H3 weight so weak mics still lock.
      final harmonicWeight =
          targetHz < 160 ? (harmonic == 1 ? 1.0 : 1.15 / harmonic) : 1.0 / harmonic;
      final score = localBestEnergy * harmonicWeight;
      if (score > bestScore) {
        bestScore = score;
        final peakHz = _refineBinToHz(magnitudes, localBestBin, binWidth);
        bestFundamental = peakHz / harmonic;
      }
    }

    if (bestFundamental == null) return null;
    return bestFundamental.clamp(minHz, maxHz);
  }

  bool _hasLowStringHarmonicSupport(
    List<double> magnitudes,
    double fundamentalHz, {
    required int minBin,
    required int maxBin,
    required double binWidth,
  }) {
    final h1 = _neighborhoodPeak(
      magnitudes,
      fundamentalHz,
      halfWidthHz: 8,
      minBin: minBin,
      maxBin: maxBin,
      binWidth: binWidth,
    );
    final h2 = _neighborhoodPeak(
      magnitudes,
      fundamentalHz * 2,
      halfWidthHz: 10,
      minBin: minBin,
      maxBin: maxBin,
      binWidth: binWidth,
    );
    final h3 = _neighborhoodPeak(
      magnitudes,
      fundamentalHz * 3,
      halfWidthHz: 12,
      minBin: minBin,
      maxBin: maxBin,
      binWidth: binWidth,
    );
    final series = h1 + h2 * 0.75 + h3 * 0.5;
    return series > 0 && (h2 > h1 * 0.2 || h3 > h1 * 0.15 || h1 > 0);
  }

  double? _rebuildLowFundamentalFromHarmonics(
    List<double> magnitudes,
    double observedHz, {
    required int minBin,
    required int maxBin,
    required double binWidth,
  }) {
    // Try interpreting the observed peak as H2 or H3 of a low open string.
    for (final harmonic in [2, 3]) {
      final candidate = observedHz / harmonic;
      if (candidate < minHz || candidate >= 160) continue;
      if (_hasLowStringHarmonicSupport(
        magnitudes,
        candidate,
        minBin: minBin,
        maxBin: maxBin,
        binWidth: binWidth,
      )) {
        return candidate;
      }
    }
    return null;
  }

  double _refineBinToHz(
    List<double> magnitudes,
    int bestBin,
    double binWidth,
  ) {
    var refinedBin = bestBin.toDouble();
    if (bestBin > 0 && bestBin < magnitudes.length - 1) {
      final y0 = magnitudes[bestBin - 1];
      final y1 = magnitudes[bestBin];
      final y2 = magnitudes[bestBin + 1];
      final denom = y0 - 2 * y1 + y2;
      if (denom.abs() > 1e-12) {
        refinedBin = bestBin + (y0 - y2) / (2 * denom);
      }
    }
    return refinedBin * binWidth;
  }

  double _neighborhoodPeak(
    List<double> magnitudes,
    double hz, {
    required double halfWidthHz,
    required int minBin,
    required int maxBin,
    required double binWidth,
  }) {
    final candidateBin = hzToBin(hz, fftSize, sampleRate.toDouble());
    final halfWidth = max(1, (halfWidthHz / binWidth).ceil());
    final start = max(minBin, candidateBin - halfWidth);
    final end = min(maxBin, candidateBin + halfWidth);
    var peak = 0.0;
    for (var b = start; b <= end; b++) {
      peak = max(peak, magnitudes[b]);
    }
    return peak;
  }

  /// Nearest catalog open string within [maxSemitones], else null.
  (int stringNumber, int openMidi, String name)? _closestOpenStringWithin(
    double midiFloat, {
    required double maxSemitones,
  }) {
    if (_openStrings.isEmpty) return null;

    var best = _openStrings.first;
    var bestDiff = (midiFloat - best.$2).abs();
    for (final s in _openStrings) {
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
    'C',
    'C#',
    'D',
    'D#',
    'E',
    'F',
    'F#',
    'G',
    'G#',
    'A',
    'A#',
    'B',
  ];

  static String _midiToNoteName(int midi) {
    final name = _names[midi % 12];
    final octave = (midi ~/ 12) - 1;
    return '$name$octave';
  }
}
