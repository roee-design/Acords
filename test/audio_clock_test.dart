import 'dart:math';

import 'package:chord_trainer/audio/audio_clock.dart';
import 'package:flutter_test/flutter_test.dart';

/// Simulates a recorder delivering [chunks] chunks of [chunk] samples: the
/// audio of chunk i ends at true time `trueZeroUs + samples/rate`, and
/// reaches the app [delayUs(i)] later.
AudioClockMapper deliver(
  int chunks, {
  required int Function(int i) delayUs,
  int chunk = 1764,
  int trueZeroUs = 5000000,
  double clockRatio = 1, // audio clock speed vs the system clock
}) {
  final m = AudioClockMapper(sampleRate: 44100);
  for (var i = 1; i <= chunks; i++) {
    final samples = i * chunk;
    final endUs = trueZeroUs + (samples / 44100 * 1e6 / clockRatio).round();
    m.onChunk(endUs + delayUs(i), samples);
  }
  return m;
}

void main() {
  const trueZero = 5000000;
  const minDelay = 8000; // the constant part of the input latency

  test('steady delivery: sample 0 maps to its recording time + the constant delay', () {
    final m = deliver(200, delayUs: (_) => minDelay);
    expect(m.sampleZeroUs, trueZero + minDelay);
    expect(m.usOfSample(44100), trueZero + minDelay + 1000000);
  });

  test('jittery and bursty delivery does not move the timestamps', () {
    final rng = Random(3);
    // Chunks arrive 0–60 ms late, sometimes in bursts of three (a stalled UI
    // thread); only a few arrive with the minimum delay.
    final m = deliver(400, delayUs: (i) {
      if (i % 50 == 0) return minDelay;
      final burst = (i ~/ 3) % 7 == 0 ? (2 - i % 3) * 40000 : 0;
      return minDelay + rng.nextInt(60000) + burst;
    });
    // Error ≤ the creep between two minimum-delay chunks (50 × 0.1 ms).
    expect(m.sampleZeroUs! - (trueZero + minDelay), inInclusiveRange(0, 5000));
  });

  test('a late first chunk does not leave a stale offset', () {
    final m = deliver(100, delayUs: (i) => i == 1 ? 300000 : minDelay);
    expect(m.sampleZeroUs, trueZero + minDelay);
  });

  test('drift between the audio and system clocks is followed', () {
    // Audio clock 100 ppm slow: after 60 s the true offset has grown 6 ms.
    final m = deliver(1500, delayUs: (_) => minDelay, clockRatio: 1 - 1e-4);
    final samples = 1500 * 1764;
    final trueEnd = trueZero + (samples / 44100 * 1e6 / (1 - 1e-4)).round();
    expect(m.usOfSample(samples) - (trueEnd + minDelay), inInclusiveRange(-1000, 1000));
  });

  test('monotonic clock never goes backwards', () {
    var last = MonotonicClock.nowUs;
    for (var i = 0; i < 10000; i++) {
      final now = MonotonicClock.nowUs;
      expect(now, greaterThanOrEqualTo(last));
      last = now;
    }
  });
}
