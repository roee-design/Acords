import 'dart:math';
import 'dart:typed_data';

import 'package:fftea/fftea.dart';

import 'frequency_utils.dart';

/// Hann-windowed real FFT and harmonic-weighted frequency scoring.
class FftProcessor {
  FftProcessor({
    required this.fftSize,
    required this.sampleRate,
  })  : _fft = FFT(fftSize),
        _window = hannWindow(fftSize),
        _input = Float64List(fftSize);

  final int fftSize;
  final double sampleRate;
  final FFT _fft;
  final List<double> _window;
  final Float64List _input;

  /// Clears reusable FFT memory between chord targets.
  void reset() {
    _input.fillRange(0, _input.length, 0);
  }

  /// One-sided magnitude spectrum (length ≈ fftSize / 2 + 1).
  /// Applies Hann window before FFT to reduce spectral leakage on plucks.
  List<double> computeMagnitudes(Float32List samples) {
    final n = min(samples.length, fftSize);
    _input.fillRange(0, _input.length, 0);
    for (var i = 0; i < n; i++) {
      _input[i] = samples[i] * _window[i];
    }

    final spectrum = _fft.realFft(_input);
    return spectrum.discardConjugates().magnitudes();
  }

  /// Noise floor from high-frequency bins (room hiss, not guitar fundamentals).
  double estimateNoiseFloor(List<double> magnitudes) {
    const guitarCeilingHz = 1200.0;
    final startBin = hzToBin(guitarCeilingHz, fftSize, sampleRate);
    if (startBin >= magnitudes.length - 1) {
      return 0;
    }

    final tail = magnitudes.sublist(startBin);
    if (tail.isEmpty) {
      return 0;
    }

    final sorted = List<double>.from(tail)..sort();
    final index = (sorted.length * 0.25).floor().clamp(0, sorted.length - 1);
    return sorted[index];
  }
}

/// Scores energy at f0 and overtone bins for a single target note.
class TargetFrequencyProfile {
  TargetFrequencyProfile({
    required this.fundamentalHz,
    required this.harmonicWeights,
    this.centsTolerance = 35,
  });

  final double fundamentalHz;
  final List<double> harmonicWeights;

  /// How wide each harmonic peak search is, in cents.
  final double centsTolerance;

  /// Peak magnitude in a window around the fundamental (±[searchCents]).
  double peakEnergy(
    List<double> magnitudes,
    int fftSize,
    double sampleRate, {
    double? searchCents,
  }) {
    final cents = searchCents ?? _defaultSearchCents;
    var peak = 0.0;
    for (final harmonic in _pitchSearchHarmonics()) {
      final harmonicHz = fundamentalHz * harmonic;
      if (harmonicHz >= sampleRate / 2) {
        break;
      }
      final centerBin = hzToBin(harmonicHz, fftSize, sampleRate);
      final halfWidth = _halfWidthBinsForCents(
        harmonicHz,
        cents,
        fftSize,
        sampleRate,
      );
      final start = max(0, centerBin - halfWidth);
      final end = min(magnitudes.length - 1, centerBin + halfWidth);
      for (var bin = start; bin <= end; bin++) {
        peak = max(peak, magnitudes[bin]);
      }
    }
    return peak;
  }

  /// Signed cents offset of the strongest peak near the fundamental.
  /// Returns null when no energy is present in the search window.
  ///
  /// The peak position is refined with quadratic (parabolic) interpolation on
  /// the log-magnitude of the strongest bin and its two neighbours. Without it
  /// the estimate is quantised to the bin grid (5.4 Hz at 44.1 kHz / 8192):
  /// E2 (82.4 Hz) can only be reported as −35 ¢ or +76 ¢, A2 (110 Hz) as
  /// −37 ¢ or +47 ¢, so those strings could never pass a ±25 ¢ gate.
  double? estimatePitchCentsOffset(
    List<double> magnitudes,
    int fftSize,
    double sampleRate, {
    double? searchCents,
  }) {
    final cents = searchCents ?? _defaultSearchCents;
    var bestEnergy = 0.0;
    var bestBin = -1;
    var bestHarmonic = 1;
    for (final harmonic in _pitchSearchHarmonics()) {
      final harmonicHz = fundamentalHz * harmonic;
      if (harmonicHz >= sampleRate / 2) {
        break;
      }
      final centerBin = hzToBin(harmonicHz, fftSize, sampleRate);
      final halfWidth = _halfWidthBinsForCents(
        harmonicHz,
        cents,
        fftSize,
        sampleRate,
      );
      final start = max(0, centerBin - halfWidth);
      final end = min(magnitudes.length - 1, centerBin + halfWidth);
      for (var bin = start; bin <= end; bin++) {
        final energy = magnitudes[bin];
        if (energy > bestEnergy) {
          bestEnergy = energy;
          bestBin = bin;
          bestHarmonic = harmonic;
        }
      }
    }

    if (bestEnergy <= 0 || bestBin < 0 || fundamentalHz <= 0) {
      return null;
    }

    final refinedBin = bestBin + _parabolicOffset(magnitudes, bestBin);
    final peakHz = (refinedBin * sampleRate / fftSize) / bestHarmonic;
    if (peakHz <= 0) {
      return null;
    }

    return 1200 * log(peakHz / fundamentalHz) / ln2;
  }

  /// Sub-bin offset in [-0.5, 0.5] of the true peak around [bin], using a
  /// parabola fitted through log-magnitudes of the bin and its neighbours.
  double _parabolicOffset(List<double> magnitudes, int bin) {
    if (bin <= 0 || bin >= magnitudes.length - 1) {
      return 0;
    }
    const eps = 1e-12;
    final left = log(magnitudes[bin - 1] + eps);
    final mid = log(magnitudes[bin] + eps);
    final right = log(magnitudes[bin + 1] + eps);
    final denom = left - 2 * mid + right;
    if (denom.abs() < 1e-9 || denom > 0) {
      // Flat or not a local maximum → keep the bin centre.
      return 0;
    }
    final offset = 0.5 * (left - right) / denom;
    return offset.clamp(-0.5, 0.5);
  }

  double score(List<double> magnitudes, int fftSize, double sampleRate) {
    var total = 0.0;

    for (var h = 0; h < harmonicWeights.length; h++) {
      final harmonicHz = fundamentalHz * (h + 1);
      if (harmonicHz >= sampleRate / 2) {
        break;
      }

      final bin = hzToBin(harmonicHz, fftSize, sampleRate);
      final halfWidth = _halfWidthBinsForCents(
        harmonicHz,
        centsTolerance,
        fftSize,
        sampleRate,
      );

      total += harmonicWeights[h] *
          binNeighborhoodEnergy(
            magnitudes,
            bin,
            halfWidthBins: halfWidth,
          );
    }

    return total;
  }

  int _halfWidthBinsForCents(
    double hz,
    double cents,
    int fftSize,
    double sampleRate,
  ) {
    final ratio = pow(2, cents / 1200).toDouble();
    final deltaHz = hz * (ratio - 1);
    final binWidth = sampleRate / fftSize;
    return max(1, (deltaHz / binWidth).ceil());
  }

  Iterable<int> _pitchSearchHarmonics() sync* {
    yield 1;
    if (fundamentalHz < 160) {
      yield 2;
      yield 3;
    }
  }

  /// Wider window on bass notes so ±1 FFT bin still counts as "near".
  double get _defaultSearchCents {
    if (fundamentalHz < 100) return 150;
    if (fundamentalHz < 140) return 110;
    return 80;
  }
}
