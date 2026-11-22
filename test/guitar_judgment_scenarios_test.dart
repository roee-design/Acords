// Guitar mode, end to end: simulated player → simulated phone mic → the
// app's engine, referee and judge (test/support/game_replay.dart) — with a
// ground-truth check of *which* stroke produced every judgement
// (test/support/judgment_audit.dart).
//
// The core requirement: every real stroke is judged on its own, against its
// own note, exactly once; a chord that only rings, silence or noise never
// scores. The randomized measurement is
// test/bench/judgment_integrity_bench_test.dart.
import 'dart:math';
import 'dart:typed_data';

import 'package:chord_trainer/audio/chord_detection_engine.dart';
import 'package:chord_trainer/audio/onset_detector.dart';
import 'package:chord_trainer/game/guitar_stroke_referee.dart';
import 'package:chord_trainer/game/rhythm_chart.dart';
import 'package:chord_trainer/models/strumming_pattern.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/catalog_loader.dart';
import 'support/fp_scenarios.dart';
import 'support/game_replay.dart';
import 'support/judgment_audit.dart';
import 'support/realistic_sim.dart';

/// A typical phone in a typical room (see PhoneMic.random for the ranges).
const _phone = PhoneMic(
  latencyMs: 150,
  highPassHz: 140,
  eq: [(300, 2, 1.5), (2500, 4, 1)],
  roomRt60: 0.35,
  roomMix: 0.2,
  noiseLevel: 0.002,
  gain: 0.8,
);

PlayerModel _player({double biasMs = 0, double jitterMs = 8, bool soft = false, int seed = 1}) =>
    PlayerModel(
      timingBiasMs: biasMs,
      timingJitterMs: jitterMs,
      strumSpanMs: 45,
      upStrings: 3,
      soft: soft,
      level: 0.2,
      seed: seed,
    );

RhythmChart _chart(String strokes, List<String> chords,
        {int bpm = 80, int beatsPerBar = 4, int subdivision = 1}) =>
    RhythmChart.forPattern(
      pattern: StrummingPattern.fromJson({
        'id': 'test',
        'name': 'test',
        'beatsPerBar': beatsPerBar,
        'subdivision': subdivision,
        'strokes': strokes,
      }),
      chordIds: chords,
      bpm: bpm,
      rounds: 1,
    );

