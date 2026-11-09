import 'dart:math';
import 'dart:typed_data';

import 'package:chord_trainer/audio/chord_detection_engine.dart';
import 'package:chord_trainer/audio/onset_detector.dart';
import 'package:chord_trainer/game/latency_calibration.dart';
import 'package:chord_trainer/game/rhythm_chart.dart';
import 'package:chord_trainer/game/stroke_verifier.dart';
import 'package:chord_trainer/models/chord_definition.dart';
import 'package:chord_trainer/models/strumming_pattern.dart';

import 'realistic_sim.dart';

/// Simulates the app's mic calibration screen: the player strums a chord on
/// each slow pulse, the phone hears it through [mic], and the app's own
/// calibrator estimates the latency. Returns null when nothing was measured.
LatencyEstimate? simulateCalibration({
  required ChordCatalog catalog,
  required PlayerModel player,
  required PhoneMic mic,
  required int seed,
  String chordId = 'c_major',
}) {
  const beatMs = 60000 / 70;
  const leadSec = 0.5;
  const maxBeats = 18;
  final pulses = RhythmChart.forPattern(
    pattern: StrummingPattern.fromJson(const {
      'id': 'calibration',
      'name': 'calibration',
      'beatsPerBar': 1,
      'subdivision': 1,
      'strokes': '↓',
    }),
    chordIds: List.filled(maxBeats, chordId),
    bpm: 70,
    rounds: 1,
  );
  final dry = perform(
    chart: pulses,
    catalog: catalog,
    player: player,
    seed: seed,
    chartStartSec: leadSec,
  ).dry;
  final audio = applyPhoneMic(dry, mic, seed: seed);

  final engine = ChordDetectionEngine(
    onsetDetector: OnsetDetector.forRhythmGame(),
  )..setTarget(catalog.chordById(chordId)!);
  final calibrator = LatencyCalibrator(beatMs: beatMs, firstCountedBeat: 2);
  for (var s = 0; s < audio.length && calibrator.count < 10; s += 1764) {
    final e = min(audio.length, s + 1764);
    engine.addSamples(Float32List.sublistView(audio, s, e));
    for (final c in engine.takeCaptures()) {
      final strength = StrokeVerifier.attackStrength(c.frame, c.residual);
      if (strength < 0.3) continue;
      calibrator.addStrum(
        c.onsetSample * 1000 / 44100 - leadSec * 1000,
        weight: strength,
      );
    }
  }
  return calibrator.estimate();
}
