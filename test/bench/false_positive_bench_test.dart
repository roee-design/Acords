// False-positive bench for the rhythm game's guitar mode.
//
// Reproduces the reported false positives (doing nothing, room noise,
// knocks, voices, a chord left ringing, strumming / plucking open middle
// strings without a chord, muted strums, the wrong chord) plus two controls
// (correct playing), runs each through exactly the app's pipeline
// (engine → GuitarStrokeReferee → RhythmJudge) and reports the accuracy the
// game would show. Also replays real rounds recorded in the app's diagnostic
// mode from test/fixtures/recordings/.
//
// Run:    flutter test test/bench/false_positive_bench_test.dart --run-skipped
// Output: build/false_positive_bench/report.txt and one .log per case
//         (LEVEL / PEAK / STROKE lines, same format as logcat).
@Tags(['bench'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:chord_trainer/game/guitar_stroke_referee.dart';
import 'package:chord_trainer/game/rhythm_chart.dart';
import 'package:chord_trainer/models/strumming_pattern.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/catalog_loader.dart';
import '../support/fp_scenarios.dart';
import '../support/game_replay.dart';

const _seeds = [1, 2];
final _outDir = Directory('build/false_positive_bench');

String _pct(double v) => '${(100 * v).toStringAsFixed(1)}%'.padLeft(6);

String _counts(Map<Object, int> m) => m.isEmpty
    ? '-'
    : (m.entries.toList()..sort((a, b) => b.value - a.value))
        .map((e) => '${e.key is CaptureOutcome ? (e.key as CaptureOutcome).name : e.key}:${e.value}')
        .join(' ');

void main() {
  final catalog = loadChordCatalog();

  /// The game's first lesson level (60 % speed, practice chords × 2).
  RhythmChart lessonChart(String patternId) {
    final p = loadPattern(patternId);
    return RhythmChart.forPattern(
      pattern: p,
      chordIds: p.practiceChordIds,
      bpm: (p.defaultBpm * 0.6).round(),
    );
  }

  final charts = <String, RhythmChart>{
    'strum(pop_rock_8)': lessonChart('pop_rock_8'),
    'arpeggio(pima)': lessonChart('arpeggio_pima'),
  };

  test('synthetic false-positive cases', () {
    _outDir.createSync(recursive: true);
    final report = StringBuffer()
      ..writeln('False-positive bench — ${DateTime.now().toIso8601String()}')
      ..writeln('controls: accuracy the game shows. Other cases: share of the '
          'notes that were really played wrong (or not at all) and still '
          'counted — should be ~0%.')
      ..writeln();
    for (final chartEntry in charts.entries) {
      final chart = chartEntry.value;
      report
        ..writeln('== ${chartEntry.key}: ${chart.bpm} BPM, ${chart.bars.length} bars, '
            '${chart.notes.length} notes')
        ..writeln('${'case'.padRight(22)}${'acc'.padLeft(7)}  hits/notes  wrong  onsets  '
            'captures by outcome  |  flux peaks rejected by rule');
      for (final c in fpCases) {
        var accSum = 0.0;
        var hits = 0, notes = 0, wrong = 0, onsets = 0;
        final outcomes = <Object, int>{};
        final rejections = <Object, int>{};
        for (final seed in _seeds) {
          final audio = c.build(chart, catalog, seed);
          final r = replayGame(
            audio: audio,
            chart: chart,
            catalog: catalog,
            chartStartMs: fpChartStartSec * 1000,
          );
          if (c.isControl) {
            accSum += r.accuracy;
            hits += r.hits;
            notes += chart.notes.length;
          } else {
            // Only notes that were really played wrong count: a random pluck
            // or the "wrong" chord can contain the expected note.
            final wrongNotes = trulyWrongNotes(c.id, chart, catalog, seed);
            var accepted = 0;
            for (final i in wrongNotes) {
              final res = r.judge.results[i];
              if (res != null && res.judgement.name != 'miss') accepted++;
            }
            accSum += wrongNotes.isEmpty ? 0 : accepted / wrongNotes.length;
            hits += accepted;
            notes += wrongNotes.length;
          }
          wrong += r.judge.wrongNotes;
          onsets += r.onsets;
          r.outcomes.forEach((k, v) => outcomes[k] = (outcomes[k] ?? 0) + v);
          r.peakRejections.forEach((k, v) => rejections[k] = (rejections[k] ?? 0) + v);
          if (seed == _seeds.first) {
            final name = '${chartEntry.key.split('(').first}_${c.id}.log';
            File('${_outDir.path}/$name').writeAsStringSync(
              '# ${c.id}: ${c.description}\n# chart time 0 = audio ${fpChartStartSec}s\n'
              '${r.log.join('\n')}\n',
            );
          }
        }
        final label = c.isControl ? '✓ ${c.id}' : c.id;
        final line = '${label.padRight(22)}'
            '${_pct(accSum / _seeds.length)}  ${'$hits/$notes'.padLeft(10)}  '
            '${'$wrong'.padLeft(5)}  ${'$onsets'.padLeft(6)}  '
            '${_counts(outcomes)}  |  ${_counts(rejections)}';
        report.writeln(line);
      }
      report.writeln();
    }
    File('${_outDir.path}/report.txt').writeAsStringSync(report.toString());
    // ignore: avoid_print
    print(report);
  }, timeout: const Timeout(Duration(minutes: 20)));

  test('replay real recordings (test/fixtures/recordings)', () {
    final dir = Directory('test/fixtures/recordings');
    final sessions = dir.existsSync()
        ? (dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
          ..sort((a, b) => a.path.compareTo(b.path)))
        : <File>[];
    if (sessions.isEmpty) {
      // ignore: avoid_print
      print('No recordings in ${dir.path} yet — see README.md there.');
      return;
    }
    _outDir.createSync(recursive: true);
    for (final jsonFile in sessions) {
      final wav = File(jsonFile.path.replaceAll(RegExp(r'\.json$'), '.wav'));
      if (!wav.existsSync()) continue;
      final session = jsonDecode(jsonFile.readAsStringSync()) as Map<String, dynamic>;
      final pattern = StrummingPattern.fromJson(session['pattern'] as Map<String, dynamic>);
      final chart = RhythmChart.forPattern(
        pattern: pattern,
        chordIds: (session['bars'] as List<dynamic>).cast<String>(),
        bpm: (session['bpm'] as num).toInt(),
        rounds: 1,
      );
      final (audio, rate) = readWav(wav);
      final r = replayGame(
        audio: audio,
        chart: chart,
        catalog: catalog,
        sampleRate: rate,
        chartStartMs: ((session['sampleZeroToStartMs'] as num?) ?? 0).toDouble() +
            (session['leadInMs'] as num).toDouble(),
        calibrationMs: (session['calibrationMs'] as num).toDouble(),
      );
      final appAcc = ((session['result'] as Map<String, dynamic>)['accuracy'] as num).toDouble();
      final name = jsonFile.uri.pathSegments.last.replaceAll('.json', '');
      File('${_outDir.path}/recording_$name.log').writeAsStringSync(r.log.join('\n'));
      // ignore: avoid_print
      print('${name.padRight(40)} replay acc ${_pct(r.accuracy)} (app showed ${_pct(appAcc)})  '
          'hits ${r.hits}/${chart.notes.length} wrong ${r.judge.wrongNotes} onsets ${r.onsets}  '
          '${_counts({...r.outcomes})}  |  ${_counts({...r.peakRejections})}  '
          '[label: ${session['label'] ?? '-'}]');
    }
  }, timeout: const Timeout(Duration(minutes: 20)));
}
