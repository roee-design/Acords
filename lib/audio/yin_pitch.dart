import 'dart:math';
import 'dart:typed_data';

/// Result of one YIN pitch estimate.
class YinResult {
  const YinResult({required this.hz, required this.aperiodicity});

  final double hz;

  /// Cumulative-mean-normalised difference at the chosen period (0 = perfectly
  /// periodic, ~1 = noise). Lower is more trustworthy.
  final double aperiodicity;
}

/// YIN fundamental-frequency estimator (de Cheveigné & Kawahara, 2002).
///
/// Works on the waveform's period rather than on spectral peaks, so it finds
/// the true fundamental of a low string even when a phone microphone has
/// attenuated it far below its 2nd/3rd harmonics — the case where FFT
/// peak-picking jumps an octave or needs special-case "rescue" heuristics.
class YinPitchEstimator {
  YinPitchEstimator({
    this.sampleRate = 44100,
    this.windowSize = 2048,
    this.threshold = 0.15,
  });

  final int sampleRate;

  /// Integration window W; the frame must hold W + maxPeriod samples.
  final int windowSize;

  /// Absolute threshold on the normalised difference (dips below it are
  /// accepted as the period; the first such dip avoids octave-down errors).
  final double threshold;

  /// Estimates pitch from the newest samples of [frame] within
  /// [minHz]–[maxHz]. Returns null for silence / noise.
  YinResult? estimate(
    Float32List frame, {
    double minHz = 70,
    double maxHz = 700,
  }) {
    final maxTau = min((sampleRate / minHz).ceil(), frame.length - windowSize - 1);
    final minTau = max(2, (sampleRate / maxHz).floor());
    if (maxTau <= minTau + 2) return null;
    final start = frame.length - windowSize - maxTau - 1;
    if (start < 0) return null;

    // Difference function d(τ) and its cumulative mean normalisation d'(τ).
    final d = Float64List(maxTau + 2);
    for (var tau = 1; tau <= maxTau + 1; tau++) {
      var sum = 0.0;
      for (var j = 0; j < windowSize; j++) {
        final diff = frame[start + j] - frame[start + j + tau];
        sum += diff * diff;
      }
      d[tau] = sum;
    }
    final dn = Float64List(maxTau + 2)..[0] = 1;
    var running = 0.0;
    for (var tau = 1; tau <= maxTau + 1; tau++) {
      running += d[tau];
      dn[tau] = running <= 0 ? 1 : d[tau] * tau / running;
    }

    var tau = -1;
    for (var t = minTau; t <= maxTau; t++) {
      if (dn[t] < threshold) {
        while (t + 1 <= maxTau && dn[t + 1] < dn[t]) {
          t++;
        }
        tau = t;
        break;
      }
    }
    if (tau < 0) {
      // No dip under the threshold: take the global minimum if it is still
      // reasonably periodic (weak / decaying notes).
      var best = minTau;
      for (var t = minTau + 1; t <= maxTau; t++) {
        if (dn[t] < dn[best]) best = t;
      }
      if (dn[best] > 0.35) return null;
      tau = best;
    }

    // Parabolic interpolation of the dip for sub-sample period.
    var refined = tau.toDouble();
    if (tau > 1 && tau < maxTau + 1) {
      final a = dn[tau - 1];
      final b = dn[tau];
      final c = dn[tau + 1];
      final denom = a - 2 * b + c;
      if (denom.abs() > 1e-12) {
        refined = tau + (0.5 * (a - c) / denom).clamp(-1.0, 1.0);
      }
    }
    return YinResult(hz: sampleRate / refined, aperiodicity: dn[tau]);
  }

  /// Number of samples [estimate] needs for a given [minHz].
  int requiredSamples(double minHz) =>
      windowSize + (sampleRate / minHz).ceil() + 2;
}
