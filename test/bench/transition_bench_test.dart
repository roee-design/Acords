// Chord-change (transition) bench: a player strums a progression and the
// target advances on every hit, like the song / strumming screens.
// Run: flutter test test/bench/transition_bench_test.dart
@Tags(['bench'])
library;

import 'dart:typed_data';

import 'package:chord_trainer/audio/chord_detection_engine.dart';
import 'package:chord_trainer/audio/fft_processor.dart';
import 'package:chord_trainer/audio/frequency_utils.dart';
import 'package:chord_trainer/models/chord_definition.dart';
import 'package:chord_trainer/models/feedback_result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/catalog_loader.dart';
import '../support/guitar_synth.dart';
import '../support/legacy_chord_matcher.dart';

const sr = 44100;

class Performance {
  Performance(this.audio, this.strums);
  final Float32List audio;

  /// (chordId, strum time sec) in play order.
  final List<(String, double)> strums;
}

/// Each chord strummed once, [gap] apart; fretted strings of the previous
/// chord are released 40 ms before the next strum (open strings ring on).
Performance progression(
  GuitarSynth synth,
  List<ChordDefinition> chords, {
  double gap = 1.1,
  MicConditions mic = const MicConditions(),
}) {
  final events = <StringEvent>[];
  final strums = <(String, double)>[];
  var t = 0.4;
  for (var i = 0; i < chords.length; i++) {
    final strum = synth.strum(chords[i], startSec: t);
    events.addAll(strum);
    strums.add((chords[i].id, t));
    t += gap;
  }
  // Physical string model: a ringing string stops when it is plucked again,
  // when the next chord changes its fret (fingers move 40 ms before the
  // strum), or when the next chord mutes it and it was fretted (lifting the
  // finger damps it). An open string the next chord does not use rings on.
  for (var i = 0; i < events.length; i++) {
    final e = events[i];
    final ci = strums.lastIndexWhere((s) => s.$2 <= e.startSec + 1e-9);
    if (ci + 1 >= chords.length) continue;
    final next = chords[ci + 1];
    final nextT = strums[ci + 1].$2;
    final cur = chords[ci].noteForString(e.stringNumber!)!;
    final nextNote = next.isStringMuted(e.stringNumber!) ? null : next.noteForString(e.stringNumber!);
    double? stop;
    if (nextNote != null) {
      stop = nextNote.fret != cur.fret ? nextT - 0.04 : nextT;
    } else if (cur.fret > 0) {
      stop = nextT - 0.04;
    }
    if (stop != null) events[i] = e.copyWith(stopSec: stop);
  }
  return Performance(synth.render(events, durationSec: t + 0.6, mic: mic), strums);
}

/// Strumming pattern ↓ - ↓ ↑ - ↑ ↓ ↑, one chord per bar.
Performance strummedBars(
  GuitarSynth synth,
  List<ChordDefinition> chords, {
  int bpm = 90,
  MicConditions mic = const MicConditions(),
}) {
  final eighth = 60 / bpm / 2;
  const slots = [0, 2, 3, 5, 6, 7];
  final events = <StringEvent>[];
  final strums = <(String, double)>[];
  for (var bar = 0; bar < chords.length; bar++) {
    final barStart = 0.4 + bar * 8 * eighth;
    final barEnd = barStart + 8 * eighth;
    strums.add((chords[bar].id, barStart));
    for (final slot in slots) {
      final t = barStart + slot * eighth;
      final down = slot.isEven;
      events.addAll(synth.strum(
        chords[bar],
        startSec: t,
        stopSec: slot == 7 ? barEnd - 0.03 : t + eighth * 2.2,
        down: down,
        level: down ? 0.22 : 0.12,
        onlyStrings: down ? null : {1, 2, 3, 4},
      ));
    }
  }
  return Performance(
    synth.render(events, durationSec: 0.4 + chords.length * 8 * eighth + 0.5, mic: mic),
    strums,
  );
}

class RunResult {
  int expected = 0;
  int hits = 0;
  int earlyHits = 0; // confirmed before its own strum (= without playing it)
  final latencies = <double>[];
  final earlyDetail = <String>[];
}

/// Target follows the progression; returns per-chord outcome.
void runNewEngine(Performance p, ChordCatalog catalog, RunResult r) {
  final engine = ChordDetectionEngine();
  var idx = 0;
  engine.setTarget(catalog.chordById(p.strums[0].$1)!);
  const chunk = 1764;
  for (var s = 0; s < p.audio.length && idx < p.strums.length; s += chunk) {
    final e = s + chunk > p.audio.length ? p.audio.length : s + chunk;
    for (final f in engine.addSamples(Float32List.sublistView(p.audio, s, e))) {
      final hit = f.hit;
      if (hit == null || idx >= p.strums.length) continue;
      final strumT = p.strums[idx].$2;
      final hitT = hit.confirmSample / sr;
      if (hitT < strumT) {
        r.earlyHits++;
        r.earlyDetail.add('${p.strums.map((x) => x.$1).join(',')}@$idx');
      } else {
        r.hits++;
        r.latencies.add((hitT - strumT) * 1000);
      }
      idx++;
      if (idx < p.strums.length) {
        engine.setTarget(catalog.chordById(p.strums[idx].$1)!);
      }
    }
  }
  r.expected += p.strums.length;
}

