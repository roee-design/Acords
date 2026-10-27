import 'dart:math';
import 'dart:typed_data';

import '../chord/chord_matcher.dart';
import '../models/chord_definition.dart';
import '../models/feedback_result.dart';
import 'fft_processor.dart';
import 'onset_detector.dart';
import 'spectrum_frame.dart';

/// A confirmed, strummed chord: the target (or, in free play, the identified
/// chord) was matched perfectly in audio recorded after a fresh strum.
class ChordHit {
  const ChordHit({
    required this.chordId,
    required this.strumSample,
    required this.confirmSample,
    required this.sampleRate,
  });

  final String chordId;

  /// Sample clock of the strum attack that produced this hit.
  final int strumSample;

  /// Sample clock of the analysis frame that confirmed it.
  final int confirmSample;
  final int sampleRate;

  /// Strum → confirmation delay.
  double get latencyMs => (confirmSample - strumSample) * 1000 / sampleRate;
}

/// Spectrum of the first analysable span after a strum, with what was ringing
/// just before it — enough to check *what* was played (rhythm game).
class StrumCapture {
  const StrumCapture({
    required this.onsetSample,
    required this.frame,
    required this.residual,
  });

  final int onsetSample;
  final SpectrumFrame frame;

  /// Spectrum of the ~93 ms before the strum (same scale as [frame]).
  final List<double>? residual;
}

/// Result of one analysis step.
class EngineFrame {
  const EngineFrame({
    required this.feedback,
    required this.endSample,
    required this.afterStrum,
    this.hit,
  });

  final ChordFeedback feedback;
  final int endSample;

  /// True when the spectrum only contains audio from after the latest strum
  /// that belongs to the current target.
  final bool afterStrum;
  final ChordHit? hit;
}

/// Pure (mic-free) chord detection pipeline on a sample clock.
///
/// Samples go in, [EngineFrame]s come out. Timing never reads the wall clock,
/// so the same code runs on the phone and in offline tests.
///
/// Chord changes: after each strum the spectrum is taken only from the samples
/// recorded since that strum (growing, zero-padded window, capped at
/// [fftSize]). The previous chord's ringing tail therefore cannot leak into
/// the new chord's analysis, and a hit always needs a strum that happened
/// after the target was set — so a chord shared by two consecutive song steps,
/// or a ringing chord the next target happens to contain, never auto-advances.
class ChordDetectionEngine {
  ChordDetectionEngine({
    this.sampleRate = 44100,
    this.fftSize = 8192,
    this.hopSamples = 2048,
    this.minSegmentSamples = 3072,
    this.requiredPerfectFrames = 2,
    this.maxStrumAgeMs = 1500,
    this.strumClusterMs = 160,
    this.strumLookbackMs = 0,
    this.captureSamples = 5120,
    ChordMatcher? matcher,
    OnsetDetector? onsetDetector,
  })  : _fft = FftProcessor(fftSize: fftSize, sampleRate: sampleRate.toDouble()),
        _ring = Float32List(fftSize),
        _onsets = onsetDetector ?? OnsetDetector(sampleRate: sampleRate) {
    _matcher = matcher ?? ChordMatcher(fftProcessor: _fft);
  }

  final int sampleRate;
  final int fftSize;

  /// Analysis period (2048 ≈ 46 ms at 44.1 kHz).
  final int hopSamples;

  /// Shortest post-strum span analysed (3072 ≈ 70 ms): enough frequency
  /// resolution to separate the low strings.
  final int minSegmentSamples;

  /// Consecutive perfect post-strum frames needed for a hit.
  final int requiredPerfectFrames;

  /// A strum older than this no longer confirms a chord (fixing fingers on a
  /// ringing chord is not playing it).
  final int maxStrumAgeMs;

  /// Onsets closer than this belong to the same strum (string spread).
  final int strumClusterMs;

  /// Post-strum span (≈116 ms) a [StrumCapture] waits for, so a whole strum
  /// (strings follow each other over 60–140 ms) is in the spectrum. If the
  /// next strum comes sooner, the latest frame before it is used.
  final int captureSamples;

  /// Accept a strum that started this long *before* the target was set.
  final int strumLookbackMs;

  final FftProcessor _fft;
  final Float32List _ring;
  final OnsetDetector _onsets;
  late final ChordMatcher _matcher;

  static const int _attackSkipSamples = 441; // 10 ms of pick transient

