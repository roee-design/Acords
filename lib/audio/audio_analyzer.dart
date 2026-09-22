import 'dart:async';

import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../chord/chord_matcher.dart';
import '../models/chord_definition.dart';
import '../models/feedback_result.dart';
import 'fft_processor.dart';
import 'frequency_utils.dart';
import 'ring_buffer.dart';

/// Microphone capture, ring-buffer framing, FFT, and chord feedback stream.
class AudioAnalyzer {
  AudioAnalyzer({
    this.sampleRate = 44100,
    this.fftSize = 8192,
    this.analysisIntervalMs = 80,
  })  : _fftProcessor = FftProcessor(
          fftSize: fftSize,
          sampleRate: sampleRate.toDouble(),
        ),
        _ringBuffer = AudioRingBuffer(fftSize),
        _recorder = AudioRecorder();

  final int sampleRate;
  final int fftSize;
  final int analysisIntervalMs;

  final FftProcessor _fftProcessor;
  final AudioRingBuffer _ringBuffer;
  final AudioRecorder _recorder;

  final StreamController<ChordFeedback> _feedbackController =
      StreamController<ChordFeedback>.broadcast();

  StreamSubscription<List<int>>? _pcmSubscription;
  ChordDefinition? _targetChord;
  List<ChordDefinition> _freePlayChords = const [];
  var _freePlayMode = false;
  double _referenceA4Hz = 440;
  ChordMatcher? _matcher;
  DateTime? _lastAnalysisTime;
  DateTime? _ignoreDetectionsUntil;
  DateTime? _lastWaitingLogAt;
  var _isListening = false;
  var _disposed = false;
  /// Bumped on every stop/dispose so a late [start] cannot leave the mic on.
  var _sessionId = 0;
  Future<void>? _operation;

  Stream<ChordFeedback> get feedbackStream => _feedbackController.stream;

  bool get isListening => _isListening;
  bool get isDisposed => _disposed;

  /// Nominal FFT frame duration — used by transitions timing compensation.
  double get fftBufferLatencyMs => (fftSize / sampleRate) * 1000.0;

  /// True while blank/grace is discarding analysis (PCM may still accumulate).
  bool get isBlanking =>
      _ignoreDetectionsUntil != null &&
      DateTime.now().isBefore(_ignoreDetectionsUntil!);

