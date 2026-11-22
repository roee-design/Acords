// Ground-truth audit of guitar-mode judgements: for every note the game
// scores, was it the player's stroke *for that note* that scored it?
//
// The accuracy number alone cannot show a misattribution: a stroke's echo
// that scores the next note, while the player's real stroke for that next
// note is then thrown away, leaves the accuracy almost unchanged — but the
// player sees feedback that has nothing to do with what they played.
//
// Run:    flutter test test/bench/judgment_integrity_bench_test.dart --run-skipped
//         (--dart-define=CONDITIONS=n, default 8)
// Output: build/judgment_integrity_bench/report.txt
@Tags(['bench'])
library;

import 'dart:io';

import 'package:chord_trainer/game/rhythm_chart.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chord_trainer/models/chord_definition.dart';

import '../support/catalog_loader.dart';
import '../support/fp_scenarios.dart';
import '../support/game_replay.dart';
import '../support/judgment_audit.dart';
import '../support/realistic_sim.dart';

const _conditions = int.fromEnvironment('CONDITIONS', defaultValue: 8);

/// Referee hold times under test (ms): `--dart-define=GRID=0,150`.
/// 0 = commit the first acceptable attack (the behaviour before 2026-11-22).
const _grid = String.fromEnvironment('GRID', defaultValue: '0,150');

void main() {
  final catalog = loadChordCatalog();

  RhythmChart lesson(String id, {double speed = 0.8}) {
    final p = loadPattern(id);
    return RhythmChart.forPattern(
      pattern: p,
      chordIds: p.practiceChordIds,
      bpm: (p.defaultBpm * speed).round(),
      rounds: 1,
    );
  }

  final charts = {
    'basic_44 (4↓ per chord)': lesson('basic_44', speed: 1),
    'pop_rock_8': lesson('pop_rock_8'),
    'pop_rock_8 full speed': lesson('pop_rock_8', speed: 1),
    'boom_chick_44': lesson('boom_chick_44'),
    'island_mute': lesson('island_mute'),
    'arpeggio_pima': lesson('arpeggio_pima'),
  };

  test('judgement integrity against the true strokes', () {
    final report = StringBuffer();
    for (final setting in _grid.split(',')) {
      _run(report, catalog, charts, double.parse(setting));
    }
    final dir = Directory('build/judgment_integrity_bench')..createSync(recursive: true);
    File('${dir.path}/report.txt').writeAsStringSync(report.toString());
    // ignore: avoid_print
    print(report);
  }, timeout: const Timeout(Duration(minutes: 90)));
}

void _run(StringBuffer report, ChordCatalog catalog, Map<String, RhythmChart> charts,
    double holdMs) {
  {
    report
      ..writeln('\n######## referee hold ${holdMs.round()} ms'
          '${holdMs == 0 ? '  (= previous behaviour: first acceptable attack wins)' : ''}')
      ..writeln('$_conditions random player/phone conditions, calibration = true latency + 20 ms');
    final examples = <String>[];
    final outliers = <String>[];
    report.writeln('\n${'chart'.padRight(26)} played  scored  correct  misattr  phantom  dup  '
        'timing p50/p95/max(ms)   feedback delay beyond mic latency p50/p95/max(ms)');
    for (final entry in charts.entries) {
      var played = 0, scored = 0, correct = 0, mis = 0, phantom = 0, dup = 0;
      final timing = <double>[];
      final feedback = <double>[];
      for (var seed = 1; seed <= _conditions; seed++) {
        final a = auditCorrectPlaying(
          chart: entry.value,
          catalog: catalog,
          player: PlayerModel.random(seed),
          mic: PhoneMic.random(seed),
          seed: seed,
          holdMs: holdMs,
        );
        played += a.playedCount;
        scored += a.scoredHits;
        correct += a.correctHits;
        mis += a.misattributed.length;
        phantom += a.phantomHits;
        dup += a.duplicateCredits;
        timing.addAll(a.timingErrors);
        final mic = PhoneMic.random(seed).latencyMs;
        feedback.addAll(a.feedbackDelays.map((d) => d - mic));
        for (final c in a.hits) {
          if (c.stroke != c.decision.note!.index) continue;
          final err = c.decision.timeMs - a.played[c.stroke!]!;
          if (err.abs() > 60 && outliers.length < 30) {
            outliers.add('${entry.key} #$seed: err ${err.round()}ms +${c.sinceStrokeMs.round()}ms into stroke · ${c.decision.toLogLine()}');
          }
        }
        for (final c in a.misattributed.take(3)) {
          if (examples.length < 40) examples.add('${entry.key} #$seed: ${a.describe(c)}');
        }
      }
      String pct(int n) => '${(100 * n / played).toStringAsFixed(1)}%'.padLeft(7);
      report.writeln('${entry.key.padRight(26)} ${'$played'.padLeft(6)} ${pct(scored)} ${pct(correct)}  '
          '${pct(mis)}  ${pct(phantom)} ${'$dup'.padLeft(4)}  '
          '${median(timing).round()}/${quantile(timing.map((x) => x.abs()).toList(), 0.95).round()}/${maxAbs(timing).round()}'
          '                 ${median(feedback).round()}/${quantile(feedback, 0.95).round()}/${maxAbs(feedback).round()}');
    }
    report.writeln('\n-- examples of misattributed hits');
    examples.take(12).forEach(report.writeln);
    report.writeln('\n-- timing outliers (|judged − played| > 60 ms, correctly attributed)');
    outliers.forEach(report.writeln);

    // No correct strokes at all: anything scored is false.
    report.writeln('\n-- scored with no correct stroke (% of notes; should be ~0)');
    for (final id in ['idle-quiet', 'idle-noisy-room', 'idle-ringing', 'random-strum-open', 'wrong-chord']) {
      for (final chartName in ['basic_44 (4↓ per chord)', 'pop_rock_8', 'arpeggio_pima']) {
        final chart = charts[chartName]!;
        var scored = 0, notes = 0;
        for (var seed = 1; seed <= (_conditions + 1) ~/ 2; seed++) {
          final mic = PhoneMic.random(seed);
          final dry = fpCases.firstWhere((c) => c.id == id).build(chart, catalog, seed);
          final r = replayGame(
            audio: applyPhoneMic(dry, mic, seed: seed),
            chart: chart,
            catalog: catalog,
            chartStartMs: fpChartStartSec * 1000,
            calibrationMs: mic.latencyMs + 20,
            holdMs: holdMs,
          );
          // Idle cases: every note is wrong. Others: only notes really played wrong.
          // (idle-ringing: its one real strum is note 0.)
          final wrong = id.startsWith('idle')
              ? {for (final n in chart.notes) if (n.timeMs > 200) n.index}
              : trulyWrongNotes(id, chart, catalog, seed);
          for (final i in wrong) {
            final res = r.judge.results[i];
            if (res != null && res.judgement.name != 'miss') scored++;
          }
          notes += wrong.length;
        }
        report.writeln('   ${id.padRight(18)} ${chartName.padRight(26)} '
            '${notes == 0 ? '-' : '${(100 * scored / notes).toStringAsFixed(1)}%'}');
      }
    }
  }
}