/// Old song-screen logic: first perfect frame after a 350 ms grace advances.
void runLegacy(Performance p, ChordCatalog catalog, RunResult r) {
  final proc = FftProcessor(fftSize: 8192, sampleRate: sr.toDouble());
  final m = LegacyChordMatcher(fftProcessor: proc);
  var idx = 0;
  var graceUntil = 0.0;
  var wasPerfect = false;
  for (var end = 8192; end <= p.audio.length && idx < p.strums.length; end += (0.08 * sr).round()) {
    final t = end / sr;
    if (t < graceUntil) continue;
    final frame = Float32List.sublistView(p.audio, end - 8192, end);
    final fb = m.evaluate(
      chord: catalog.chordById(p.strums[idx].$1)!,
      magnitudes: proc.computeMagnitudes(frame),
      referenceA4Hz: 440,
      inputLevel: frameRms(frame),
    );
    final perfect = fb.matchStatus == ChordMatchStatus.perfect;
    if (perfect && !wasPerfect) {
      final strumT = p.strums[idx].$2;
      if (t < strumT) {
        r.earlyHits++;
      } else {
        r.hits++;
        r.latencies.add((t - strumT) * 1000);
      }
      idx++;
      graceUntil = t + 0.35;
      wasPerfect = false;
      continue;
    }
    wasPerfect = perfect;
  }
  r.expected += p.strums.length;
}

void main() {
  final catalog = loadChordCatalog();
  List<ChordDefinition> ids(List<String> l) => [for (final i in l) catalog.chordById(i)!];
  const mics = [
    MicConditions(highPassHz: 100, noiseLevel: 0.001),
    MicConditions(highPassHz: 200, noiseLevel: 0.004, gain: 0.6),
  ];
  final progressions = [
    ids(['g_major', 'c_major', 'g_major', 'd_major', 'g_major']),
    ids(['e_minor', 'a_minor', 'd_major', 'g_major', 'e_minor']),
    ids(['c_major', 'g_major', 'a_minor', 'f_major', 'c_major']),
    ids(['a_minor', 'c_major', 'd_major', 'f_major', 'a_minor', 'e_major']),
    ids(['g_major', 'g_major', 'c_major', 'c_major', 'g_major']), // repeats
    ids(['d_major', 'a_major', 'b_minor', 'g_major', 'd_major']),
  ];

  final runners = <String, void Function(Performance, ChordCatalog, RunResult)>{
    'legacy': runLegacy,
    'new': runNewEngine,
  };

  for (final runner in runners.entries) {
    test('[${runner.key}] transitions', () {
      final single = RunResult();
      final bars = RunResult();
      for (final mic in mics) {
        for (var seed = 1; seed <= 3; seed++) {
          for (var i = 0; i < progressions.length; i++) {
            runner.value(progression(GuitarSynth(seed: seed * 31 + i), progressions[i], mic: mic), catalog, single);
            runner.value(strummedBars(GuitarSynth(seed: seed * 53 + i), progressions[i], mic: mic), catalog, bars);
          }
        }
      }
      for (final e in {'one strum per chord': single, 'strumming pattern': bars}.entries) {
        final r = e.value;
        final lat = [...r.latencies]..sort();
        final med = lat.isEmpty ? 0 : lat[lat.length ~/ 2];
        // ignore: avoid_print
        print('[${runner.key}] ${e.key}: hit ${r.hits}/${r.expected}, '
            'advanced without strum ${r.earlyHits}, median latency ${med.round()} ms'
            '${runner.key == 'new' ? ' ${r.earlyDetail}' : ''}');
      }
    }, timeout: const Timeout(Duration(minutes: 10)));
  }

  test('[new] wrong similar chord never confirms the target', () {
    final pairs = [
      ('g_major', 'g_7'), ('c_major', 'a_minor7'), ('a_major', 'a_minor'),
      ('d_major', 'd_sus4'), ('e_5', 'e_minor'), ('e_major', 'e_7'),
      ('a_5', 'a_major'), ('c_major', 'c_maj7'), ('d_minor', 'd_major'),
    ];
    var falseHits = 0, trials = 0, recovered = 0;
    for (final mic in mics) {
      for (var seed = 1; seed <= 3; seed++) {
        for (final (target, played) in pairs) {
          final synth = GuitarSynth(seed: seed * 7 + trials);
          // Wrong chord first, then the right one.
          final p = progression(synth, ids([played, target]), mic: mic);
          final engine = ChordDetectionEngine()..setTarget(catalog.chordById(target)!);
          var firstHitT = -1.0;
          for (final f in engine.addSamples(p.audio)) {
            if (f.hit != null && firstHitT < 0) firstHitT = f.hit!.confirmSample / sr;
          }
          trials++;
          if (firstHitT >= 0 && firstHitT < p.strums[1].$2) {
            falseHits++;
            // ignore: avoid_print
            print('false hit: target $target played $played mic $mic');
          }
          if (firstHitT >= p.strums[1].$2) recovered++;
        }
      }
    }
    // ignore: avoid_print
    print('[new] wrong-chord false hits: $falseHits/$trials, then correct chord hit: $recovered/$trials');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
