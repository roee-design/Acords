// Frame-level matcher bench on synthetic strums (legacy baseline numbers are
// recorded in HANDOFF.md). Run: flutter test test/bench/matcher_bench_test.dart
@Tags(['bench'])
library;

import 'dart:typed_data';

import 'package:chord_trainer/audio/fft_processor.dart';
import 'package:chord_trainer/audio/frequency_utils.dart';
import 'package:chord_trainer/chord/chord_matcher.dart';
import 'package:chord_trainer/models/chord_definition.dart';
import 'package:chord_trainer/models/feedback_result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/catalog_loader.dart';
import '../support/guitar_synth.dart';
import '../support/legacy_chord_matcher.dart';

typedef Eval = ChordMatchStatus Function(
    ChordDefinition target, List<double> mags, double level);

const sr = 44100;
const fft = 8192;
final proc = FftProcessor(fftSize: fft, sampleRate: sr.toDouble());

List<(List<double>, double)> framesOf(Float32List audio) {
  final frames = <(List<double>, double)>[];
  for (var end = fft; end <= audio.length; end += (0.08 * sr).round()) {
    final frame = Float32List.sublistView(audio, end - fft, end);
    frames.add((proc.computeMagnitudes(frame), frameRms(frame)));
  }
  return frames;
}

bool hits(Eval m, ChordDefinition target,
    List<(List<double>, double)> frames) {
  var run = 0;
  for (final f in frames) {
    run = m(target, f.$1, f.$2) == ChordMatchStatus.perfect ? run + 1 : 0;
    if (run >= 2) return true;
  }
  return false;
}

bool sameSound(ChordDefinition a, ChordDefinition b) {
  Set<int> pcs(ChordDefinition c) => c.notes.map((n) => n.midi % 12).toSet();
  final x = pcs(a), y = pcs(b);
  return x.length == y.length && x.containsAll(y);
}

const conditions = [
  MicConditions(highPassHz: 80, noiseLevel: 0.001),
  MicConditions(highPassHz: 150, noiseLevel: 0.003),
  MicConditions(highPassHz: 220, noiseLevel: 0.004, gain: 0.5),
];

void main() {
  final catalog = loadChordCatalog();
  final chords = catalog.chords;
  final newM = ChordMatcher(fftProcessor: proc);
  final legacyM = LegacyChordMatcher(fftProcessor: proc);
  final engines = <String, Eval>{
    'legacy': (t, m, l) => legacyM.evaluate(chord: t, magnitudes: m, referenceA4Hz: 440, inputLevel: l).matchStatus,
    'new': (t, m, l) => newM.evaluate(chord: t, magnitudes: m, referenceA4Hz: 440, inputLevel: l).matchStatus,
  };
  for (final engine in engines.entries) {
  final matcher = engine.value;
  final name = engine.key;

  test('[$name] accept / wrong-chord rejection', () {
    var accepts = 0, trials = 0, fa = 0, faTrials = 0;
    final miss = <String, int>{};
    final faPairs = <String, int>{};
    for (final mic in conditions) {
      for (var seed = 1; seed <= 3; seed++) {
        for (final played in chords) {
          final synth = GuitarSynth(seed: seed * 100 + chords.indexOf(played));
          final frames = framesOf(synth.render(
              synth.strum(played, startSec: 0.2), durationSec: 1.6, mic: mic));
          for (final target in chords) {
            final h = hits(matcher, target, frames);
            if (target.id != played.id && sameSound(target, played)) continue;
            if (target.id == played.id) {
              trials++;
              if (h) { accepts++; } else { miss['${played.id} $mic'] = (miss['${played.id} $mic'] ?? 0) + 1; }
            } else {
              faTrials++;
              if (h) { fa++; final k = '${target.id}<-${played.id}'; faPairs[k] = (faPairs[k] ?? 0) + 1; }
            }
          }
        }
      }
    }
    final top = faPairs.entries.toList()..sort((a, b) => b.value - a.value);
    // ignore: avoid_print
    print('[$name] ACCEPT ${(100 * accepts / trials).toStringAsFixed(1)}% ($accepts/$trials)\n'
        'FALSE ACCEPT ${(100 * fa / faTrials).toStringAsFixed(2)}% ($fa/$faTrials)\n'
        'misses: $miss\ntop FA: ${top.take(12).map((e) => '${e.key} x${e.value}').join(', ')}');
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('[$name] missing string / ringing muted string must not be perfect', () {
    var missingTrials = 0, missingWrongPerfect = 0;
    var mutedTrials = 0, mutedWrongPerfect = 0;
    final missDetail = <String, int>{};
    final mutedDetail = <String, int>{};
    for (final mic in conditions) {
      for (var seed = 1; seed <= 2; seed++) {
        for (final chord in chords) {
          final synth = GuitarSynth(seed: 7000 + seed * 100 + chords.indexOf(chord));
          for (final note in chord.notes) {
            final frames = framesOf(synth.render(
                synth.strum(chord, startSec: 0.2, skipStrings: {note.string}),
                durationSec: 1.4, mic: mic));
            missingTrials++;
            if (hits(matcher, chord, frames)) {
              missingWrongPerfect++;
              final k = '${chord.id}/s${note.string}';
              missDetail[k] = (missDetail[k] ?? 0) + 1;
            }
          }
          // Muted strings that ring open.
          for (var s = 6; s >= 1; s--) {
            if (!chord.isStringMuted(s)) continue;
            final events = synth.strum(chord, startSec: 0.2)
              ..add(synth.pluck(s, startSec: 0.21, level: 0.15));
            final frames = framesOf(synth.render(events, durationSec: 1.4, mic: mic));
            mutedTrials++;
            if (hits(matcher, chord, frames)) { mutedWrongPerfect++; mutedDetail['${chord.id}/s$s'] = (mutedDetail['${chord.id}/s$s'] ?? 0) + 1; }
          }
        }
      }
    }
    // ignore: avoid_print
    print('[$name] MISSING-STRING still perfect: ${(100 * missingWrongPerfect / missingTrials).toStringAsFixed(1)}% ($missingWrongPerfect/$missingTrials)\n'
        'MUTED-STRING-RINGING still perfect: ${(100 * mutedWrongPerfect / mutedTrials).toStringAsFixed(1)}% ($mutedWrongPerfect/$mutedTrials)\n'
        'muted detail: $mutedDetail');
  }, timeout: const Timeout(Duration(minutes: 10)));
  }
}
