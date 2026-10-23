import 'dart:math';

/// Result of a microphone latency calibration.
class LatencyEstimate {
  const LatencyEstimate({
    required this.latencyMs,
    required this.spreadMs,
    required this.samples,
  });

  /// How much later a strum is heard than it was played (ms).
  final int latencyMs;

  /// Robust spread of the measurements (1.48 × MAD, ms).
  final double spreadMs;
  final int samples;

  /// Enough consistent strums to trust the value.
  bool get isReliable => samples >= 6 && spreadMs <= 75;
}

/// Measures input latency from strums played along a slow visual pulse.
///
/// Pulses are at `k × beatMs`. Audio always arrives *late*, by 0–[maxLatencyMs],
/// and a player may be a little early, so each strum is matched to the one
/// pulse in `[t − maxLatencyMs, t + earlyToleranceMs]`. With a slow pulse
/// that window is shorter than a beat, so the match is unambiguous — unlike
/// matching against the nearest game note, which can lock onto the wrong one.
class LatencyCalibrator {
  LatencyCalibrator({
    required this.beatMs,
    this.firstCountedBeat = 2,
    this.maxLatencyMs = 600,
    this.earlyToleranceMs = 150,
  }) : assert(maxLatencyMs + earlyToleranceMs < beatMs);

  final double beatMs;

  /// Pulses before this one are a warm-up and not measured.
  final int firstCountedBeat;
  final double maxLatencyMs;
  final double earlyToleranceMs;

  final List<double> _offsets = [];
  final Set<int> _usedBeats = {};

  int get count => _offsets.length;

  /// Adds a strum heard at [heardMs] (same clock as the pulses). Returns the
  /// measured offset, or null when it matches no pulse.
  double? addStrum(double heardMs) {
    final beat = ((heardMs - maxLatencyMs) / beatMs).ceil();
    final beatTime = beat * beatMs;
    final offset = heardMs - beatTime;
    if (beat < firstCountedBeat) return null;
    if (offset < -earlyToleranceMs || offset > maxLatencyMs) return null;
    // One strum per pulse (a strum can be detected twice).
    if (!_usedBeats.add(beat)) return null;
    _offsets.add(offset);
    return offset;
  }

  LatencyEstimate? estimate() {
    if (_offsets.isEmpty) return null;
    final sorted = [..._offsets]..sort();
    final median = sorted[sorted.length ~/ 2];
    final deviations = [for (final o in sorted) (o - median).abs()]..sort();
    final mad = deviations[deviations.length ~/ 2];
    return LatencyEstimate(
      latencyMs: max(0, median.round()),
      spreadMs: 1.48 * mad,
      samples: sorted.length,
    );
  }
}

/// Small in-game corrections around a calibrated latency.
///
/// Only strokes within [reachMs] of a note count, the median of the last few
/// moves the correction halfway, and the total stays within ±[maxCorrectionMs]
/// of the calibrated value — so it can fine-tune but never run away.
class LatencyTrim {
  LatencyTrim({this.reachMs = 120, this.maxCorrectionMs = 100});

  final double reachMs;
  final double maxCorrectionMs;
  final List<double> _recent = [];
  double correctionMs = 0;

  /// [offsetMs]: stroke time (already corrected) minus nearest note time.
  void add(double offsetMs) {
    if (offsetMs.abs() > reachMs) return;
    _recent.add(offsetMs);
    if (_recent.length > 8) _recent.removeAt(0);
    if (_recent.length < 4) return;
    final sorted = [..._recent]..sort();
    final median = sorted[sorted.length ~/ 2];
    if (median.abs() < 20) return;
    final step = median * 0.5;
    final next = (correctionMs + step).clamp(-maxCorrectionMs, maxCorrectionMs);
    final applied = next - correctionMs;
    correctionMs = next;
    for (var i = 0; i < _recent.length; i++) {
      _recent[i] -= applied;
    }
  }
}
