import 'dart:math';
import 'dart:typed_data';

import 'package:chord_trainer/audio/chord_detection_engine.dart';
import 'package:chord_trainer/audio/onset_detector.dart';
import 'package:chord_trainer/game/stroke_verifier.dart';
import 'package:chord_trainer/models/chord_definition.dart';
import 'package:chord_trainer/models/strumming_pattern.dart';

import 'guitar_synth.dart';

const openMidi = {6: 40, 5: 45, 4: 50, 3: 55, 2: 59, 1: 64};

/// One played stroke and what the game expected at that moment.
class PlayedStroke {
  PlayedStroke(this.timeSec, this.kind, {this.stringNumber, this.rightNote = true});
  final double timeSec;
  final PatternEventKind kind;
  final int? stringNumber;

  /// False when a "random" pluck played a different note than expected
  /// (a random pluck can land on the right note by chance).
  bool rightNote;
}

/// Runs the game pipeline (engine with game settings → captures → verifier)
/// over [audio]; returns per expected stroke whether it was accepted.
/// Strokes never captured count as not accepted.
List<bool> runStrokes(
  Float32List audio,
  List<PlayedStroke> strokes,
  ChordDefinition expectedChord,
) =>
    [for (final r in strokeResults(audio, strokes, expectedChord)) r == StrokeCheck.ok];

/// Per expected stroke: the verifier's verdict, or null if never captured.
List<StrokeCheck?> strokeResults(
  Float32List audio,
  List<PlayedStroke> strokes,
  ChordDefinition expectedChord,
) {
  final engine = ChordDetectionEngine(
    onsetDetector: OnsetDetector.forRhythmGame(),
    strumClusterMs: 90,
  )..setTarget(expectedChord);
  final verifier = StrokeVerifier(engine.matcher);
  final results = List<StrokeCheck?>.filled(strokes.length, null);
  for (var s = 0; s < audio.length; s += 1764) {
    final e = min(audio.length, s + 1764);
    engine.addSamples(Float32List.sublistView(audio, s, e));
    for (final c in engine.takeCaptures()) {
      final t = c.onsetSample / 44100;
      for (var i = 0; i < strokes.length; i++) {
        final dt = t - strokes[i].timeSec;
        if (dt > -0.03 && dt < 0.09 && results[i] == null) {
          final r = verifier.check(
            chord: expectedChord,
            kind: strokes[i].kind,
            stringNumber: strokes[i].stringNumber,
            frame: c.frame,
            residual: c.residual,
          );
          results[i] = r;
          break;
        }
      }
    }
  }
  return results;
}

/// ↓ - ↓ ↑ - ↑ ↓ ↑ for two bars of [chord] (or of open middle strings when
/// [randomOpen]), 80 BPM.
(Float32List, List<PlayedStroke>) strumBars(
  GuitarSynth synth,
  ChordDefinition chord, {
  required bool randomOpen,
  required MicConditions mic,
  bool soft = false,
}) {
  const eighth = 60 / 80 / 2;
  const slots = [0, 2, 3, 5, 6, 7];
  final events = <StringEvent>[];
  final strokes = <PlayedStroke>[];
  for (var bar = 0; bar < 2; bar++) {
    for (final slot in slots) {
      final t = 0.4 + (bar * 8 + slot) * eighth;
      final down = slot.isEven;
      strokes.add(PlayedStroke(t, down ? PatternEventKind.down : PatternEventKind.up));
      if (randomOpen) {
        // Strings 5–2 open, no chord held.
        final order = down ? [5, 4, 3, 2] : [2, 3, 4, 5];
        var tt = t;
        for (final s in order) {
          events.add(StringEvent(
            midi: openMidi[s]!,
            startSec: tt,
            amplitude: (down ? 0.2 : 0.12) * (0.7 + 0.3 * synth.rand()),
            stopSec: t + eighth * 2.2,
            stringNumber: s,
            attackNoise: !soft,
            attackSec: soft ? 0.008 : 0.003,
          ));
          tt += 0.012;
        }
      } else {
        events.addAll(synth.strum(
          chord,
          startSec: t,
          down: down,
          soft: soft,
          level: down ? 0.22 : 0.13,
          onlyStrings: down ? null : {1, 2, 3, 4},
          stopSec: t + eighth * 2.2,
        ));
      }
    }
  }
  return (synth.render(events, durationSec: 0.4 + 16 * eighth + 0.6, mic: mic), strokes);
}

