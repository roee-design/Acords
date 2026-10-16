import 'dart:math';
import 'dart:typed_data';

import 'package:chord_trainer/models/chord_definition.dart';

/// Recording conditions applied to a synthesized performance.
class MicConditions {
  const MicConditions({
    this.highPassHz = 120,
    this.noiseLevel = 0.002,
    this.gain = 1.0,
  });

  /// Phone microphones roll off the low end; E2/A2 fundamentals arrive weak.
  final double highPassHz;

  /// RMS of additive broadband room/self noise.
  final double noiseLevel;

  /// Overall level (distance to the phone).
  final double gain;

  @override
  String toString() =>
      'hpf=${highPassHz.toStringAsFixed(0)}Hz noise=$noiseLevel gain=$gain';
}

/// One string event: a pluck of [midi] starting at [startSec].
class StringEvent {
  StringEvent({
    required this.midi,
    required this.startSec,
    this.amplitude = 0.25,
    this.stopSec,
    this.detuneCents = 0,
    this.pluckPosition = 0.18,
    this.attackNoise = true,
    this.attackSec = 0.003,
    this.stringNumber,
  });

  final int midi;
  final double startSec;
  final double amplitude;

  /// When set, the string is damped (finger lifted / palm) from this time.
  final double? stopSec;
  final double detuneCents;
  final double pluckPosition;
  final bool attackNoise;

  /// Rise time; a legato (hammer-on / fret change) note rises slowly.
  final double attackSec;

  /// Guitar string this note is played on (6 = low E), when known.
  final int? stringNumber;

  StringEvent copyWith({double? stopSec}) => StringEvent(
        midi: midi,
        startSec: startSec,
        amplitude: amplitude,
        stopSec: stopSec ?? this.stopSec,
        detuneCents: detuneCents,
        pluckPosition: pluckPosition,
        attackNoise: attackNoise,
        attackSec: attackSec,
        stringNumber: stringNumber,
      );
}

/// Simple physically-inspired plucked-string synthesizer for offline tests.
///
/// It is not meant to sound good — it reproduces the properties that make
/// guitar detection hard: harmonic-rich spectra with a weak fundamental on a
/// phone mic, slight inharmonicity, faster decay of upper partials, string
/// spread inside a strum, ringing tails of the previous chord, pick noise and
/// room noise.
class GuitarSynth {
  GuitarSynth({this.sampleRate = 44100, int seed = 1}) : _rng = Random(seed);

  final int sampleRate;
  final Random _rng;

  static const _openMidi = {6: 40, 5: 45, 4: 50, 3: 55, 2: 59, 1: 64};

  double _gauss() {
    final u1 = max(1e-12, _rng.nextDouble());
    final u2 = _rng.nextDouble();
    return sqrt(-2 * log(u1)) * cos(2 * pi * u2);
  }

  /// String events for a down-strum of [chord] beginning at [startSec].
  List<StringEvent> strum(
    ChordDefinition chord, {
    required double startSec,
    double? stopSec,
    bool down = true,
    double tuningSpreadCents = 6,
    double level = 0.22,
    Set<int> skipStrings = const {},
    Set<int>? onlyStrings,
    bool legato = false,
    bool soft = false,
  }) {
    final notes = [...chord.notes]
      ..sort((a, b) => down ? b.string - a.string : a.string - b.string);
    final events = <StringEvent>[];
    var t = startSec;
    for (final note in notes) {
      if (skipStrings.contains(note.string)) continue;
      if (onlyStrings != null && !onlyStrings.contains(note.string)) continue;
      events.add(
        StringEvent(
          attackNoise: !legato && !soft,
          attackSec: legato ? 0.025 : (soft ? 0.008 : 0.003),
          stringNumber: note.string,
          midi: note.midi,
          startSec: t,
          stopSec: stopSec,
          amplitude: level * (0.55 + 0.45 * _rng.nextDouble()),
          detuneCents: _gauss() * tuningSpreadCents,
          pluckPosition: 0.12 + 0.12 * _rng.nextDouble(),
        ),
      );
      t += 0.006 + 0.022 * _rng.nextDouble();
    }
    return events;
  }

  /// Single open or fretted string pluck (tuner tests).
  StringEvent pluck(
    int stringNumber, {
    int fret = 0,
    double startSec = 0.05,
    double detuneCents = 0,
    double level = 0.25,
  }) {
    return StringEvent(
      midi: _openMidi[stringNumber]! + fret,
      startSec: startSec,
      amplitude: level,
      detuneCents: detuneCents,
      pluckPosition: 0.12 + 0.12 * _rng.nextDouble(),
    );
  }

