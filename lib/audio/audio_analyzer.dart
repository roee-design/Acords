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
  var _isListening = false;
  var _disposed = false;
  /// Bumped on every stop/dispose so a late [start] cannot leave the mic on.
  var _sessionId = 0;
  Future<void>? _operation;

  Stream<ChordFeedback> get feedbackStream => _feedbackController.stream;

  bool get isListening => _isListening;
  bool get isDisposed => _disposed;

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
  }) {
    _freePlayMode = false;
    _freePlayChords = const [];
    _targetChord = chord;
    _referenceA4Hz = referenceA4Hz;
    _matcher ??= ChordMatcher(fftProcessor: _fftProcessor);

    resetAnalysisState(gracePeriod: gracePeriod);

    _emitIdleFeedback(chord);
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
        // Hold the matcher closed during grace; discard audio so no stale frame remains.
        _ringBuffer.clear();
        return;
      }
      _ignoreDetectionsUntil = null;
      _ringBuffer.clear();
      _fftProcessor.reset();
      _lastAnalysisTime = null;
      return;
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

    if (!_feedbackController.isClosed) {
      _feedbackController.add(feedback);
    }
  }
}
