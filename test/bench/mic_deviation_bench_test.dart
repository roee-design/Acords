// Realistic end-to-end simulation of the rhythm game's guitar mode.
//
// For several random (player, guitar, phone, room) conditions it simulates
// the whole flow the app goes through:
//   1. the calibration screen  → estimated mic latency vs. the true one,
//   2. correct playing of three lessons through the phone mic → the accuracy
//      the game shows, why strokes were not counted, how far the judged
//      timing is from what was really played, and how each string's level
//      and pitch reach the matcher,
//   3. wrong / no playing through the same mic → false accepts.
//
// Run:    flutter test test/bench/mic_deviation_bench_test.dart --run-skipped
// Output: build/mic_deviation_bench/report.txt
@Tags(['bench'])
library;

import 'dart:io';
import 'dart:math';

import 'package:chord_trainer/game/guitar_stroke_referee.dart';
import 'package:chord_trainer/game/rhythm_chart.dart';
import 'package:chord_trainer/models/strumming_pattern.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/catalog_loader.dart';
import '../support/fp_scenarios.dart';
import '../support/game_replay.dart';
import '../support/realistic_sim.dart';
import '../support/sim_session.dart';

/// Number of random conditions; override with `--dart-define=CONDITIONS=n`.
const _conditions = int.fromEnvironment('CONDITIONS', defaultValue: 8);
const _runFp = bool.fromEnvironment('FP', defaultValue: true);
const _fpCaseIds = ['idle-ringing', 'random-strum-open', 'random-pluck-middle', 'wrong-chord'];

class _Stats {
  final List<double> v = [];
  void add(double x) => v.add(x);
  double q(double p) {
    if (v.isEmpty) return double.nan;
    final s = [...v]..sort();
    return s[(p * (s.length - 1)).round()];
  }

  double get mean => v.isEmpty ? double.nan : v.reduce((a, b) => a + b) / v.length;
  double get sd {
    if (v.length < 2) return double.nan;
    final m = mean;
    return sqrt(v.map((x) => (x - m) * (x - m)).reduce((a, b) => a + b) / (v.length - 1));
  }

  String summary([int digits = 0]) => v.isEmpty
      ? 'n=0'
      : 'mean ${mean.toStringAsFixed(digits)} sd ${sd.toStringAsFixed(digits)} '
          'p5 ${q(0.05).toStringAsFixed(digits)} p50 ${q(0.5).toStringAsFixed(digits)} '
          'p95 ${q(0.95).toStringAsFixed(digits)} (n=${v.length})';
}