  var _ringPos = 0;
  var _clock = 0;
  var _nextAnalysis = 0;

  ChordDefinition? _target;
  List<ChordDefinition>? _freePlay;
  double _a4 = 440;
  var _targetSetAt = 0;
  var _ignoreUntil = 0;

  int? _strumStart;
  int? _lastOnset;

  /// Spectrum of the audio just before [_strumStart] (previous chord's tail).
  List<double>? _residual;
  var _perfectRun = 0;
  var _hitConsumed = false;
  String? _runChordId;

  ChordMatcher get matcher => _matcher;

  final List<int> _pendingOnsets = <int>[];
  final List<StrumCapture> _pendingCaptures = <StrumCapture>[];
  var _captureDone = true;
  SpectrumFrame? _captureFrame;
  List<double>? _captureResidual;
  int? _captureOnset;

  /// Post-strum spectra captured since the last call (one per strum).
  List<StrumCapture> takeCaptures() {
    final out = List<StrumCapture>.of(_pendingCaptures);
    _pendingCaptures.clear();
    return out;
  }

  /// Strum attacks (sample clock) detected since the last call.
  List<int> takeOnsets() {
    final out = List<int>.of(_pendingOnsets);
    _pendingOnsets.clear();
    return out;
  }
  int get sampleClock => _clock;
  int? get lastStrumSample => _strumStart;
  ChordDefinition? get target => _target;
  bool get isFreePlay => _freePlay != null;
  bool get isIgnoring => _clock < _ignoreUntil;

  /// Sets the chord to listen for. Only strums after this call can hit it.
  void setTarget(
    ChordDefinition chord, {
    double referenceA4Hz = 440,
    int graceSamples = 0,
  }) {
    _target = chord;
    _freePlay = null;
    _a4 = referenceA4Hz;
    _targetSetAt = _clock;
    _ignoreUntil = _clock + graceSamples;
    _resetRun();
  }

  void setFreePlay(List<ChordDefinition> chords, {double referenceA4Hz = 440}) {
    if (chords.isEmpty) {
      throw ArgumentError('Free play requires at least one chord.');
    }
    _freePlay = chords;
    _target = chords.first;
    _a4 = referenceA4Hz;
    _targetSetAt = _clock;
    _ignoreUntil = 0;
    _resetRun();
  }

  /// Suppresses analysis for [samples] (e.g. while a metronome click sounds).
  void ignoreFor(int samples) {
    _ignoreUntil = max(_ignoreUntil, _clock + samples);
  }

  /// Clears audio history (new listening session). Keeps target settings.
  void reset() {
    _ring.fillRange(0, _ring.length, 0);
    _ringPos = 0;
    _clock = 0;
    _nextAnalysis = 0;
    _targetSetAt = 0;
    _ignoreUntil = 0;
    _strumStart = null;
    _lastOnset = null;
    _residual = null;
    _pendingOnsets.clear();
    _pendingCaptures.clear();
    _captureDone = true;
    _captureFrame = null;
    _onsets.reset();
    _resetRun();
  }

  void _resetRun() {
    _perfectRun = 0;
    _hitConsumed = false;
    _runChordId = null;
  }

  /// Feeds mono samples in [-1, 1]; returns the analysis frames produced.
  List<EngineFrame> addSamples(Float32List samples) {
    final out = <EngineFrame>[];
    var offset = 0;
    while (offset < samples.length) {
      final untilAnalysis = max(1, _nextAnalysis - _clock);
      final take = min(samples.length - offset, untilAnalysis);
      final part = Float32List.sublistView(samples, offset, offset + take);
      _ingest(part);
      offset += take;
      if (_clock >= _nextAnalysis) {
        _nextAnalysis = _clock + hopSamples;
        final frame = _analyze();
        if (frame != null) out.add(frame);
      }
    }
    return out;
  }

  /// PCM16 little-endian convenience wrapper (what the recorder delivers).
  List<EngineFrame> addPcm16(List<int> bytes) {
    final n = bytes.length ~/ 2;
    final samples = Float32List(n);
    for (var i = 0; i < n; i++) {
      final u = bytes[2 * i] | (bytes[2 * i + 1] << 8);
      samples[i] = (u >= 0x8000 ? u - 0x10000 : u) / 32768.0;
    }
    return addSamples(samples);
  }

