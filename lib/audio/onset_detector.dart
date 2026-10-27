import 'dart:math';
import 'dart:typed_data';

import 'package:fftea/fftea.dart';

/// Detects strum / pluck attacks in a mono sample stream, on the sample clock.
///
/// Every [hopSize] samples a short Hann-windowed FFT is taken and the
/// *spectral flux* — how much new energy appeared across frequencies since the
/// previous hop, on a log scale — is compared with its recent median. A pick
/// or nail attack adds broadband energy and re-excites every partial at once,
/// so it produces a sharp flux peak even when the previous chord is still
/// ringing at the same loudness (where a plain RMS ratio fails). Moving a
/// finger on an already-ringing string adds a few partials without a level
/// rise, so the flux peak must also coincide with a rise in short-term energy.
class OnsetDetector {
  OnsetDetector({
    this.sampleRate = 44100,
    this.frameSize = 1024,
    this.hopSize = 512,
    this.minLevel = 0.006,
    this.fluxThreshold = 0.2,
    this.energyRiseRatio = 1.0,
    this.refractoryMs = 140,
    this.attackFluxThreshold = 0.2,
    this.attackRiseRatio = 1.4,
    this.noiseGateRatio = 3,
    this.minRiseFraction = 0,
  })  : _fft = FFT(frameSize),
        _window = Float64List.fromList(
          List<double>.generate(
            frameSize,
            (i) => 0.5 * (1 - cos(2 * pi * i / (frameSize - 1))),
          ),
        ),
        _frame = Float64List(frameSize),
        _ring = Float64List(frameSize);

  /// Settings for the rhythm game, where strums are expected on the beat:
  /// accept soft finger strums (nylon strings, no pick noise) and fast
  /// patterns. A few extra detections only cost an "extra stroke" there,
  /// while a missed real strum breaks the combo.
  factory OnsetDetector.forRhythmGame({int sampleRate = 44100}) =>
      OnsetDetector(
        sampleRate: sampleRate,
        minLevel: 0.005,
        fluxThreshold: 0.09,
        refractoryMs: 130,
        attackFluxThreshold: 0.04,
        attackRiseRatio: 1.1,
        noiseGateRatio: 3,
        minRiseFraction: 0.2,
      );

  final int sampleRate;
  final int frameSize;
  final int hopSize;

  /// Minimum hop RMS for an onset (rejects hiss / handling noise).
  final double minLevel;

  /// Flux above the recent median (mean log-magnitude rise per bin).
  final double fluxThreshold;

  /// Hop RMS must exceed the quietest of the previous few hops by this ratio.
  final double energyRiseRatio;

  final int refractoryMs;

  /// A real strum carries a short broadband "pick/nail" transient. Flux in
  /// 2–8 kHz above its recent median by this much marks one. Without it, an
  /// onset is only accepted on a clear level jump ([attackRiseRatio]); this
  /// keeps a silent fret change on ringing strings from counting as a strum.
  final double attackFluxThreshold;
  final double attackRiseRatio;

  /// An onset's hop RMS must be at least this many times the room's
  /// background level (a slow follower of the quiet hops). 0 = off.
  /// Rejects hum, fans, talking in the next room and handling noise without
  /// raising the absolute threshold for soft strums in a quiet room.
  final double noiseGateRatio;

  /// Fraction of the audible spectrum (80 Hz–5 kHz bins above the frame's
  /// own floor) that must rise together (by > 35 %) for an onset. A struck
  /// string starts all its partials at once; a chord merely ringing on only
  /// "breathes" in a few partials at a time (beating), which can still push
  /// the average flux over its threshold. 0 = off.
  final double minRiseFraction;
  double _noiseFloor = 0;

  /// Optional diagnostics sink (tests / benches).
  void Function(String message)? debugLog;

    /// Current background level estimate (RMS).
  double get noiseFloor => _noiseFloor;

  final FFT _fft;
  final Float64List _window;
  final Float64List _frame;
  final Float64List _ring;
  var _ringPos = 0;
  var _samplesSeen = 0;
  var _sinceHop = 0;

  Float64List? _prevLogMag;
  final List<double> _fluxHistory = <double>[];
  final List<double> _hfFluxHistory = <double>[];
  final List<double> _rmsHistory = <double>[];

  // One-hop lookahead for peak picking.
  double? _pendingFlux;
  int _pendingSample = 0;
  double _pendingRms = 0;
  double _pendingRise = 0;
  double _pendingThreshold = 0;
  double _pendingHfExcess = 0;
  double _pendingRiseFraction = 0;
  double? _beforePendingFlux;

  int? _lastOnsetSample;

  int? get lastOnsetSample => _lastOnsetSample;

  void reset() {
    _ring.fillRange(0, _ring.length, 0);
    _ringPos = 0;
    _samplesSeen = 0;
    _sinceHop = 0;
    _prevLogMag = null;
    _fluxHistory.clear();
    _hfFluxHistory.clear();
    _rmsHistory.clear();
    _pendingFlux = null;
    _beforePendingFlux = null;
    _lastOnsetSample = null;
    _noiseFloor = 0;
  }

  /// Feeds samples; returns the absolute sample indices of new onsets.
  /// [startSample] is the clock value of `samples[0]`.
  List<int> process(Float32List samples, int startSample) {
    final onsets = <int>[];
    for (var i = 0; i < samples.length; i++) {
      _ring[_ringPos] = samples[i];
      _ringPos = (_ringPos + 1) % frameSize;
      _samplesSeen++;
      _sinceHop++;
      if (_sinceHop >= hopSize && _samplesSeen >= frameSize) {
        _sinceHop = 0;
        final onset = _analyzeHop(startSample + i + 1);
        if (onset != null) onsets.add(onset);
      }
    }
    return onsets;
  }

