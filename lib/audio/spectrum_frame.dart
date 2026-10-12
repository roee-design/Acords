import 'dart:math';

/// A spectral peak (local maximum) with sub-bin refined frequency.
class SpectralPeak {
  const SpectralPeak({
    required this.bin,
    required this.hz,
    required this.magnitude,
  });

  final int bin;
  final double hz;
  final double magnitude;
}

/// One analysed audio frame: magnitudes plus the level references every
/// matcher decision is made relative to.
///
/// All thresholds downstream are expressed relative to [bandPeak] (the
/// strongest component in the guitar band) and [noiseFloor], so detection does
/// not depend on how loud the guitar is or how sensitive the phone mic is.
class SpectrumFrame {
  SpectrumFrame({
    required this.magnitudes,
    required this.fftSize,
    required this.sampleRate,
    required this.inputLevel,
  })  : binHz = sampleRate / fftSize,
        noiseFloor = _estimateNoiseFloor(magnitudes, sampleRate / fftSize),
        bandPeak = _bandPeak(magnitudes, sampleRate / fftSize);

  final List<double> magnitudes;
  final int fftSize;
  final double sampleRate;
  final double binHz;

  /// RMS of the analysed samples (0–1).
  final double inputLevel;

  /// Typical magnitude of bins that hold no guitar partials.
  final double noiseFloor;

  /// Strongest magnitude between [bandLowHz] and [bandHighHz].
  final double bandPeak;

  static const double bandLowHz = 70;
  static const double bandHighHz = 1400;

  List<SpectralPeak>? _peaks;

  int hzToBinIndex(double hz) =>
      (hz / binHz).round().clamp(0, magnitudes.length - 1);

  /// Strongest refined peak within [hz] ± [toleranceHz]; null if none.
  SpectralPeak? peakNear(double hz, double toleranceHz) {
    final start = max(1, ((hz - toleranceHz) / binHz).floor());
    final end = min(magnitudes.length - 2, ((hz + toleranceHz) / binHz).ceil());
    var best = -1;
    var bestMag = 0.0;
    for (var b = start; b <= end; b++) {
      final m = magnitudes[b];
      if (m > bestMag) {
        bestMag = m;
        best = b;
      }
    }
    if (best < 0 || bestMag <= 0) return null;
    return SpectralPeak(
      bin: best,
      hz: (best + parabolicOffset(best)) * binHz,
      magnitude: bestMag,
    );
  }

  /// Prominent local maxima inside the guitar band (strongest first).
  List<SpectralPeak> get peaks => _peaks ??= _findPeaks();

  List<SpectralPeak> _findPeaks() {
    final lo = max(2, (bandLowHz / binHz).floor());
    final hi = min(magnitudes.length - 3, (bandHighHz / binHz).ceil());
    final out = <SpectralPeak>[];
    final minMag = max(noiseFloor * 4, bandPeak * 0.02);
    for (var b = lo; b <= hi; b++) {
      final m = magnitudes[b];
      if (m < minMag) continue;
      if (m < magnitudes[b - 1] ||
          m < magnitudes[b + 1] ||
          m < magnitudes[b - 2] ||
          m < magnitudes[b + 2]) {
        continue;
      }
      out.add(
        SpectralPeak(
          bin: b,
          hz: (b + parabolicOffset(b)) * binHz,
          magnitude: m,
        ),
      );
    }
    out.sort((a, b) => b.magnitude.compareTo(a.magnitude));
    return out;
  }

  /// Sub-bin offset in [-0.5, 0.5] from a parabola through log-magnitudes.
  double parabolicOffset(int bin) {
    if (bin <= 0 || bin >= magnitudes.length - 1) return 0;
    const eps = 1e-12;
    final l = log(magnitudes[bin - 1] + eps);
    final c = log(magnitudes[bin] + eps);
    final r = log(magnitudes[bin + 1] + eps);
    final denom = l - 2 * c + r;
    if (denom.abs() < 1e-9 || denom > 0) return 0;
    return (0.5 * (l - r) / denom).clamp(-0.5, 0.5);
  }

  static double _bandPeak(List<double> mags, double binHz) {
    final lo = max(1, (bandLowHz / binHz).floor());
    final hi = min(mags.length - 1, (bandHighHz / binHz).ceil());
    var peak = 0.0;
    for (var b = lo; b <= hi; b++) {
      if (mags[b] > peak) peak = mags[b];
    }
    return peak;
  }

  /// Lower quartile of 1.6–5 kHz: above guitar fundamentals, mostly hiss.
  static double _estimateNoiseFloor(List<double> mags, double binHz) {
    final lo = min(mags.length - 1, (1600 / binHz).floor());
    final hi = min(mags.length - 1, (5000 / binHz).ceil());
    if (hi <= lo) return 0;
    final tail = mags.sublist(lo, hi)..sort();
    return tail[(tail.length * 0.25).floor()];
  }
}
