// Strum detection for the rhythm game: default vs game-sensitive settings,
// including soft finger strums (nylon, no pick noise).
// Run: flutter test test/bench/onset_game_bench_test.dart --run-skipped
@Tags(['bench'])
library;

import 'package:chord_trainer/audio/onset_detector.dart';
import 'package:chord_trainer/models/chord_definition.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/catalog_loader.dart';
import '../support/guitar_synth.dart';
import 'onset_bench_test.dart' show runChunks, onsetMics, Scenario, onsetScenarios;

List<Scenario> softScenarios(ChordCatalog catalog, int seed, MicConditions mic) {
  ChordDefinition c(String id) => catalog.chordById(id)!;
  final synth = GuitarSynth(seed: seed);
  final events = <StringEvent>[];
  final truth = <double>[];
  const eighth = 60 / 80 / 2;
  const slots = [0, 2, 3, 5, 6, 7];
  final prog = [c('c_major'), c('a_minor'), c('f_major'), c('g_major')];
  for (var bar = 0; bar < 4; bar++) {
    final barStart = 0.3 + bar * 8 * eighth;
    for (final slot in slots) {
      final t = barStart + slot * eighth;
      final down = slot.isEven;
      truth.add(t);
      events.addAll(synth.strum(prog[bar], startSec: t, soft: true, down: down,
          level: down ? 0.12 : 0.07, onlyStrings: down ? null : {1, 2, 3, 4},
          stopSec: t + eighth * 2.2));
    }
  }
  return [Scenario('soft strumming', synth.render(events, durationSec: 0.3 + 32 * eighth + 0.5, mic: mic), truth)];
}

void main() {
  final catalog = loadChordCatalog();
  final configs = <String, OnsetDetector Function()>{
    'default': OnsetDetector.new,
    'game': OnsetDetector.forRhythmGame,
  };
  for (final cfg in configs.entries) {
    test('[${cfg.key}]', () {
      final stats = <String, List<int>>{};
      for (final mic in onsetMics) {
        for (var seed = 1; seed <= 4; seed++) {
          for (final sc in [...onsetScenarios(catalog, seed * 10, mic), ...softScenarios(catalog, seed * 7, mic)]) {
            final found = runChunks(cfg.value(), sc.audio).map((s) => s / 44100).toList();
            final used = <int>{};
            var tp = 0;
            for (final t in sc.truthSec) {
              for (var i = 0; i < found.length; i++) {
                final dt = found[i] - t;
                if (!used.contains(i) && dt > -0.03 && dt < 0.08) { used.add(i); tp++; break; }
              }
            }
            final s = stats.putIfAbsent(sc.name, () => [0, 0, 0]);
            s[0] += tp; s[1] += sc.truthSec.length - tp; s[2] += found.length - used.length;
          }
        }
      }
      for (final e in stats.entries) {
        // ignore: avoid_print
        print('[${cfg.key}] ${e.key.padRight(18)} hit=${e.value[0]} missed=${e.value[1]} false=${e.value[2]}');
      }
    }, timeout: const Timeout(Duration(minutes: 5)));
  }
}
