// Fast regression checks for the detection pipeline on synthetic guitar audio.
// The full comparisons (legacy vs new, many conditions) live in test/bench/.
import 'dart:typed_data';

import 'package:chord_trainer/audio/chord_detection_engine.dart';
import 'package:chord_trainer/audio/pitch_tuner.dart';
import 'package:chord_trainer/models/chord_definition.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/catalog_loader.dart';
import 'support/guitar_synth.dart';

const _mic = MicConditions(highPassHz: 150, noiseLevel: 0.002);

List<ChordHit> _hits(ChordDetectionEngine engine, Float32List audio,
    {void Function(ChordHit hit)? onHit}) {
  final out = <ChordHit>[];
  for (var s = 0; s < audio.length; s += 1764) {
    final e = s + 1764 > audio.length ? audio.length : s + 1764;
    for (final f in engine.addSamples(Float32List.sublistView(audio, s, e))) {
      if (f.hit != null) {
        out.add(f.hit!);
        onHit?.call(f.hit!);
      }
    }
  }
  return out;
}

void main() {
  final catalog = loadChordCatalog();
  ChordDefinition c(String id) => catalog.chordById(id)!;

  test('every level-1 chord is confirmed after a strum', () {
    for (final chord in catalog.chordsForDifficulty(1)) {
      final synth = GuitarSynth(seed: chord.id.hashCode);
      final audio = synth.render(synth.strum(chord, startSec: 0.3),
          durationSec: 1.5, mic: _mic);
      final hits = _hits(ChordDetectionEngine()..setTarget(chord), audio);
      expect(hits, hasLength(1), reason: chord.id);
      expect(hits.single.latencyMs, lessThan(450), reason: chord.id);
    }
  });

  test('a chord that contains the target is not accepted', () {
    for (final (target, played) in [
      ('g_major', 'g_7'),
      ('a_5', 'a_major'),
      ('e_5', 'e_minor'),
      ('a_major', 'a_minor'),
      ('c_major', 'a_minor7'),
    ]) {
      final synth = GuitarSynth(seed: 5);
      final audio = synth.render(synth.strum(c(played), startSec: 0.3),
          durationSec: 1.5, mic: _mic);
      expect(_hits(ChordDetectionEngine()..setTarget(c(target)), audio),
          isEmpty,
          reason: '$played must not count as $target');
    }
  });

  test('no strum, no hit: a ringing chord does not confirm the next target',
      () {
    final synth = GuitarSynth(seed: 9);
    final audio = synth.render(synth.strum(c('c_major'), startSec: 0.3),
        durationSec: 2.5, mic: _mic);
    final engine = ChordDetectionEngine()..setTarget(c('c_major'));
    var hits = 0;
    _hits(engine, audio, onHit: (_) {
      hits++;
      // Same chord again (e.g. two consecutive song segments): needs a new
      // strum, the ringing one must not count twice.
      engine.setTarget(c('c_major'));
    });
    expect(hits, 1);
  });

  test('chord changes follow a strummed progression in order', () {
    final progression = ['g_major', 'c_major', 'd_major', 'e_minor'];
    final synth = GuitarSynth(seed: 3);
    final events = <StringEvent>[];
    for (var i = 0; i < progression.length; i++) {
      events.addAll(synth.strum(c(progression[i]),
          startSec: 0.3 + i * 1.0, stopSec: 0.3 + (i + 1) * 1.0 - 0.04));
    }
    final audio = synth.render(events, durationSec: 4.6, mic: _mic);
    final engine = ChordDetectionEngine()..setTarget(c(progression.first));
    var index = 0;
    final hitTimes = <double>[];
    _hits(engine, audio, onHit: (hit) {
      hitTimes.add(hit.confirmSample / 44100);
      index++;
      if (index < progression.length) engine.setTarget(c(progression[index]));
    });
    expect(index, progression.length);
    for (var i = 0; i < hitTimes.length; i++) {
      final strum = 0.3 + i * 1.0;
      expect(hitTimes[i], greaterThan(strum), reason: 'chord $i before strum');
      expect(hitTimes[i], lessThan(strum + 0.6), reason: 'chord $i too slow');
    }
  });

  test('tuner reads a weak-fundamental low E within 3 cents', () {
    const openStrings = <(int, int, String)>[
      (6, 40, 'low E'), (5, 45, 'A'), (4, 50, 'D'),
      (3, 55, 'G'), (2, 59, 'B'), (1, 64, 'high E'),
    ];
    for (final detune in [-30.0, -7.0, 0.0, 12.0]) {
      final synth = GuitarSynth(seed: 11);
      final audio = synth.render([synth.pluck(6, detuneCents: detune)],
          durationSec: 0.6,
          mic: const MicConditions(highPassHz: 300, noiseLevel: 0.002));
      final frame = Float32List.sublistView(audio, audio.length - 8192);
      final reading = (TunerPitchEstimator()..openStrings = openStrings)
          .estimate(frame, 0.1);
      expect(reading.closestStringNumber, 6, reason: 'detune $detune');
      expect(reading.centsOffset!, closeTo(detune, 3), reason: 'detune $detune');
    }
  });
}
