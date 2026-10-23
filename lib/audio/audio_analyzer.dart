import 'dart:async';
import 'dart:math';

import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../chord/chord_matcher.dart';
import '../models/chord_definition.dart';
import '../models/feedback_result.dart';
import 'chord_detection_engine.dart';
import 'onset_detector.dart';

export 'chord_detection_engine.dart' show ChordHit;

/// Microphone capture feeding [ChordDetectionEngine]; publishes per-frame
/// [ChordFeedback] (live UI) and [ChordHit]s (a target chord that was actually
/// strummed — what practice, blitz, songs and strumming advance on).
class AudioAnalyzer {
  AudioAnalyzer({
    this.sampleRate = 44100,
    this.fftSize = 8192,
    OnsetDetector? onsetDetector,
  })  : _engine = ChordDetectionEngine(
          sampleRate: sampleRate,
          fftSize: fftSize,
          onsetDetector: onsetDetector,
        ),
        _recorder = AudioRecorder();

  final int sampleRate;
  final int fftSize;

  final ChordDetectionEngine _engine;
  final AudioRecorder _recorder;

  final StreamController<ChordFeedback> _feedbackController =
      StreamController<ChordFeedback>.broadcast();
  final StreamController<ChordHit> _hitController =
      StreamController<ChordHit>.broadcast();
  final StreamController<DateTime> _onsetController =
      StreamController<DateTime>.broadcast();

  StreamSubscription<List<int>>? _pcmSubscription;
  ChordDefinition? _targetChord;
  var _freePlayMode = false;
  double _currentA4 = 440;
  var _isListening = false;
  var _disposed = false;
  /// Bumped on every stop/dispose so a late [start] cannot leave the mic on.
  var _sessionId = 0;
  Future<void>? _operation;

  ChordMatcher get _matcher => _engine.matcher;

  Stream<ChordFeedback> get feedbackStream => _feedbackController.stream;

  /// Confirmed strummed chords (see [ChordDetectionEngine]).
  Stream<ChordHit> get hitStream => _hitController.stream;

  /// Every detected strum attack (wall-clock time of the attack) — used by
  /// the rhythm game to judge timing.
  Stream<DateTime> get onsetStream => _onsetController.stream;

  bool get isListening => _isListening;
  bool get isDisposed => _disposed;

  /// Chord currently listened for (null in free play).
  String? get targetChordId => _freePlayMode ? null : _targetChord?.id;

  /// Wall-clock time of the latest strum attack, if any.
  DateTime? get lastOnsetAt {
    final strum = _engine.lastStrumSample;
    if (strum == null) return null;
    final ageMs = (_engine.sampleClock - strum) * 1000 ~/ sampleRate;
    return DateTime.now().subtract(Duration(milliseconds: ageMs));
  }

  /// True when a strum attack was detected within [window].
  bool hasOnsetWithin(Duration window) {
    final onset = lastOnsetAt;
    if (onset == null) return false;
    return DateTime.now().difference(onset) <= window;
  }

  /// Nominal FFT frame duration — used by transitions timing compensation.
  double get fftBufferLatencyMs => (fftSize / sampleRate) * 1000.0;

  /// True while a grace / blank window suppresses analysis.
  bool get isBlanking => _engine.isIgnoring;

  Future<bool> ensureMicrophonePermission() async {
    final recordGranted = await _recorder.hasPermission();
    if (recordGranted) {
      return true;
    }

    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  /// Listens for [chord]. Only strums made after this call can produce a
  /// [ChordHit] for it, so no extra grace period is needed between targets;
  /// [gracePeriod] still suppresses analysis if a caller wants it.
  void setTargetChord(
    ChordDefinition chord, {
    double referenceA4Hz = 440,
    Duration? gracePeriod,
    bool resetAnalysis = true,
  }) {
    _freePlayMode = false;
    _targetChord = chord;
    _currentA4 = referenceA4Hz;
    _engine.setTarget(
      chord,
      referenceA4Hz: referenceA4Hz,
      graceSamples: _samplesFor(gracePeriod),
    );
    if (resetAnalysis) {
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
    _targetChord = chords.first;
    _currentA4 = referenceA4Hz;
    _engine.setFreePlay(chords, referenceA4Hz: referenceA4Hz);
    if (!_isListening) {
      _emitFreePlayIdle();
    }
  }

  void resetAnalysisState({Duration? gracePeriod}) {
    if (gracePeriod != null) {
      _engine.ignoreFor(_samplesFor(gracePeriod));
    }
  }

  /// Short mute so metronome click energy does not reach the analysis.
  void blankInput({
    Duration duration = const Duration(milliseconds: 70),
  }) {
    _engine.ignoreFor(_samplesFor(duration));
  }

  int _samplesFor(Duration? d) =>
      d == null ? 0 : d.inMicroseconds * sampleRate ~/ 1000000;

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
      if (!_hitController.isClosed) {
        await _hitController.close();
      }
      if (!_onsetController.isClosed) {
        await _onsetController.close();
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

      _engine.reset();
      _sampleZeroWallUs = null;
      // Re-arm the current target on the fresh clock.
      final target = _targetChord;
      if (!_freePlayMode && target != null) {
        _engine.setTarget(target, referenceA4Hz: _currentA4);
      }
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
    if (_feedbackController.isClosed) return;
    _feedbackController.add(_matcher.idleFeedback(chord));
  }

  void _emitFreePlayIdle() {
    if (_feedbackController.isClosed) return;
    _feedbackController.add(_matcher.freePlayWaiting(0));
  }

  /// Wall-clock time (µs since epoch) of sample 0 of the current session.
  ///
  /// Audio arrives in chunks, sometimes late, never early — so the smallest
  /// "arrival time − audio time" seen is the best estimate of the true
  /// mapping. Using it (instead of "now" when a chunk is processed) removes
  /// the delivery and processing jitter from every strum timestamp; what is
  /// left is a constant input latency that calibration measures once.
  int? _sampleZeroWallUs;

  void _onPcmChunk(List<int> pcmBytes) {
    if (!_isListening) return;
    final arrivalUs = DateTime.now().microsecondsSinceEpoch;
    final frames = _engine.addPcm16(pcmBytes);
    final audioUs = _engine.sampleClock * 1000000 ~/ sampleRate;
    final candidate = arrivalUs - audioUs;
    final current = _sampleZeroWallUs;
    // Track the minimum, but let it creep up slowly (0.1 ms per chunk) so a
    // drift between the audio and system clocks cannot freeze a stale value.
    _sampleZeroWallUs =
        current == null ? candidate : min(current + 100, candidate);
    final onsets = _engine.takeOnsets();
    if (onsets.isNotEmpty && !_onsetController.isClosed) {
      final zero = _sampleZeroWallUs!;
      for (final sample in onsets) {
        _onsetController.add(
          DateTime.fromMicrosecondsSinceEpoch(
            zero + sample * 1000000 ~/ sampleRate,
          ),
        );
      }
    }
    for (final frame in frames) {
      if (_feedbackController.isClosed) return;
      _feedbackController.add(frame.feedback);
      final hit = frame.hit;
      if (hit != null && !_hitController.isClosed) {
        // ignore: avoid_print
        print(
          '[Acords Audio] hit ${hit.chordId} '
          'latency=${hit.latencyMs.toStringAsFixed(0)}ms',
        );
        _hitController.add(hit);
      }
    }
  }
}
