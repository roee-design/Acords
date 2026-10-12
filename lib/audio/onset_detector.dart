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
  })  : _fft = FFT(frameSize),
        _window = Float64List.fromList(
          List<double>.generate(
            frameSize,
            (i) => 0.5 * (1 - cos(2 * pi * i / (frameSize - 1))),
          ),
        ),
        _frame = Float64List(frameSize),
        _ring = Float64List(frameSize);

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
    final prev = _prevLogMag;
    if (prev != null) {
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
          _pendingRise >= energyRiseRatio &&
          (_pendingHfExcess >= attackFluxThreshold ||
              _pendingRise >= attackRiseRatio)) {
        final last = _lastOnsetSample;
        final refractory = (refractoryMs * sampleRate / 1000).round();
        if (last == null || _pendingSample - last >= refractory) {
          _lastOnsetSample = _pendingSample;
          onset = _pendingSample;
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
    _hfFluxHistory.add(hfFlux);
    if (_hfFluxHistory.length > 24) _hfFluxHistory.removeAt(0);

    _fluxHistory.add(flux);
    if (_fluxHistory.length > 24) _fluxHistory.removeAt(0);
    _rmsHistory.add(rms);
    if (_rmsHistory.length > 8) _rmsHistory.removeAt(0);
    return onset;
  }
}
