import 'dart:math';

/// The one monotonic clock that audio timestamps and game clocks share.
///
/// `DateTime.now()` is wall time: the system may adjust it at any moment
/// (network time sync), which would shift every strum against the chart.
/// A [Stopwatch] never jumps.
class MonotonicClock {
  MonotonicClock._();

  static final Stopwatch _clock = Stopwatch()..start();

  /// Microseconds since the app started; never goes backwards.
  static int get nowUs => _clock.elapsedMicroseconds;
}

/// Maps the audio sample clock to [MonotonicClock] time.
///
/// Audio arrives in chunks, sometimes late, never early — so the smallest
/// "arrival time − audio time" seen is the best estimate of when sample 0
/// was recorded (minus a constant input latency, which the mic calibration
/// measures). Using it, instead of "now" when a chunk is processed, keeps the
/// delivery and processing jitter out of every strum timestamp. The estimate
/// may creep up by [creepUs] per chunk, so a slow drift between the audio and
/// system clocks cannot freeze a stale value.
class AudioClockMapper {
  AudioClockMapper({required this.sampleRate, this.creepUs = 100});

  final int sampleRate;
  final int creepUs;
  int? _zeroUs;

  /// Monotonic time (µs) of sample 0, once a chunk has arrived.
  int? get sampleZeroUs => _zeroUs;

  void reset() => _zeroUs = null;

  /// A chunk ending at sample [samplesSoFar] arrived at monotonic [arrivalUs].
  void onChunk(int arrivalUs, int samplesSoFar) {
    final candidate = arrivalUs - samplesSoFar * 1000000 ~/ sampleRate;
    final current = _zeroUs;
    _zeroUs = current == null ? candidate : min(current + creepUs, candidate);
  }

  /// Monotonic time (µs) at which [sample] was recorded (+ input latency).
  int usOfSample(int sample) => _zeroUs! + sample * 1000000 ~/ sampleRate;
}