  Float32List render(
    List<StringEvent> events, {
    required double durationSec,
    MicConditions mic = const MicConditions(),
  }) {
    final n = (durationSec * sampleRate).round();
    final out = Float64List(n);

    for (final e in events) {
      _renderString(out, e);
    }

    _highPass(out, mic.highPassHz);

    final result = Float32List(n);
    for (var i = 0; i < n; i++) {
      final v = out[i] * mic.gain + _gauss() * mic.noiseLevel;
      result[i] = v.clamp(-1.0, 1.0).toDouble();
    }
    return result;
  }

  void _renderString(Float64List out, StringEvent e) {
    final f0 = 440.0 *
        pow(2, (e.midi - 69) / 12).toDouble() *
        pow(2, e.detuneCents / 1200).toDouble();
    final start = (e.startSec * sampleRate).round();
    if (start >= out.length) return;
    final stop = e.stopSec == null ? null : (e.stopSec! * sampleRate).round();

    // Wound strings are a bit more inharmonic and ring longer.
    final inharmonicity = f0 < 150 ? 1.2e-4 : 6e-5;
    final baseTau = f0 < 150 ? 2.4 : (f0 < 250 ? 1.8 : 1.3);

    final partials = <(double hz, double amp, double tau, double phase)>[];
    for (var k = 1; k <= 24; k++) {
      final hz = k * f0 * sqrt(1 + inharmonicity * k * k);
      if (hz > 6000) break;
      final pluckComb = sin(pi * k * e.pluckPosition).abs();
      final amp = pluckComb / pow(k, 0.9);
      final tau = baseTau / (1 + 0.22 * (k - 1));
      partials.add((hz, amp, tau, _rng.nextDouble() * 2 * pi));
    }
    var norm = 0.0;
    for (final p in partials) {
      norm += p.$2 * p.$2;
    }
    norm = sqrt(norm);

    final attackSamples = max(1, (e.attackSec * sampleRate).round());
    const dampTau = 0.035;
    final end = out.length;
    for (final p in partials) {
      final w = 2 * pi * p.$1 / sampleRate;
      final a = e.amplitude * p.$2 / norm;
      final decay = exp(-1 / (p.$3 * sampleRate));
      final dampDecay = exp(-1 / (dampTau * sampleRate));
      var env = a;
      for (var i = start; i < end; i++) {
        final rel = i - start;
        final attack = rel < attackSamples ? rel / attackSamples : 1.0;
        out[i] += env * attack * sin(w * rel + p.$4);
        env *= (stop != null && i >= stop) ? dampDecay : decay;
        if (env < 1e-6) break;
      }
    }

    if (e.attackNoise) {
      // Pick / nail transient: ~8 ms of decaying broadband noise.
      final len = (0.008 * sampleRate).round();
      for (var i = 0; i < len && start + i < end; i++) {
        final env = e.amplitude * 0.35 * exp(-i / (0.002 * sampleRate));
        out[start + i] += env * _gauss();
      }
    }
  }

  /// Second-order Butterworth high-pass (RBJ biquad), in place.
  void _highPass(Float64List x, double cutoffHz) {
    if (cutoffHz <= 0) return;
    final w0 = 2 * pi * cutoffHz / sampleRate;
    final alpha = sin(w0) / (2 * sqrt1_2);
    final cosW = cos(w0);
    final b0 = (1 + cosW) / 2;
    final b1 = -(1 + cosW);
    final b2 = (1 + cosW) / 2;
    final a0 = 1 + alpha;
    final a1 = -2 * cosW;
    final a2 = 1 - alpha;
    var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0;
    for (var i = 0; i < x.length; i++) {
      final x0 = x[i];
      final y0 = (b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0;
      x2 = x1;
      x1 = x0;
      y2 = y1;
      y1 = y0;
      x[i] = y0;
    }
  }
}

/// Converts float samples to the PCM16 little-endian bytes the recorder emits.
List<int> toPcm16Bytes(Float32List samples) {
  final bytes = Uint8List(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    final v = (samples[i] * 32767).round().clamp(-32768, 32767);
    final u = v & 0xFFFF;
    bytes[2 * i] = u & 0xFF;
    bytes[2 * i + 1] = (u >> 8) & 0xFF;
  }
  return bytes;
}
