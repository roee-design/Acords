import 'package:chord_trainer/game/rhythm_chart.dart';
import 'package:chord_trainer/game/rhythm_judge.dart';
import 'package:chord_trainer/models/song_definition.dart';
import 'package:chord_trainer/models/strumming_pattern.dart';
import 'package:flutter_test/flutter_test.dart';

StrummingPattern _pattern(String strokes, {int beats = 4, int sub = 2}) =>
    StrummingPattern.fromJson({
      'id': 't',
      'name': 't',
      'beatsPerBar': beats,
      'subdivision': sub,
      'strokes': strokes,
    });

void main() {
  test('chart places sounding slots and skips rests', () {
    final chart = RhythmChart.forPattern(
      pattern: _pattern('↓ - ↓ ↑ - ↑ ↓ ↑'),
      chordIds: ['c_major', 'g_major'],
      bpm: 60,
      rounds: 1,
    );
    expect(chart.bars, hasLength(2));
    expect(chart.slotMs, 500);
    expect(chart.notes, hasLength(12)); // 6 strokes × 2 bars
    expect(chart.notes.first.timeMs, 0);
    expect(chart.notes[1].timeMs, 1000); // slot 2
    expect(chart.notes[6].timeMs, 4000); // bar 2
    expect(chart.barAt(4100)!.chordId, 'g_major');
  });

  test('short pattern repeats to fill the bar', () {
    final chart = RhythmChart.forPattern(
      pattern: _pattern('p i m a i m a i', sub: 4),
      chordIds: ['c_major'],
      bpm: 60,
      rounds: 1,
    );
    expect(chart.notes, hasLength(16));
  });

  test('song chart: one bar per chord segment with lyrics', () {
    final song = SongDefinition.fromJson({
      'id': 's',
      'title': 's',
      'pattern': '↓ ↓ ↓ ↓',
      'lines': [
        {
          'segments': [
            {'chordId': 'g_major', 'lyrics': 'Hello '},
            {'chordId': 'c_major', 'lyrics': 'world'},
          ],
        },
      ],
    });
    final chart =
        RhythmChart.forSong(song: song, pattern: song.pattern, bpm: 90);
    expect(chart.bars.map((b) => b.chordId), ['g_major', 'c_major']);
    expect(chart.bars[1].lyrics, 'world');
    expect(chart.bars[1].lineIndex, 0);
  });

  test('judge: perfect, good, miss, extra, direction', () {
    final chart = RhythmChart.forPattern(
      pattern: _pattern('↓ ↑ ↓ ↑', sub: 1),
      chordIds: ['c_major'],
      bpm: 60,
      rounds: 1,
    ); // notes at 0, 1000, 2000, 3000
    final judge = RhythmJudge(chart);

    var out = judge.input(20, direction: StrokeDirection.down);
    expect(out.result!.judgement, Judgement.perfect);

    out = judge.input(1110);
    expect(out.result!.judgement, Judgement.good);
    expect(out.result!.offsetMs, closeTo(110, 0.001));

    out = judge.input(1500);
    expect(out.isExtra, isTrue);

    // Note at 2000 is never played → missed once its window passes.
    expect(judge.advance(2200), hasLength(1));
    expect(judge.combo, 0);

    out = judge.input(2990, direction: StrokeDirection.down); // ↑ expected
    expect(out.result!.judgement, Judgement.good);
    expect(out.result!.wrongDirection, isTrue);

    expect(judge.isFinished, isTrue);
    expect(judge.perfects, 1);
    expect(judge.goods, 2);
    expect(judge.misses, 1);
    expect(judge.extras, 1);
  });

  test('stars follow accuracy; combo raises the multiplier', () {
    final chart = RhythmChart.forPattern(
      pattern: _pattern('↓ ↓ ↓ ↓', sub: 1),
      chordIds: ['c_major', 'c_major', 'c_major'],
      bpm: 120,
      rounds: 1,
    );
    final judge = RhythmJudge(chart);
    for (final n in chart.notes) {
      judge.input(n.timeMs + 5);
    }
    expect(judge.stars, 3);
    expect(judge.maxCombo, chart.notes.length);
    expect(judge.multiplier, greaterThan(1));
  });
}