  int? _analyzeHop(int endSample) {
    var sumSq = 0.0;
    for (var i = 0; i < frameSize; i++) {
      final s = _ring[(_ringPos + i) % frameSize];
      _frame[i] = s * _window[i];
    }
    // Energy of the newest hop only (sharper than the whole frame).
    for (var i = frameSize - hopSize; i < frameSize; i++) {
      final s = _ring[(_ringPos + i) % frameSize];
      sumSq += s * s;
    }
    final rms = sqrt(sumSq / hopSize);
    // Background follower: drops quickly to quiet hops and rises only from
    // hops that are themselves near the background — music never lifts it,
    // so a long song cannot gate its own strums out.
    if (_noiseFloor == 0) {
      _noiseFloor = rms;
    } else if (rms < _noiseFloor) {
      _noiseFloor = _noiseFloor * 0.8 + rms * 0.2;
    } else if (rms < _noiseFloor * 2) {
      _noiseFloor = _noiseFloor * 0.99 + rms * 0.01;
    }

    final mags = _fft.realFft(_frame).discardConjugates().magnitudes();
    final binHz = sampleRate / frameSize;
    final lo = max(1, (60 / binHz).floor());
    final hi = min(mags.length - 1, (8000 / binHz).ceil());
    final logMag = Float64List(mags.length);
    for (var b = lo; b <= hi; b++) {
      logMag[b] = log(1 + 1000 * mags[b]);
    }
    final hfLo = (2000 / binHz).floor();
    var flux = 0.0;
    var hfFlux = 0.0;
    var riseFraction = 0.0;
    final prev = _prevLogMag;
    if (prev != null) {
      final rLo = max(lo, (80 / binHz).floor());
      final rHi = min(hi, (5000 / binHz).ceil());
      var peak = 0.0;
      for (var b = rLo; b <= rHi; b++) {
        peak = max(peak, logMag[b]);
      }
      final audible = peak - 4.6; // bins within ~40 dB of the strongest
      var counted = 0;
      var rising = 0;
      for (var b = rLo; b <= rHi; b++) {
        if (max(logMag[b], prev[b]) < audible) continue;
        counted++;
        if (logMag[b] - prev[b] > 0.3) rising++;
      }
      riseFraction = counted == 0 ? 0 : rising / counted;
      for (var b = lo; b <= hi; b++) {
        final d = logMag[b] - prev[b];
        if (d > 0) {
          flux += d;
          if (b >= hfLo) hfFlux += d;
        }
      }
      flux /= (hi - lo + 1);
      hfFlux /= (hi - hfLo + 1);
    }
    final sortedHf = [..._hfFluxHistory]..sort();
    final hfMedian = sortedHf.isEmpty ? 0.0 : sortedHf[sortedHf.length ~/ 2];
    _prevLogMag = logMag;

    // Reference energy: quietest of the 4 hops before this one.
    var refRms = double.infinity;
    for (final r in _rmsHistory.length > 4
        ? _rmsHistory.sublist(_rmsHistory.length - 4)
        : _rmsHistory) {
      refRms = min(refRms, r);
    }
    final rise = refRms.isFinite && refRms > 0 ? rms / refRms : 10.0;

    final sortedFlux = [..._fluxHistory]..sort();
    final median =
        sortedFlux.isEmpty ? 0.0 : sortedFlux[sortedFlux.length ~/ 2];
    final threshold = median + fluxThreshold;

    // Decide on the *pending* hop now that we know its successor (peak pick).
    int? onset;
    final pending = _pendingFlux;
    if (pending != null) {
      final isPeak = pending >= (_beforePendingFlux ?? 0) && pending >= flux;
      if (isPeak &&
          pending >= _pendingThreshold &&
          _pendingRms >= minLevel &&
          (noiseGateRatio <= 0 || _pendingRms >= _noiseFloor * noiseGateRatio) &&
          _pendingRise >= energyRiseRatio &&
          (minRiseFraction <= 0 || _pendingRiseFraction >= minRiseFraction) &&
          (_pendingHfExcess >= attackFluxThreshold ||
              _pendingRise >= attackRiseRatio)) {
        final last = _lastOnsetSample;
        final refractory = (refractoryMs * sampleRate / 1000).round();
        if (last == null || _pendingSample - last >= refractory) {
          _lastOnsetSample = _pendingSample;
          onset = _pendingSample;
          debugLog?.call(
            'onset t=${(_pendingSample / sampleRate).toStringAsFixed(2)} '
            'flux=${pending.toStringAsFixed(3)} thr=${_pendingThreshold.toStringAsFixed(3)} '
            'rms=${_pendingRms.toStringAsFixed(4)} rise=${_pendingRise.toStringAsFixed(2)} '
            'hf=${_pendingHfExcess.toStringAsFixed(3)} cover=${_pendingRiseFraction.toStringAsFixed(2)} '
            'floor=${_noiseFloor.toStringAsFixed(4)}',
          );
        }
      }
    }
    _beforePendingFlux = pending;
    _pendingFlux = flux;
    // The attack starts somewhere in the newest hop; report its beginning.
    _pendingSample = endSample - hopSize;
    _pendingRms = rms;
    _pendingRise = rise;
    _pendingThreshold = threshold;
    _pendingHfExcess = hfFlux - hfMedian;
    _pendingRiseFraction = riseFraction;
    _hfFluxHistory.add(hfFlux);
    if (_hfFluxHistory.length > 24) _hfFluxHistory.removeAt(0);

    _fluxHistory.add(flux);
    if (_fluxHistory.length > 24) _fluxHistory.removeAt(0);
    _rmsHistory.add(rms);
    if (_rmsHistory.length > 8) _rmsHistory.removeAt(0);
    return onset;
  }
}
