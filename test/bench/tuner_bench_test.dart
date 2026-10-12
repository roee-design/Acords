// Tuner accuracy: legacy FFT peak-picking vs YIN.
// Run: flutter test test/bench/tuner_bench_test.dart
import 'dart:typed_data';

import 'package:chord_trainer/audio/fft_processor.dart';
import 'package:chord_trainer/audio/frequency_utils.dart';
import 'package:chord_trainer/audio/pitch_tuner.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/guitar_synth.dart';
import '../support/legacy_pitch.dart';

const openStrings = <(int, int, String)>[
  (6, 40, 'low E'), (5, 45, 'A'), (4, 50, 'D'),
  (3, 55, 'G'), (2, 59, 'B'), (1, 64, 'high E'),
];

class Stats {
  final errors = <double>[];
  var gross = 0;
  var noReading = 0;
  var n = 0;

  void add(PitchReading r, int expectedString, double trueCents) {
    n++;
    final c = r.centsOffset;
    if (c == null || r.isSilent || r.awaitingOpenString) {
      noReading++;
      return;
    }
    if (r.closestStringNumber != expectedString || (c - trueCents).abs() > 50) {
      gross++;
      return;
    }
    errors.add((c - trueCents).abs());
  }

  @override
  String toString() {
    final e = [...errors]..sort();
    final mean = e.isEmpty ? 0 : e.reduce((a, b) => a + b) / e.length;
    final within3 = e.where((x) => x <= 3).length;
    return 'readings=${e.length}/$n  within±3¢ ${(100 * within3 / n).toStringAsFixed(0)}%  '
        'mean err ${mean.toStringAsFixed(1)}¢  p90 ${e.isEmpty ? 0 : e[(e.length * 0.9).floor()].toStringAsFixed(1)}¢  '
        'wrong string/octave $gross  no reading $noReading';
  }
}

void main() {
  test('tuner accuracy', () {
    final proc = FftProcessor(fftSize: 8192, sampleRate: 44100);
    final results = <String, Stats>{};
    const mics = [
      MicConditions(highPassHz: 120, noiseLevel: 0.001),
      MicConditions(highPassHz: 250, noiseLevel: 0.003, gain: 0.5),
      MicConditions(highPassHz: 350, noiseLevel: 0.003, gain: 0.5),
    ];
    for (final mic in mics) {
      for (final s in openStrings) {
        for (final detune in [-40.0, -20.0, -8.0, 0.0, 8.0, 20.0, 40.0]) {
          final synth = GuitarSynth(seed: s.$1 * 100 + detune.toInt());
          final audio = synth.render(
            [synth.pluck(s.$1, detuneCents: detune, startSec: 0.05)],
            durationSec: 2.3,
            mic: mic,
          );
          for (final at in [0.2, 0.5, 1.2, 2.2]) {
            final end = (at * 44100).round();
            final frame = Float32List.sublistView(audio, end - 8192, end);
            final level = frameRms(frame);
            for (final locked in [false, true]) {
              final mode = locked ? 'locked' : 'auto';
              final legacy = LegacyPitchEstimator(
                openStrings: openStrings,
                targetStringNumber: locked ? s.$1 : null,
              ).estimate(proc.computeMagnitudes(frame), level);
              final yin = TunerPitchEstimator()
                ..openStrings = openStrings
                ..targetStringNumber = locked ? s.$1 : null;
              final y = yin.estimate(frame, level);
              results.putIfAbsent('legacy $mode', Stats.new).add(legacy, s.$1, detune);
              results.putIfAbsent('yin    $mode', Stats.new).add(y, s.$1, detune);
            }
          }
        }
      }
    }
    for (final e in results.entries) {
      // ignore: avoid_print
      print('${e.key}: ${e.value}');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