String _reason(CaptureDecision d) {
  switch (d.outcome) {
    case CaptureOutcome.hit:
      return 'hit';
    case CaptureOutcome.noNote:
      return 'no note in window (timing)';
    case CaptureOutcome.unanchored:
      return 'unanchored';
    case CaptureOutcome.notFresh:
      if (d.detail.contains('too quiet')) return 'too quiet';
      if (d.detail.contains('not plucked')) return 'not fresh: string not plucked';
      if (d.detail.contains('freshly struck')) return 'not fresh: <2 notes struck';
      return 'not fresh: score low';
    case CaptureOutcome.wrongNotes:
      final text = d.detail.contains(': ') ? d.detail.split(': ').skip(1).join(': ') : d.detail;
      return 'wrong: ${text.split(' (').first.replaceAll(RegExp(r' [0-9]+Hz'), '')}';
  }
}

String _band(double hz) =>
    hz < 110 ? '<110Hz' : (hz < 170 ? '110-170' : (hz < 260 ? '170-260' : '>260Hz'));

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

  final charts = {
    'strum pop_rock_8': lesson('pop_rock_8'),
    'bass+strum boom_chick': lesson('boom_chick_44'),
    'arpeggio pima': lesson('arpeggio_pima'),
  };

  test('guitar mode through a simulated phone', () {
    final report = StringBuffer()
      ..writeln('Guitar-mode simulation — ${DateTime.now().toIso8601String()}')
      ..writeln('$_conditions random player/guitar/phone/room conditions');
    final latencyError = _Stats();
    final timing = <String, _Stats>{};
    final level = <String, _Stats>{};
    final cents = <String, _Stats>{};
    final missing = <String, List<int>>{}; // band → [missing, total]
    final accuracy = {for (final c in charts.keys) c: _Stats()};
    final reasons = {for (final c in charts.keys) c: <String, int>{}};
    final falseAccept = <String, _Stats>{};
    // Per missed note (not per detection): what happened to it.
    final missedNotes = {for (final c in charts.keys) c: <String, int>{}};
    var unreliableCalibrations = 0;

    report.writeln('\n== 1+2. per condition: calibration and correct playing');
    for (var seed = 1; seed <= _conditions; seed++) {
      final player = PlayerModel.random(seed);
      final mic = PhoneMic.random(seed);
      final detune = player.stringDetunes();
      report
        ..writeln('\n#$seed player: $player')
        ..writeln('#$seed phone:  $mic');

      final cal = simulateCalibration(catalog: catalog, player: player, mic: mic, seed: seed);
      final estimate = (cal?.latencyMs ?? 150).toDouble();
      if (cal == null || !cal.isReliable) unreliableCalibrations++;
      latencyError.add(estimate - mic.latencyMs);
      report.writeln('#$seed calibration: true ${mic.latencyMs.round()}ms → estimated '
          '${estimate.round()}ms (error ${(estimate - mic.latencyMs).round()}ms, '
          'spread ${cal?.spreadMs.toStringAsFixed(0)}ms, n=${cal?.samples}, '
          '${cal?.isReliable == true ? 'reliable' : 'NOT reliable'})');

      for (final entry in charts.entries) {
        final chart = entry.value;
        final perf = perform(chart: chart, catalog: catalog, player: player, seed: seed * 100 + 1);
        final audio = applyPhoneMic(perf.dry, mic, seed: seed);
        final perNote = <int, List<CaptureDecision>>{};
        final strays = <CaptureDecision>[];
        final r = replayGame(
          audio: audio,
          chart: chart,
          catalog: catalog,
          chartStartMs: 1000,
          calibrationMs: estimate,
          onDecision: (d, match) {
            final why = _reason(d);
            if (d.outcome != CaptureOutcome.hit) {
              reasons[entry.key]![why] = (reasons[entry.key]![why] ?? 0) + 1;
            }
            final note = d.note;
            if (note == null) {
              strays.add(d);
              return;
            }
            perNote.putIfAbsent(note.index, () => []).add(d);
            if (d.outcome == CaptureOutcome.hit) {
              timing.putIfAbsent(note.kind.name, _Stats.new).add(d.timeMs - perf.playedMs[note.index]);
            }
            if (match != null && note.kind == PatternEventKind.down) {
              for (final s in match.feedback.activeStringFeedback) {
                final band = _band(s.expectedHz);
                final m = missing.putIfAbsent(band, () => [0, 0]);
                m[1]++;
                if (s.status.name == 'missing') m[0]++;
                if (s.energy > 0 && match.bandPeak > 0) {
                  level.putIfAbsent(band, _Stats.new).add(20 * log(s.energy / match.bandPeak) / ln10);
                }
                final c = s.pitchCentsOffset;
                if (c != null && c.abs() < 150) {
                  cents.putIfAbsent(band, _Stats.new).add(c - detune[s.stringNumber]);
                }
              }
            }
          },
        );
        for (final note in chart.notes) {
          final result = r.judge.results[note.index];
          if (result != null && result.judgement.name != 'miss') continue;
          final ds = perNote[note.index] ?? const <CaptureDecision>[];
          String why;
          if (ds.any((d) => d.outcome == CaptureOutcome.wrongNotes)) {
            why = _reason(ds.firstWhere((d) => d.outcome == CaptureOutcome.wrongNotes));
          } else if (ds.any((d) => d.outcome == CaptureOutcome.unanchored)) {
            why = 'unanchored (${note.kind.name})';
          } else if (ds.any((d) => d.outcome == CaptureOutcome.notFresh)) {
            why = '${_reason(ds.lastWhere((d) => d.outcome == CaptureOutcome.notFresh))} (${note.kind.name})';
          } else {
            // No capture was matched to this note: was a strum heard near the
            // time it was really played?
            final played = perf.playedMs[note.index];
            final near = strays.where((d) => (d.timeMs - played).abs() < 200);
            why = near.isEmpty
                ? 'no strum detected (${note.kind.name})'
                : 'strum heard but outside window (${note.kind.name})';
          }
          missedNotes[entry.key]![why] = (missedNotes[entry.key]![why] ?? 0) + 1;
        }
        accuracy[entry.key]!.add(r.accuracy * 100);
        report.writeln('#$seed ${entry.key.padRight(24)} accuracy ${(100 * r.accuracy).toStringAsFixed(0).padLeft(3)}%  '
            'hits ${r.hits}/${chart.notes.length}  wrong ${r.judge.wrongNotes}');

        // 3. False accepts through the same phone (first half of conditions).
        if (_runFp && seed <= (_conditions + 1) ~/ 2 && entry.key != 'bass+strum boom_chick') {
          for (final c in fpCases.where((c) => _fpCaseIds.contains(c.id))) {
            final dry = c.build(chart, catalog, seed);
            final fpAudio = applyPhoneMic(dry, mic, seed: seed);
            final fr = replayGame(
              audio: fpAudio,
              chart: chart,
              catalog: catalog,
              chartStartMs: fpChartStartSec * 1000,
              calibrationMs: estimate,
            );
            // Only notes that were really played wrong count: a random
            // pluck or the "wrong" chord can contain the expected note.
            final wrong = trulyWrongNotes(c.id, chart, catalog, seed);
            var accepted = 0;
            for (final i in wrong) {
              final res = fr.judge.results[i];
              if (res != null && res.judgement.name != 'miss') accepted++;
            }
            falseAccept
                .putIfAbsent('${c.id} / ${entry.key}', _Stats.new)
                .add(wrong.isEmpty ? 0 : 100 * accepted / wrong.length);
          }
        }
      }
    }

    report
      ..writeln('\n== SUMMARY')
      ..writeln('\n-- calibration: estimated − true latency (ms)')
      ..writeln('   ${latencyError.summary()}   unreliable: $unreliableCalibrations/$_conditions')
      ..writeln('\n-- correct playing: accuracy the game shows (%)');
    for (final e in accuracy.entries) {
      report.writeln('   ${e.key.padRight(24)} mean ${e.value.mean.toStringAsFixed(1)}  '
          'min ${e.value.q(0).toStringAsFixed(0)}  median ${e.value.q(0.5).toStringAsFixed(0)}');
    }
    report.writeln('\n-- correct playing: why strums were not counted');
    for (final e in reasons.entries) {
      final sorted = e.value.entries.toList()..sort((a, b) => b.value - a.value);
      report.writeln('   ${e.key}: ${sorted.map((x) => '${x.key} ×${x.value}').join('; ')}');
    }
    report.writeln('\n-- correct playing: what happened to each note that was NOT counted');
    for (final e in missedNotes.entries) {
      final sorted = e.value.entries.toList()..sort((a, b) => b.value - a.value);
      report.writeln('   ${e.key}: ${sorted.map((x) => '${x.key} ×${x.value}').join('; ')}');
    }
    report.writeln('\n-- timing: judged time − really played time, for hits (ms)');
    for (final e in timing.entries) {
      report.writeln('   ${e.key.padRight(8)} ${e.value.summary()}');
    }
    report.writeln('\n-- how each string of a ↓ strum reaches the matcher, by pitch');
    for (final band in const ['<110Hz', '110-170', '170-260', '>260Hz']) {
      final m = missing[band];
      if (m == null) continue;
      report.writeln('   ${band.padRight(8)} "missing" ${(100 * m[0] / m[1]).toStringAsFixed(0).padLeft(3)}% of ${m[1]}  '
          'level dB vs strongest: ${level[band]?.summary(0)}');
      report.writeln('   ${''.padRight(8)} pitch error (cents): ${cents[band]?.summary(0)}');
    }
    report.writeln('\n-- wrong / no playing through the same phones: accuracy shown (%), should be ~0');
    for (final e in falseAccept.entries) {
      report.writeln('   ${e.key.padRight(46)} mean ${e.value.mean.toStringAsFixed(1)}  max ${e.value.q(1).toStringAsFixed(1)}');
    }

    final dir = Directory('build/mic_deviation_bench')..createSync(recursive: true);
    File('${dir.path}/report.txt').writeAsStringSync(report.toString());
    // ignore: avoid_print
    print(report);
  }, timeout: const Timeout(Duration(minutes: 60)));
}
