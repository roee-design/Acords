// Rhythm-game stroke verification: does the right chord count, and does
// strumming / picking random open strings without a chord get rejected?
// Run: flutter test test/bench/stroke_verify_bench_test.dart --run-skipped
@Tags(['bench'])
library;

import 'package:chord_trainer/models/chord_definition.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/catalog_loader.dart';
import '../support/guitar_synth.dart';
import '../support/stroke_scenarios.dart';

void main() {
  final catalog = loadChordCatalog();
  const mics = [
    MicConditions(highPassHz: 120, noiseLevel: 0.001),
    MicConditions(highPassHz: 220, noiseLevel: 0.004, gain: 0.5),
  ];
  final chords = [
    for (final id in ['c_major', 'g_major', 'd_major', 'a_minor', 'e_minor', 'f_major', 'a_major', 'e_major', 'd_minor', 'b_minor'])
      catalog.chordById(id)!,
  ];

  void report(String name, List<bool> results, {required bool expectAccept}) {
    final accepted = results.where((r) => r).length;
    final pct = 100 * accepted / results.length;
    // ignore: avoid_print
    print('${name.padRight(34)} accepted ${pct.toStringAsFixed(1)}% ($accepted/${results.length})'
        '  → ${expectAccept ? 'should be high' : 'should be ~0'}');
  }

  test('stroke verification', () {
    final out = <String, List<bool>>{};
    for (final mic in mics) {
      for (var seed = 1; seed <= 2; seed++) {
        for (final chord in chords) {
          final synth = GuitarSynth(seed: seed * 97 + chords.indexOf(chord));
          ChordDefinition c = chord;
          for (final (name, random, soft) in [
            ('strum: correct chord', false, false),
            ('strum: correct chord, soft', false, true),
            ('strum: random open strings 5-2', true, false),
          ]) {
            final (audio, strokes) = strumBars(synth, c, randomOpen: random, mic: mic, soft: soft);
            out.putIfAbsent(name, () => []).addAll(runStrokes(audio, strokes, c));
          }
          for (final (name, random) in [
            ('arpeggio: correct notes', false),
            ('arpeggio: random open strings', true),
          ]) {
            final (audio, strokes) = arpeggioBar(synth, c, randomOpen: random, mic: mic);
            final r = runStrokes(audio, strokes, c);
            for (var i = 0; i < r.length; i++) {
              // Random plucks that hit the right note by chance are correct.
              if (random && strokes[i].rightNote) continue;
              out.putIfAbsent(name, () => []).add(r[i]);
            }
          }
        }
      }
    }
    for (final e in out.entries) {
      report(e.key, e.value, expectAccept: !e.key.contains('random'));
    }
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('doing nothing: ringing chord / room noise', () {
    var ringCaps = 0, ringAcc = 0, noiseCaps = 0, noiseAcc = 0;
    var seconds = 0.0;
    for (final mic in mics) {
      for (final chord in chords) {
        final synth = GuitarSynth(seed: 11 + chords.indexOf(chord));
        // One strum, then 5 s of the chord ringing out.
        final ring = synth.render(synth.strum(chord, startSec: 0.3), durationSec: 5.3, mic: mic);
        final (c1, a1) = idleAccepts(ring, chord);
        ringCaps += c1;
        ringAcc += a1;
        // Room noise with soft knocks (non-tonal transients), no guitar.
        final noise = synth.render([], durationSec: 5, mic: MicConditions(highPassHz: mic.highPassHz, noiseLevel: mic.noiseLevel * 3, gain: mic.gain));
        for (var k = 1; k < 5; k++) {
          final at = (k * 44100).round();
          for (var i = 0; i < 300; i++) {
            noise[at + i] += 0.05 * (synth.rand() * 2 - 1) * (1 - i / 300);
          }
        }
        final (c2, a2) = idleAccepts(noise, chord, fromSec: 0);
        noiseCaps += c2;
        noiseAcc += a2;
        seconds += 5;
      }
    }
    // ignore: avoid_print
    print('IDLE ringing chord: $ringCaps strum detections, $ringAcc accepted '
        '(${(60 * ringAcc / seconds).toStringAsFixed(1)} false hits/min)');
    // ignore: avoid_print
    print('IDLE room noise+knocks: $noiseCaps strum detections, $noiseAcc accepted');
    // ignore: avoid_print
    print('IDLE accepted by stroke kind (finger = any of 4 strings): $idleByKind over ${seconds.round()} s');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
