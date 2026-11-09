// Fast end-to-end checks of the rhythm game's guitar mode against simulated
// players and phone microphones (see test/support/realistic_sim.dart).
// The full measurement is test/bench/mic_deviation_bench_test.dart.
import 'package:chord_trainer/game/rhythm_chart.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/catalog_loader.dart';
import 'support/fp_scenarios.dart';
import 'support/game_replay.dart';
import 'support/realistic_sim.dart';
import 'support/sim_session.dart';

void main() {
  final catalog = loadChordCatalog();
  RhythmChart lesson(String id) {
    final p = loadPattern(id);
    return RhythmChart.forPattern(
      pattern: p,
      chordIds: p.practiceChordIds,
      bpm: (p.defaultBpm * 0.8).round(),
      rounds: 1,
    );
  }

  test('calibration finds the phone latency', () {
    for (final seed in [2, 5, 8]) {
      final mic = PhoneMic.random(seed);
      final cal = simulateCalibration(
        catalog: catalog,
        player: PlayerModel.random(seed),
        mic: mic,
        seed: seed,
      );
      expect(cal, isNotNull, reason: 'seed $seed');
      expect(cal!.isReliable, isTrue, reason: 'seed $seed: $mic');
      expect(cal.latencyMs, closeTo(mic.latencyMs, 50), reason: 'seed $seed: $mic');
    }
  });

  test('correct playing through a phone is mostly counted', () {
    for (final (patternId, minimum) in [
      ('pop_rock_8', 0.65),
      ('arpeggio_pima', 0.8),
    ]) {
      final chart = lesson(patternId);
      var sum = 0.0;
      const seeds = [1, 4, 7];
      for (final seed in seeds) {
        final mic = PhoneMic.random(seed);
        final perf = perform(
          chart: chart,
          catalog: catalog,
          player: PlayerModel.random(seed),
          seed: seed * 100 + 1,
        );
        final r = replayGame(
          audio: applyPhoneMic(perf.dry, mic, seed: seed),
          chart: chart,
          catalog: catalog,
          chartStartMs: 1000,
          calibrationMs: mic.latencyMs + 20,
        );
        sum += r.accuracy;
      }
      expect(sum / seeds.length, greaterThan(minimum), reason: patternId);
    }
  });

  test('strumming open strings without a chord is not counted', () {
    final chart = lesson('pop_rock_8');
    for (final seed in [1, 4]) {
      final mic = PhoneMic.random(seed);
      final dry = fpCases
          .firstWhere((c) => c.id == 'random-strum-open')
          .build(chart, catalog, seed);
      final r = replayGame(
        audio: applyPhoneMic(dry, mic, seed: seed),
        chart: chart,
        catalog: catalog,
        chartStartMs: fpChartStartSec * 1000,
        calibrationMs: mic.latencyMs + 20,
      );
      expect(r.accuracy, lessThan(0.1), reason: 'seed $seed');
    }
  });

  test('a chord left ringing does not keep scoring', () {
    final chart = lesson('arpeggio_pima');
    final mic = PhoneMic.random(3);
    final dry = fpCases
        .firstWhere((c) => c.id == 'idle-ringing')
        .build(chart, catalog, 3);
    final r = replayGame(
      audio: applyPhoneMic(dry, mic, seed: 3),
      chart: chart,
      catalog: catalog,
      chartStartMs: fpChartStartSec * 1000,
      calibrationMs: mic.latencyMs + 20,
    );
    expect(r.accuracy, lessThan(0.1));
  });
}
