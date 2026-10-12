// Robustness of the full engine (strum → hit) under harder conditions.
// Run: flutter test test/bench/robustness_bench_test.dart
@Tags(['bench'])
library;

import 'dart:typed_data';

import 'package:chord_trainer/audio/chord_detection_engine.dart';
import 'package:chord_trainer/models/chord_definition.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/catalog_loader.dart';
import '../support/guitar_synth.dart';

bool engineHits(ChordDefinition target, Float32List audio) {
  final engine = ChordDetectionEngine()..setTarget(target);
  for (var s = 0; s < audio.length; s += 1764) {
    final e = s + 1764 > audio.length ? audio.length : s + 1764;
    for (final f in engine.addSamples(Float32List.sublistView(audio, s, e))) {
      if (f.hit != null) return true;
    }
  }
  return false;
}

void main() {
  final catalog = loadChordCatalog();
  final chords = catalog.chords;

  void scenario(String name, bool expectHit, List<StringEvent> Function(GuitarSynth, ChordDefinition) events, MicConditions mic) {
    var ok = 0, n = 0;
    final bad = <String>[];
    for (var seed = 1; seed <= 2; seed++) {
      for (final c in chords) {
        final synth = GuitarSynth(seed: seed * 1000 + chords.indexOf(c));
        final hit = engineHits(c, synth.render(events(synth, c), durationSec: 1.8, mic: mic));
        n++;
        if (hit == expectHit) { ok++; } else { bad.add(c.id); }
      }
    }
    // ignore: avoid_print
    print('${name.padRight(34)} correct ${(100 * ok / n).toStringAsFixed(0)}% ($ok/$n) ${bad.isEmpty ? '' : bad.toSet()}');
  }

  test('free play identification', () {
    final pool = catalog.chords;
    var ok = 0, n = 0;
    final wrong = <String, int>{};
    for (final mic in const [
      MicConditions(highPassHz: 120, noiseLevel: 0.001),
      MicConditions(highPassHz: 220, noiseLevel: 0.004, gain: 0.5),
    ]) {
      for (var seed = 1; seed <= 2; seed++) {
        for (final played in chords) {
          final synth = GuitarSynth(seed: seed * 4000 + chords.indexOf(played));
          final audio = synth.render(synth.strum(played, startSec: 0.3), durationSec: 1.6, mic: mic);
          final engine = ChordDetectionEngine()..setFreePlay(pool);
          String? got;
          for (final f in engine.addSamples(audio)) {
            if (f.hit != null) { got = f.hit!.chordId; break; }
          }
          n++;
          final gotChord = got == null ? null : catalog.chordById(got);
          Set<int> pcs(ChordDefinition c) => c.notes.map((x) => x.midi % 12).toSet();
          if (gotChord != null && pcs(gotChord).length == pcs(played).length && pcs(gotChord).containsAll(pcs(played))) {
            ok++;
          } else {
            final k = '${played.id}->${got ?? 'none'}';
            wrong[k] = (wrong[k] ?? 0) + 1;
          }
        }
      }
    }
    // ignore: avoid_print
    print('FREE PLAY identified ${(100 * ok / n).toStringAsFixed(1)}% ($ok/$n) wrong: $wrong');
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('robustness', () {
    const normal = MicConditions(highPassHz: 150, noiseLevel: 0.002);
    scenario('baseline', true, (s, c) => s.strum(c, startSec: 0.3), normal);
    scenario('whole guitar +20 cents', true, (s, c) => [for (final e in s.strum(c, startSec: 0.3)) StringEvent(midi: e.midi, startSec: e.startSec, amplitude: e.amplitude, detuneCents: e.detuneCents + 20, pluckPosition: e.pluckPosition, stringNumber: e.stringNumber)], normal);
    scenario('sloppy tuning (sd 10 cents)', true, (s, c) => s.strum(c, startSec: 0.3, tuningSpreadCents: 10), normal);
    scenario('noisy room (noise 0.01)', true, (s, c) => s.strum(c, startSec: 0.3), const MicConditions(highPassHz: 150, noiseLevel: 0.01));
    scenario('very quiet / far (gain 0.15)', true, (s, c) => s.strum(c, startSec: 0.3), const MicConditions(highPassHz: 200, noiseLevel: 0.002, gain: 0.15));
    // Detune a note whose pitch class occurs once in the chord and is not an
    // overtone of a lower chord note (typically the third) — the string a
    // player can actually be told about.
    int? diagnosticString(ChordDefinition c) {
      for (final n in c.notes) {
        final same = c.notes.where((m) => m.midi % 12 == n.midi % 12).length;
        final overtone = c.notes.any((m) => m.midi < n.midi && const [12, 19, 24, 28].contains(n.midi - m.midi));
        if (same == 1 && !overtone) return n.string;
      }
      return null;
    }
    for (final cents in [35, 50]) {
      var ok = 0, n = 0;
      final bad = <String>[];
      for (var seed = 1; seed <= 2; seed++) {
        for (final c in chords) {
          final target = diagnosticString(c);
          if (target == null) continue;
          final synth = GuitarSynth(seed: seed * 1000 + chords.indexOf(c));
          final ev = [
            for (final e in synth.strum(c, startSec: 0.3, tuningSpreadCents: 3))
              e.stringNumber == target
                  ? StringEvent(midi: e.midi, startSec: e.startSec, amplitude: e.amplitude, detuneCents: cents.toDouble(), pluckPosition: e.pluckPosition, stringNumber: e.stringNumber)
                  : e,
          ];
          n++;
          if (!engineHits(c, synth.render(ev, durationSec: 1.8, mic: normal))) { ok++; } else { bad.add('${c.id}/s$target'); }
        }
      }
      // ignore: avoid_print
      print('${'unique note $cents cents off -> reject'.padRight(34)} correct ${(100 * ok / n).toStringAsFixed(0)}% ($ok/$n) ${bad.toSet()}');
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