/// p i m a i m a i (sixteenths at 66 BPM), the chord's notes or random open
/// middle strings.
(Float32List, List<PlayedStroke>) arpeggioBar(
  GuitarSynth synth,
  ChordDefinition chord, {
  required bool randomOpen,
  required MicConditions mic,
}) {
  const sixteenth = 60 / 66 / 4;
  const fingers = ['p', 'i', 'm', 'a', 'i', 'm', 'a', 'i'];
  const fingerString = {'p': 6, 'i': 3, 'm': 2, 'a': 1};
  final events = <StringEvent>[];
  final strokes = <PlayedStroke>[];
  final rng = Random(synth.seed);
  for (var rep = 0; rep < 2; rep++) {
    for (var k = 0; k < fingers.length; k++) {
      final t = 0.4 + (rep * fingers.length + k) * sixteenth * 1.0;
      final s = fingerString[fingers[k]]!;
      var expected = chord.isStringMuted(s) ? null : chord.noteForString(s);
      expected ??= chord.notes.first; // p on a muted bass string → chord bass
      int midi;
      int str;
      if (randomOpen) {
        str = 2 + rng.nextInt(4); // strings 2..5 open
        midi = openMidi[str]!;
      } else {
        str = expected.string;
        midi = expected.midi;
      }
      strokes.add(PlayedStroke(
        t,
        PatternEventKind.finger,
        stringNumber: s,
        rightNote: midi == expected.midi,
      ));
      events.add(StringEvent(
        midi: midi,
        startSec: t,
        amplitude: 0.2,
        stringNumber: str,
      ));
    }
  }
  return (synth.render(events, durationSec: 0.4 + 16 * sixteenth + 0.8, mic: mic), strokes);
}

/// Idle accepts per stroke kind (accumulates across calls; benches only).
final Map<String, int> idleByKind = {};

/// Counts strokes the game would accept while the player does *nothing*
/// new: every capture in [audio] is checked against every stroke kind.
/// Returns (captures, accepted).
(int, int) idleAccepts(Float32List audio, ChordDefinition chord, {double fromSec = 0.6}) {
  final engine = ChordDetectionEngine(
    onsetDetector: OnsetDetector.forRhythmGame(),
    strumClusterMs: 90,
  )..setTarget(chord);
  final verifier = StrokeVerifier(engine.matcher);
  var captures = 0, accepted = 0;
  for (var s = 0; s < audio.length; s += 1764) {
    final e = min(audio.length, s + 1764);
    engine.addSamples(Float32List.sublistView(audio, s, e));
    for (final c in engine.takeCaptures()) {
      if (c.onsetSample / 44100 < fromSec) continue;
      captures++;
      final kinds = [
        (PatternEventKind.down, null),
        (PatternEventKind.up, null),
        for (final s in [6, 3, 2, 1]) (PatternEventKind.finger, s),
      ];
      for (final k in kinds) {
        final key = k.$1 == PatternEventKind.finger ? 'finger' : k.$1.name;
        if (verifier.check(
              chord: chord,
              kind: k.$1,
              stringNumber: k.$2,
              frame: c.frame,
              residual: c.residual,
            ) ==
            StrokeCheck.ok) {
          idleByKind[key] = (idleByKind[key] ?? 0) + 1;
        }
      }
      if (kinds.any((k) => verifier.check(
                chord: chord,
                kind: k.$1,
                stringNumber: k.$2,
                frame: c.frame,
                residual: c.residual,
              ) ==
          StrokeCheck.ok)) {
        accepted++;
      }
    }
  }
  return (captures, accepted);
}