  void _ingest(Float32List part) {
    final onsets = _onsets.process(part, _clock);
    _pendingOnsets.addAll(onsets);
    for (final s in part) {
      _ring[_ringPos] = s;
      _ringPos = (_ringPos + 1) % fftSize;
    }
    _clock += part.length;

    final cluster = strumClusterMs * sampleRate ~/ 1000;
    for (final onset in onsets) {
      final last = _lastOnset;
      if (last == null || onset - last > cluster) {
        // A new strum: restart the post-strum analysis window and remember
        // what was already ringing.
        _flushCapture();
        _strumStart = onset;
        _residual = _spectrumBefore(onset);
        _captureDone = false;
        _captureFrame = null;
        _captureOnset = onset;
        _captureResidual = _residual;
        _perfectRun = 0;
        _hitConsumed = false;
        _runChordId = null;
      }
      _lastOnset = onset;
    }
  }

  /// Emits the pending capture of the current strum, if it has a frame.
  void _flushCapture() {
    final frame = _captureFrame;
    final onset = _captureOnset;
    if (_captureDone || frame == null || onset == null) return;
    _captureDone = true;
    _pendingCaptures.add(
      StrumCapture(onsetSample: onset, frame: frame, residual: _captureResidual),
    );
  }

  static const int _residualSamples = 4096;

  List<double>? _spectrumBefore(int sample) {
    final back = _clock - sample; // samples recorded after the strum
    final length = _residualSamples;
    if (back < 0 || back + length > min(_clock, fftSize)) return null;
    final all = _orderedRing(back + length);
    final before = Float32List.sublistView(all, 0, length);
    return _fft.computeMagnitudesOfTail(before, length);
  }

  Float32List _orderedRing(int length) {
    final out = Float32List(length);
    final start = (_ringPos - length) % fftSize;
    for (var i = 0; i < length; i++) {
      out[i] = _ring[(start + i + fftSize) % fftSize];
    }
    return out;
  }

  EngineFrame? _analyze() {
    if (_clock < _ignoreUntil) return null;

    final available = min(_clock, fftSize);
    var segment = available;
    final strum = _strumStart;
    if (strum != null) {
      final sinceStrum = _clock - (strum + _attackSkipSamples);
      if (sinceStrum < segment) segment = sinceStrum;
    }
    if (segment < minSegmentSamples) {
      // Right after a strum: wait for enough new audio rather than mixing in
      // the previous chord.
      if (strum != null && _clock - strum < fftSize) return null;
      if (available < minSegmentSamples) return null;
      segment = available;
    }

    final samples = _orderedRing(segment);
    var sumSq = 0.0;
    for (final s in samples) {
      sumSq += s * s;
    }
    final frame = SpectrumFrame(
      magnitudes: segment >= fftSize
          ? _fft.computeMagnitudes(samples)
          : _fft.computeMagnitudesOfTail(samples, segment),
      fftSize: fftSize,
      sampleRate: sampleRate.toDouble(),
      inputLevel: sqrt(sumSq / segment),
    );

    if (strum != null && !_captureDone && segment < fftSize) {
      _captureFrame = frame;
      if (segment >= captureSamples) _flushCapture();
    }

    final freePlay = _freePlay;
    final feedback = freePlay != null
        ? _matcher.identifyBestChordFrame(
            chords: freePlay,
            frame: frame,
            referenceA4Hz: _a4,
            residual: _residual,
          )
        : _matcher.evaluateFrame(
            chord: _target!,
            frame: frame,
            referenceA4Hz: _a4,
            residual: _residual,
          );

    final lookback = strumLookbackMs * sampleRate ~/ 1000;
    final maxAge = maxStrumAgeMs * sampleRate ~/ 1000;
    final eligible = strum != null &&
        strum >= _targetSetAt - lookback &&
        _clock - strum <= maxAge;

    ChordHit? hit;
    if (eligible && feedback.matchStatus == ChordMatchStatus.perfect) {
      if (_runChordId != feedback.chordId) {
        _runChordId = feedback.chordId;
        _perfectRun = 0;
      }
      _perfectRun++;
      if (_perfectRun >= requiredPerfectFrames && !_hitConsumed) {
        _hitConsumed = true;
        hit = ChordHit(
          chordId: feedback.chordId,
          strumSample: strum,
          confirmSample: _clock,
          sampleRate: sampleRate,
        );
      }
    } else {
      _perfectRun = 0;
      _runChordId = null;
    }

    return EngineFrame(
      feedback: feedback,
      endSample: _clock,
      afterStrum: eligible,
      hit: hit,
    );
  }
}
