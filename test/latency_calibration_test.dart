import 'dart:math';

import 'package:chord_trainer/game/latency_calibration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const beat = 60000 / 70; // 857 ms

  test('finds a large latency that nearest-note matching would get wrong', () {
    final rng = Random(1);
    for (final latency in [60.0, 180.0, 320.0, 480.0]) {
      final cal = LatencyCalibrator(beatMs: beat);
      for (var k = 0; k < 14; k++) {
        // Human timing ±30 ms around each pulse, plus the mic latency.
        final played = k * beat + (rng.nextDouble() - 0.5) * 60;
        cal.addStrum(played + latency);
      }
      final e = cal.estimate()!;
      expect(e.latencyMs, closeTo(latency, 20), reason: 'latency $latency');
      expect(e.isReliable, isTrue);
    }
  });

  test('warm-up pulses, double detections and stray noise are ignored', () {
    final cal = LatencyCalibrator(beatMs: beat);
    expect(cal.addStrum(0 * beat + 200), isNull); // warm-up
    expect(cal.addStrum(1 * beat + 200), isNull); // warm-up
    expect(cal.addStrum(2 * beat + 200), 200);
    // A second, weaker attack for the same pulse is kept as a candidate but
    // the estimate uses the earliest strong one.
    expect(cal.addStrum(2 * beat + 330, weight: 0.4), closeTo(330, 1e-6));
    expect(cal.addStrum(3 * beat + 700), isNull); // beyond max latency
    expect(cal.count, 1);
    expect(cal.estimate()!.latencyMs, 200);
  });

  test('a weak false attack before the strum does not win the pulse', () {
    final cal = LatencyCalibrator(beatMs: beat);
    for (var k = 2; k < 12; k++) {
      cal.addStrum(k * beat + 180 - 90, weight: 0.35); // ringing chord
      cal.addStrum(k * beat + 180, weight: 1.2); // the strum
      cal.addStrum(k * beat + 180 + 58, weight: 1.0); // its later strings
    }
    final e = cal.estimate()!;
    expect(e.latencyMs, 180);
    expect(e.isReliable, isTrue);
  });

  test('inconsistent strumming is not trusted', () {
    final rng = Random(7);
    final cal = LatencyCalibrator(beatMs: beat);
    for (var k = 2; k < 14; k++) {
      cal.addStrum(k * beat + 100 + rng.nextDouble() * 400);
    }
    expect(cal.estimate()!.isReliable, isFalse);
  });

  test('in-game trim converges but stays bounded', () {
    final trim = LatencyTrim();
    // Remaining error of +60 ms after calibration.
    for (var i = 0; i < 20; i++) {
      trim.add(60 - trim.correctionMs);
    }
    expect(trim.correctionMs, closeTo(60, 20));

    final runaway = LatencyTrim();
    for (var i = 0; i < 50; i++) {
      runaway.add(110); // always late, even after correcting
    }
    expect(runaway.correctionMs, lessThanOrEqualTo(100));
  });
}
