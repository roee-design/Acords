// Fast regression checks for the rhythm game's guitar mode: strokes count
// only with the right notes, freshly played, while actually playing.
// Full numbers: test/bench/stroke_verify_bench_test.dart.
import 'package:chord_trainer/game/rhythm_chart.dart';
import 'package:chord_trainer/game/rhythm_judge.dart';
import 'package:chord_trainer/models/strumming_pattern.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/catalog_loader.dart';
import 'support/guitar_synth.dart';
import 'support/stroke_scenarios.dart';

const _mic = MicConditions(highPassHz: 140, noiseLevel: 0.002);

double _rate(List<bool> r) => r.where((x) => x).length / r.length;

void main() {
  final catalog = loadChordCatalog();
  final chords = [
    for (final id in ['g_major', 'c_major', 'a_minor', 'd_major'])
      catalog.chordById(id)!,
  ];

  test('the correct chord strummed in a pattern is accepted', () {
    final results = <bool>[];
    for (final c in chords) {
      final (audio, strokes) =
          strumBars(GuitarSynth(seed: 3), c, randomOpen: false, mic: _mic);
      results.addAll(runStrokes(audio, strokes, c));
    }
    expect(_rate(results), greaterThan(0.8));
  });

  test('strumming open middle strings without a chord is rejected', () {
    final results = <bool>[];
    for (final c in chords) {
      final (audio, strokes) =
          strumBars(GuitarSynth(seed: 3), c, randomOpen: true, mic: _mic);
      results.addAll(runStrokes(audio, strokes, c));
    }
    expect(_rate(results), lessThan(0.08));
  });

  test('arpeggio: right notes accepted, wrong open strings rejected', () {
    final right = <bool>[];
    final wrong = <bool>[];
    for (final c in chords) {
      final synth = GuitarSynth(seed: 5);
      final (a1, s1) = arpeggioBar(synth, c, randomOpen: false, mic: _mic);
      right.addAll(runStrokes(a1, s1, c));
      final (a2, s2) = arpeggioBar(synth, c, randomOpen: true, mic: _mic);
      final r2 = runStrokes(a2, s2, c);
      for (var i = 0; i < r2.length; i++) {
        if (!s2[i].rightNote) wrong.add(r2[i]);
      }
    }
    expect(_rate(right), greaterThan(0.75));
    expect(_rate(wrong), lessThan(0.15));
  });

  test('room noise and knocks never count as a stroke', () {
    final synth = GuitarSynth(seed: 9);
    final noise = synth.render(
      [],
      durationSec: 5,
      mic: const MicConditions(highPassHz: 140, noiseLevel: 0.006),
    );
    for (var k = 1; k < 5; k++) {
      for (var i = 0; i < 300; i++) {
        noise[k * 44100 + i] += 0.05 * (synth.rand() * 2 - 1) * (1 - i / 300);
      }
    }
    expect(idleAccepts(noise, chords.first, fromSec: 0).$2, 0);
  });

  test('a missed note can be flagged as wrong notes; a hit note cannot', () {
    final pattern = StrummingPattern.fromJson({
      'id': 't',
      'name': 't',
      'beatsPerBar': 4,
      'subdivision': 2,
      'strokes': '↓ ↑ ↓ ↑ ↓ ↑ ↓ ↑',
    });
    final chart = RhythmChart.forPattern(
      pattern: pattern,
      chordIds: ['g_major'],
      bpm: 60,
      rounds: 1,
    );
    final judge = RhythmJudge(chart);
    judge.input(chart.notes[0].timeMs);
    // Note 1 is never hit: its window passes.
    final missed = judge.advance(chart.notes[1].timeMs + 500);
    expect(missed.map((n) => n.index), [1]);
    judge.flagWrongNotes(chart.notes[1]);
    judge.flagWrongNotes(chart.notes[1]); // idempotent
    judge.flagWrongNotes(chart.notes[0]); // a hit stays a hit
    expect(judge.results[1]!.wrongNotes, isTrue);
    expect(judge.results[0]!.judgement, isNot(Judgement.miss));
    expect(judge.wrongNotes, 1);
  });
}
