// Strum onset bench. Run: flutter test test/bench/onset_bench_test.dart
@Tags(['bench'])
library;

import 'dart:typed_data';

import 'package:chord_trainer/audio/onset_detector.dart';
import 'package:chord_trainer/models/chord_definition.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/catalog_loader.dart';
import '../support/guitar_synth.dart';
import '../support/legacy_onset.dart';

List<int> runChunks(dynamic det, Float32List audio) {
  final out = <int>[];
  const chunk = 1764; // ~40 ms, typical recorder callback
  for (var s = 0; s < audio.length; s += chunk) {
    final e = s + chunk > audio.length ? audio.length : s + chunk;
    out.addAll(
      det.process(Float32List.sublistView(audio, s, e), s) as List<int>,
    );
  }
  return out;
}

class Scenario {
  Scenario(this.name, this.audio, this.truthSec);
  final String name;
  final Float32List audio;
  final List<double> truthSec;
}

List<Scenario> onsetScenarios(
  ChordCatalog catalog,
  int seed,
  MicConditions mic,
) {
  ChordDefinition c(String id) => catalog.chordById(id)!;
  final out = <Scenario>[];
  // 1. Song-like strumming: ↓ - ↓ ↑ - ↑ ↓ ↑ at 90 BPM, chord change per bar.
  {
    final synth = GuitarSynth(seed: seed);
    final prog = [c('c_major'), c('g_major'), c('a_minor'), c('f_major')];
    final events = <StringEvent>[];
    final truth = <double>[];
    const eighth = 60 / 90 / 2;
    const slots = [0, 2, 3, 5, 6, 7];
    for (var bar = 0; bar < 4; bar++) {
      final chord = prog[bar];
      final barStart = 0.3 + bar * 8 * eighth;
      final barEnd = barStart + 8 * eighth;
      for (final slot in slots) {
        final t = barStart + slot * eighth;
        final down = slot.isEven;
        truth.add(t);
        events.addAll(
          synth.strum(
            chord,
            startSec: t,
            stopSec: slot == 7 ? barEnd - 0.02 : t + eighth * 2.2,
            down: down,
            level: down ? 0.22 : 0.12,
            onlyStrings: down ? null : {1, 2, 3, 4},
          ),
        );
      }
    }
    out.add(
      Scenario(
        'strumming',
        synth.render(events, durationSec: 0.3 + 32 * eighth + 0.5, mic: mic),
        truth,
      ),
    );
  }
  // 2. Legato fret change on ringing strings (no pick attack): one onset.
  {
    final synth = GuitarSynth(seed: seed + 1);
    final events = [
      ...synth.strum(c('a_minor'), startSec: 0.3, stopSec: 1.3),
      ...synth.strum(c('c_major'), startSec: 1.3, level: 0.08, legato: true),
    ];
    out.add(
      Scenario(
        'legato change',
        synth.render(events, durationSec: 2.6, mic: mic),
        [0.3],
      ),
    );
  }
  // 3. Same chord re-strummed at equal loudness while still ringing.
  {
    final synth = GuitarSynth(seed: seed + 2);
    final events = <StringEvent>[];
    final truth = <double>[];
    for (var k = 0; k < 6; k++) {
      final t = 0.3 + k * 0.42;
      truth.add(t);
      events.addAll(synth.strum(c('g_major'), startSec: t, level: 0.2));
    }
    out.add(
      Scenario(
        're-strum ringing',
        synth.render(events, durationSec: 3.2, mic: mic),
        truth,
      ),
    );
  }
  // 4. One strum, long decay.
  {
    final synth = GuitarSynth(seed: seed + 3);
    out.add(
      Scenario(
        'single decay',
        synth.render(
          synth.strum(c('e_major'), startSec: 0.3),
          durationSec: 4,
          mic: mic,
        ),
        [0.3],
      ),
    );
  }
  // 5. Room noise only.
  {
    final synth = GuitarSynth(seed: seed + 4);
    out.add(
      Scenario(
        'silence',
        synth.render(const [], durationSec: 3, mic: mic),
        [],
      ),
    );
  }
  return out;
}

const onsetMics = [
  MicConditions(highPassHz: 100, noiseLevel: 0.001),
  MicConditions(highPassHz: 200, noiseLevel: 0.004, gain: 0.6),
];

void main() {
  final catalog = loadChordCatalog();
  final detectors = <String, dynamic Function()>{
    'legacy': () => LegacyOnsetDetector(),
    'new': () => OnsetDetector(),
  };

  for (final d in detectors.entries) {
    test('[${d.key}] onset accuracy', () {
      final stats = <String, List<int>>{}; // hit, missed, false
      for (final mic in onsetMics) {
        for (var seed = 1; seed <= 4; seed++) {
          for (final sc in onsetScenarios(catalog, seed * 10, mic)) {
            final found =
                runChunks(d.value(), sc.audio).map((s) => s / 44100).toList();
            final used = <int>{};
            var tp = 0;
            for (final t in sc.truthSec) {
              for (var i = 0; i < found.length; i++) {
                final dt = found[i] - t;
                if (!used.contains(i) && dt > -0.03 && dt < 0.06) {
                  used.add(i);
                  tp++;
                  break;
                }
              }
            }
            final s = stats.putIfAbsent(sc.name, () => [0, 0, 0]);
            s[0] += tp;
            s[1] += sc.truthSec.length - tp;
            s[2] += found.length - used.length;
          }
        }
      }
      for (final e in stats.entries) {
        // ignore: avoid_print
        print(
          '[${d.key}] ${e.key.padRight(18)} hit=${e.value[0]} '
          'missed=${e.value[1]} false=${e.value[2]}',
        );
      }
    }, timeout: const Timeout(Duration(minutes: 5)));
  }
}