void main() {
  final catalog = loadChordCatalog();

  /// Am ×4 ↓, C ×4 ↓, G ×4 ↓ — the example from the requirement.
  final amCG = _chart('↓ ↓ ↓ ↓', ['a_minor', 'c_major', 'g_major']);

  AuditResult play(RhythmChart chart, PlayerModel player,
      {PhoneMic mic = _phone, double calErrorMs = 15, int seed = 3,
      int Function(int)? chunkOf, double processingDelayMs = 0, bool deliverTwice = false}) {
    final perf = perform(chart: chart, catalog: catalog, player: player, seed: seed);
    return auditRound(
      chart: chart,
      catalog: catalog,
      played: [for (final n in chart.notes) perf.playedMs[n.index]],
      trueLatencyMs: mic.latencyMs,
      calibrationMs: mic.latencyMs + calErrorMs,
      audio: applyPhoneMic(perf.dry, mic, seed: seed),
      chunkOf: chunkOf,
      processingDelayMs: processingDelayMs,
      deliverTwice: deliverTwice,
    );
  }

  /// Every note judged at most once, every hit backed by exactly one attack.
  void expectJudgedOnce(AuditResult a) {
    final hitsPerNote = <int, int>{};
    final hitsPerAttack = <int, int>{};
    for (final d in a.run.decisions.where((d) => d.outcome == CaptureOutcome.hit)) {
      hitsPerNote[d.note!.index] = (hitsPerNote[d.note!.index] ?? 0) + 1;
      hitsPerAttack[d.onsetSample!] = (hitsPerAttack[d.onsetSample!] ?? 0) + 1;
    }
    expect(hitsPerNote.values.every((n) => n == 1), isTrue, reason: 'a note scored twice');
    expect(hitsPerAttack.values.every((n) => n == 1), isTrue, reason: 'an attack scored twice');
    expect(a.duplicateCredits, 0, reason: 'one physical stroke credited to two notes');
    expect(a.run.judge.results.length, a.chart.notes.length, reason: 'every note gets a result');
  }

  String misattributed(AuditResult a) => a.misattributed.map(a.describe).join('\n');

  double medianOffset(AuditResult a) => median([
        for (final r in a.run.judge.results.values)
          if (r.offsetMs != null) r.offsetMs!,
      ]);

  test('regression: a ringing chord\'s false attack just before a strum does not take its note', () {
    // Bench condition #1 (basic_44, 72 BPM): the G chord left ringing fires an
    // attack 77 ms before the player's 4th strum. Its capture (the 126 ms
    // after it) already contains that strum, so it passed the note check and
    // — committed first — scored note #3 at −114 ms, while the real strum
    // found the note taken and was thrown away as an extra stroke.
    final p = loadPattern('basic_44');
    final chart = RhythmChart.forPattern(
        pattern: p, chordIds: p.practiceChordIds, bpm: p.defaultBpm, rounds: 1);
    AuditResult run(double holdMs) {
      final perf = perform(chart: chart, catalog: catalog, player: PlayerModel.random(1), seed: 101);
      final mic = PhoneMic.random(1);
      return auditRound(
        chart: chart,
        catalog: catalog,
        played: [for (final n in chart.notes) perf.playedMs[n.index]],
        trueLatencyMs: mic.latencyMs,
        calibrationMs: mic.latencyMs + 20,
        audio: applyPhoneMic(perf.dry, mic, seed: 1),
        holdMs: holdMs,
      );
    }

    final before = run(0); // first acceptable attack wins (old behaviour)
    expect(before.misattributed.map((c) => c.decision.note!.index), contains(3),
        reason: 'the bug no longer reproduces with the old rule');
    final after = run(150);
    expect(after.misattributed, isEmpty, reason: misattributed(after));
    expect(after.correctHits, chart.notes.length);
  });

  group('correct chord', () {
    test('1. on time: every strum of Am C G scores, each by its own stroke', () {
      final a = play(amCG, _player());
      expectJudgedOnce(a);
      expect(a.correctHits, amCG.notes.length, reason: misattributed(a));
      expect(a.misattributed, isEmpty, reason: misattributed(a));
      expect(maxAbs(a.timingErrors), lessThan(60));
    });

    test('2. slightly early (−50 ms): scored, and shown as early', () {
      final a = play(amCG, _player(biasMs: -50));
      expectJudgedOnce(a);
      expect(a.correctHits, greaterThanOrEqualTo(amCG.notes.length - 1), reason: misattributed(a));
      expect(a.misattributed, isEmpty, reason: misattributed(a));
      expect(medianOffset(a), inInclusiveRange(-90, -15));
    });

    test('3. slightly late (+50 ms): scored, and shown as late', () {
      final a = play(amCG, _player(biasMs: 50));
      expectJudgedOnce(a);
      expect(a.correctHits, greaterThanOrEqualTo(amCG.notes.length - 1), reason: misattributed(a));
      expect(a.misattributed, isEmpty, reason: misattributed(a));
      expect(medianOffset(a), inInclusiveRange(15, 90));
    });

    test('4. far too late (+280 ms, outside the window): never scored, not even for the next note', () {
      final a = play(amCG, _player(biasMs: 280));
      expectJudgedOnce(a);
      expect(a.scoredHits, 0, reason: misattributed(a));
    });
  });

  group('nothing correct is played', () {
    double scoredWrong(String caseId, RhythmChart chart, {int seed = 2}) {
      final dry = fpCases.firstWhere((c) => c.id == caseId).build(chart, catalog, seed);
      final r = replayGame(
        audio: applyPhoneMic(dry, _phone, seed: seed),
        chart: chart,
        catalog: catalog,
        chartStartMs: fpChartStartSec * 1000,
        calibrationMs: _phone.latencyMs + 15,
      );
      final wrong = caseId.startsWith('idle')
          ? {for (final n in chart.notes) if (n.timeMs > 200) n.index}
          : trulyWrongNotes(caseId, chart, catalog, seed);
      var scored = 0;
      for (final i in wrong) {
        final res = r.judge.results[i];
        if (res != null && res.judgement.name != 'miss') scored++;
      }
      return wrong.isEmpty ? 0 : scored / wrong.length;
    }

    test('5. wrong chord at the right time', () {
      expect(scoredWrong('wrong-chord', amCG), lessThan(0.1));
    });

    test('6. one strum, then the chord only rings: the later strums do not score', () {
      expect(scoredWrong('idle-ringing', amCG), 0);
      expect(scoredWrong('idle-ringing', _chart('↓ - ↓ ↑ - ↑ ↓ ↑', ['g_major', 'c_major'], subdivision: 2)), 0);
    });

    test('7. silence', () {
      expect(scoredWrong('idle-quiet', amCG), 0);
    });

    test('8. noise and knocks without a guitar', () {
      expect(scoredWrong('idle-noisy-room', amCG), 0);
      expect(scoredWrong('idle-knocks', amCG), 0);
    });
  });

  test('9. one strum between two scheduled strokes counts for one of them at most', () {
    // Target: ↓ every 300 ms. Played: only every other one, 150 ms late —
    // each real strum is exactly between two notes.
    final target = _chart('↓ ↓', ['g_major', 'g_major'], bpm: 100, beatsPerBar: 2, subdivision: 2);
    final sparse = _chart('↓ -', ['g_major', 'g_major'], bpm: 100, beatsPerBar: 2, subdivision: 2);
    final perf = perform(chart: sparse, catalog: catalog, player: _player(biasMs: 150), seed: 5);
    final r = replayGame(
      audio: applyPhoneMic(perf.dry, _phone, seed: 5),
      chart: target,
      catalog: catalog,
      chartStartMs: 1000,
      calibrationMs: _phone.latencyMs + 15,
    );
    final strokes = sparse.notes.length;
    final hits = r.decisions.where((d) => d.outcome == CaptureOutcome.hit).toList();
    expect(hits.length, lessThanOrEqualTo(strokes));
    // No real strum scored two notes: hits are at least ~a stroke apart.
    for (var i = 1; i < hits.length; i++) {
      expect(hits[i].timeMs - hits[i - 1].timeMs, greaterThan(400),
          reason: '${hits[i - 1].toLogLine()}\n${hits[i].toLogLine()}');
    }
  });

  test('10. four strums on one chord: four separate judgements', () {
    final chart = _chart('↓ ↓ ↓ ↓', ['g_major']);
    final a = play(chart, _player());
    expectJudgedOnce(a);
    expect(a.correctHits, 4, reason: misattributed(a));
  });

  test('11. four strums, then four on another chord', () {
    final chart = _chart('↓ ↓ ↓ ↓', ['c_major', 'g_major']);
    final a = play(chart, _player(seed: 2), seed: 6);
    expectJudgedOnce(a);
    expect(a.correctHits, 8, reason: misattributed(a));
    expect(a.run.judge.wrongNotes, 0);
  });

  test('12. chord changes with the old chord\'s open strings still ringing', () {
    // C → Am → G → D: open strings of each chord keep ringing into the next
    // (the simulated player only stops the fretted ones).
    final chart = _chart('↓ ↓ ↓ ↓', ['c_major', 'a_minor', 'g_major', 'd_major']);
    final a = play(chart, _player(seed: 4), seed: 8);
    expectJudgedOnce(a);
    expect(a.correctHits, greaterThanOrEqualTo(chart.notes.length - 1), reason: misattributed(a));
    expect(a.misattributed, isEmpty, reason: misattributed(a));
  });

  test('13. mic latency from 80 to 320 ms, calibration off by ±30 ms', () {
    for (final (latency, calError) in [(80.0, -30.0), (200.0, 30.0), (320.0, 0.0)]) {
      final mic = PhoneMic(
        latencyMs: latency,
        highPassHz: _phone.highPassHz,
        eq: _phone.eq,
        roomRt60: _phone.roomRt60,
        roomMix: _phone.roomMix,
        noiseLevel: _phone.noiseLevel,
        gain: _phone.gain,
      );
      final a = play(amCG, _player(), mic: mic, calErrorMs: calError);
      expectJudgedOnce(a);
      expect(a.correctHits, greaterThanOrEqualTo(amCG.notes.length - 1),
          reason: 'latency $latency, error $calError\n${misattributed(a)}');
      expect(a.misattributed, isEmpty, reason: misattributed(a));
    }
  });

  group('delivery of the audio does not change any judgement', () {
    Map<int, (String, double?)> results(AuditResult a) => {
          for (final e in a.run.judge.results.entries)
            e.key: (e.value.judgement.name, e.value.offsetMs),
        };
    final chart = _chart('↓ - ↓ ↑ - ↑ ↓ ↑', ['c_major', 'g_major'], subdivision: 2);
    late final Map<int, (String, double?)> reference;
    setUpAll(() => reference = results(play(chart, _player(seed: 5), seed: 9)));

    test('14. extra processing delay (busy UI thread) of 60 / 120 ms', () {
      for (final delay in [60.0, 120.0]) {
        expect(results(play(chart, _player(seed: 5), seed: 9, processingDelayMs: delay)), reference,
            reason: 'delay $delay ms');
      }
    });

    test('15. audio in irregular batches (10 ms … 190 ms chunks)', () {
      final rng = Random(7);
      expect(results(play(chart, _player(seed: 5), seed: 9, chunkOf: (_) => 441 + rng.nextInt(8000))),
          reference);
      expect(results(play(chart, _player(seed: 5), seed: 9, chunkOf: (_) => 8192)), reference);
    });

    test('17. every capture delivered twice', () {
      final a = play(chart, _player(seed: 5), seed: 9, deliverTwice: true);
      expectJudgedOnce(a);
      expect(results(a), reference);
    });
  });

  test('16. restarting: a reset engine behaves exactly like a new one', () {
    final perf = perform(chart: amCG, catalog: catalog, player: _player(), seed: 3);
    final audio = applyPhoneMic(perf.dry, _phone, seed: 3);
    List<(int, int?)> run(ChordDetectionEngine engine) {
      final out = <(int, int?)>[];
      for (var s = 0; s < audio.length; s += 1764) {
        engine.addSamples(Float32List.sublistView(audio, s, min(audio.length, s + 1764)));
        out.addAll(engine.takeCaptures().map((c) => (c.onsetSample, c.nextOnsetSample)));
      }
      return out;
    }

    ChordDetectionEngine fresh() => ChordDetectionEngine(
          onsetDetector: OnsetDetector.forRhythmGame(),
          strumClusterMs: 90,
        )..setTarget(catalog.chordById('a_minor')!);
    final reused = fresh();
    run(reused); // a first round
    reused.reset();
    expect(run(reused), run(fresh()));
  });

  test('18. soft up-strums and normal down-strums', () {
    final chart = _chart('↓ - ↓ ↑ - ↑ ↓ ↑', ['c_major', 'g_major', 'a_minor'], subdivision: 2);
    for (final soft in [false, true]) {
      final a = play(chart, _player(soft: soft, seed: 6), seed: 10);
      expectJudgedOnce(a);
      expect(a.misattributed, isEmpty, reason: 'soft=$soft\n${misattributed(a)}');
      final downs = [for (final n in chart.notes) if (n.isDown) n.index];
      final downsHit = downs.where((i) => a.hits.any((c) => c.stroke == i && c.decision.note!.index == i));
      expect(downsHit.length, greaterThanOrEqualTo(downs.length - 1), reason: 'soft=$soft');
      // Soft ↑ strums: at least most count (the phone simulation loses ~20 %).
      final ups = [for (final n in chart.notes) if (n.isUp) n.index];
      final upsHit = ups.where((i) => a.hits.any((c) => c.stroke == i && c.decision.note!.index == i));
      expect(upsHit.length, greaterThanOrEqualTo((ups.length * 0.5).ceil()), reason: 'soft=$soft');
    }
  });
}
