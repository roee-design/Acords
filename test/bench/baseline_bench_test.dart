// Baseline of the legacy ChordMatcher on synthetic strums.
// Run: flutter test test/bench/baseline_bench_test.dart
import 'dart:typed_data';

import 'package:chord_trainer/audio/fft_processor.dart';
import 'package:chord_trainer/audio/frequency_utils.dart';
import 'package:chord_trainer/chord/chord_matcher.dart';
import 'package:chord_trainer/models/feedback_result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/catalog_loader.dart';
import '../support/guitar_synth.dart';

void main() {
  test('legacy matcher baseline', () {
    final catalog = loadChordCatalog();
    final chords = catalog.chords;
    const sr = 44100;
    const fft = 8192;
    final proc = FftProcessor(fftSize: fft, sampleRate: sr.toDouble());
    final matcher = ChordMatcher(fftProcessor: proc);
    final conditions = [
      const MicConditions(highPassHz: 80, noiseLevel: 0.001),
      const MicConditions(highPassHz: 150, noiseLevel: 0.003),
      const MicConditions(highPassHz: 220, noiseLevel: 0.004, gain: 0.5),
    ];
    var accepts = 0, trials = 0, falseAccepts = 0, falseTrials = 0;
    final missByChord = <String, int>{};
    final faPairs = <String, int>{};
    for (final mic in conditions) {
      for (var seed = 1; seed <= 3; seed++) {
        for (final played in chords) {
          final synth = GuitarSynth(seed: seed * 100 + chords.indexOf(played));
          final audio = synth.render(
            synth.strum(played, startSec: 0.2),
            durationSec: 1.6,
            mic: mic,
          );
          // Frames every 80 ms once the ring buffer is full.
          final frames = <(List<double>, double)>[];
          for (var end = fft; end <= audio.length; end += (0.08 * sr).round()) {
            final frame = Float32List.sublistView(audio, end - fft, end);
            frames.add((proc.computeMagnitudes(frame), frameRms(frame)));
          }
          for (final target in chords) {
            var run = 0, hit = false;
            for (final f in frames) {
              final fb = matcher.evaluate(
                chord: target,
                magnitudes: f.$1,
                referenceA4Hz: 440,
                inputLevel: f.$2,
              );
              run = fb.matchStatus == ChordMatchStatus.perfect ? run + 1 : 0;
              if (run >= 2) { hit = true; break; }
            }
            if (target.id == played.id) {
              trials++;
              if (hit) { accepts++; } else {
                missByChord[played.id] = (missByChord[played.id] ?? 0) + 1;
              }
            } else {
              falseTrials++;
              if (hit) {
                falseAccepts++;
                final k = 'target ${target.id} <- played ${played.id}';
                faPairs[k] = (faPairs[k] ?? 0) + 1;
              }
            }
          }
        }
      }
    }
    // ignore: avoid_print
    print('ACCEPT ${(100 * accepts / trials).toStringAsFixed(1)}% ($accepts/$trials)');
    // ignore: avoid_print
    print('FALSE ACCEPT ${(100 * falseAccepts / falseTrials).toStringAsFixed(2)}% ($falseAccepts/$falseTrials)');
    // ignore: avoid_print
    print('misses: $missByChord');
    final top = faPairs.entries.toList()..sort((a, b) => b.value - a.value);
    // ignore: avoid_print
    print('top false accepts: ${top.take(15).map((e) => '${e.key} x${e.value}').join('\n')}');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