  Future<bool> ensureMicrophonePermission() async {
    final recordGranted = await _recorder.hasPermission();
    if (recordGranted) {
      return true;
    }

    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  void setTargetChord(
    ChordDefinition chord, {
    double referenceA4Hz = 440,
    Duration? gracePeriod,
    bool resetAnalysis = true,
  }) {
    _freePlayMode = false;
    _freePlayChords = const [];
    _targetChord = chord;
    _referenceA4Hz = referenceA4Hz;
    _matcher ??= ChordMatcher(fftProcessor: _fftProcessor);

    if (resetAnalysis) {
      resetAnalysisState(gracePeriod: gracePeriod);
      _emitIdleFeedback(chord);
    }
  }

  void setFreePlayCatalog(
    List<ChordDefinition> chords, {
    double referenceA4Hz = 440,
  }) {
    if (chords.isEmpty) {
      throw ArgumentError('Free play requires at least one chord.');
    }
    _freePlayMode = true;
    _freePlayChords = chords;
    _targetChord = chords.first;
    _referenceA4Hz = referenceA4Hz;
    _matcher ??= ChordMatcher(fftProcessor: _fftProcessor);
    resetAnalysisState();

    if (!_isListening) {
      _emitFreePlayIdle();
    }
  }

  void resetAnalysisState({Duration? gracePeriod}) {
    _ringBuffer.clear();
    _fftProcessor.reset();
    _lastAnalysisTime = null;
    _ignoreDetectionsUntil = gracePeriod == null
        ? null
        : DateTime.now().add(gracePeriod);
    if (gracePeriod != null) {
      // ignore: avoid_print
      print(
        '[Acords Audio] grace START ${gracePeriod.inMilliseconds}ms '
        '(clear buffer once; PCM fills during grace)',
      );
    }
  }

  /// Short mute so metronome click energy does not reach the FFT.
  /// Clears the buffer once at the start; PCM still accumulates during blank
  /// so the ring can be full when analysis resumes (avoids +FFT refill delay).
  void blankInput({
    Duration duration = const Duration(milliseconds: 70),
  }) {
    final until = DateTime.now().add(duration);
    if (_ignoreDetectionsUntil == null ||
        until.isAfter(_ignoreDetectionsUntil!)) {
      _ignoreDetectionsUntil = until;
    }
    _ringBuffer.clear();
    _fftProcessor.reset();
    _lastAnalysisTime = null;
    // ignore: avoid_print
    print('[Acords Audio] blank ${duration.inMilliseconds}ms (buffer cleared once)');
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
      if (!_feedbackController.isClosed) {
        await _feedbackController.close();
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
        } catch (_) {
          // Ignore prior failures; this op still runs.
        }
      }
      await op();
    }();
    _operation = next;
    return next;
  }

  Future<void> _startImpl() async {
    if (_disposed) return;
    if (_targetChord == null && !_freePlayMode) {
      throw StateError('Call setTargetChord() or setFreePlayCatalog() before start().');
    }
    final chord = _targetChord;
    if (chord == null) {
      throw StateError('No chord catalog configured for free play.');
    }

    if (!await ensureMicrophonePermission()) {
      throw StateError(
        'Microphone permission was denied. Enable it in system settings.',
      );
    }

    if (_disposed) return;
    if (_isListening) {
      return;
    }

    final session = ++_sessionId;

    try {
      // Raw PCM16 mono — no AGC/echo cancel so guitar dynamics stay natural.
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

      // Stop raced ahead while we awaited startStream — tear down immediately.
      if (_disposed || session != _sessionId) {
        await _recorder.stop();
        return;
      }

      resetAnalysisState();
      _isListening = true;

      _pcmSubscription = stream.listen(
        _onPcmChunk,
        onError: (Object error) {
          if (!_feedbackController.isClosed) {
            _feedbackController.addError(error);
          }
        },
      );

      if (_freePlayMode) {
        _emitFreePlayIdle();
      } else {
        _emitIdleFeedback(chord);
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

    resetAnalysisState();

    if (_disposed || _feedbackController.isClosed) return;

    if (_freePlayMode) {
      _emitFreePlayIdle();
    } else {
      final chord = _targetChord;
      if (chord != null) {
        _emitIdleFeedback(chord);
      }
    }
  }

  void _emitIdleFeedback(ChordDefinition chord) {
    final matcher = _matcher;
    if (matcher == null || _feedbackController.isClosed) {
      return;
    }
    _feedbackController.add(matcher.idleFeedback(chord));
  }

  void _emitFreePlayIdle() {
    final matcher = _matcher;
    if (matcher == null || _feedbackController.isClosed) {
      return;
    }
    _feedbackController.add(matcher.freePlayWaiting(0));
  }

  void _onPcmChunk(List<int> pcmBytes) {
    final matcher = _matcher;
    if (matcher == null || !_isListening) {
      return;
    }
    if (!_freePlayMode && _targetChord == null) {
      return;
    }

    _ringBuffer.writePcm16LeBytes(pcmBytes);

    final ignoreUntil = _ignoreDetectionsUntil;
    if (ignoreUntil != null) {
      if (DateTime.now().isBefore(ignoreUntil)) {
        // Skip FFT during blank/grace, but keep filling the ring buffer so a
        // strum on the tick is ready to analyze as soon as the window ends.
        return;
      }
      _ignoreDetectionsUntil = null;
      // Keep PCM already accumulated; only reset spectral state.
      _fftProcessor.reset();
      _lastAnalysisTime = null;
      // ignore: avoid_print
      print(
        '[Acords Audio] grace/blank END — resume FFT '
        '(bufferFull=${_ringBuffer.isFull})',
      );
      // Fall through and analyze this chunk if the ring is already full.
    }

    if (!_ringBuffer.isFull) {
      return;
    }

    final now = DateTime.now();
    if (_lastAnalysisTime != null &&
        now.difference(_lastAnalysisTime!).inMilliseconds <
            analysisIntervalMs) {
      return;
    }
    _lastAnalysisTime = now;

    final frame = _ringBuffer.toOrderedFrame();
    // Hann-windowed FFT → magnitude bins (~5.4 Hz resolution at 44.1 kHz / 8192).
    final magnitudes = _fftProcessor.computeMagnitudes(frame);
    final level = frameRms(frame);

    final feedback = _freePlayMode
        ? matcher.identifyBestChord(
            chords: _freePlayChords,
            magnitudes: magnitudes,
            referenceA4Hz: _referenceA4Hz,
            inputLevel: level,
          )
        : matcher.evaluate(
            chord: _targetChord!,
            magnitudes: magnitudes,
            referenceA4Hz: _referenceA4Hz,
            inputLevel: level,
          );

    if (feedback.matchStatus == ChordMatchStatus.waiting) {
      final last = _lastWaitingLogAt;
      if (last == null || now.difference(last).inMilliseconds >= 500) {
        _lastWaitingLogAt = now;
        // ignore: avoid_print
        print(
          '[Acords Audio] blocked RMS/waiting level=${level.toStringAsFixed(4)} '
          't_detect=${now.millisecondsSinceEpoch}',
        );
      }
    } else if (feedback.matchStatus == ChordMatchStatus.perfect ||
        feedback.matchStatus == ChordMatchStatus.close) {
      // ignore: avoid_print
      print(
        '[Acords Audio] detect ${feedback.matchStatus.name} '
        'chord=${feedback.chordName} level=${level.toStringAsFixed(4)} '
        't_detect=${now.millisecondsSinceEpoch}',
      );
    }

    if (!_feedbackController.isClosed) {
      _feedbackController.add(feedback);
    }
  }
}
