import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:chord_trainer/audio/chord_detection_engine.dart';
import 'package:chord_trainer/audio/detection_diagnostics.dart';
import 'package:chord_trainer/audio/onset_detector.dart';
import 'package:chord_trainer/game/guitar_stroke_referee.dart';
import 'package:chord_trainer/game/rhythm_chart.dart';
import 'package:chord_trainer/game/rhythm_judge.dart';
import 'package:chord_trainer/game/stroke_verifier.dart';
import 'package:chord_trainer/models/chord_definition.dart';
import 'package:chord_trainer/models/strumming_pattern.dart';

/// Loads a pattern from assets/strum_patterns.json by id.
StrummingPattern loadPattern(String id) {
  final json = jsonDecode(File('assets/strum_patterns.json').readAsStringSync())
      as Map<String, dynamic>;
  final p = (json['patterns'] as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .firstWhere((p) => p['id'] == id);
  return StrummingPattern.fromJson(p);
}

/// Outcome of replaying one guitar-mode round.
class GameRunResult {
  GameRunResult({
    required this.judge,
    required this.outcomes,
    required this.onsets,
    required this.peakRejections,
    required this.decisions,
    required this.log,
  });

  final RhythmJudge judge;

  /// Captured strums per referee outcome.
  final Map<CaptureOutcome, int> outcomes;
  final int onsets;

  /// Flux peaks that were not onsets, per rejecting rule.
  final Map<String, int> peakRejections;
  final List<CaptureDecision> decisions;

  /// Full diagnostics log (LEVEL / PEAK / STROKE lines).
  final List<String> log;

  /// The number the game shows at the end (0–1).
  double get accuracy => judge.finalAccuracy;
  int get hits => judge.perfects + judge.goods;
}

/// Runs the rhythm game's guitar mode over [audio] exactly as the app does:
/// engine with the game's onset settings → [GuitarStrokeReferee] →
/// [RhythmJudge] with the guitar timing windows.
///
/// Chart time of sample `s` = s / rate·1000 − [chartStartMs] − [calibrationMs]
/// (for app recordings: chartStartMs = sampleZeroToStartMs + leadInMs).
GameRunResult replayGame({
  required Float32List audio,
  required RhythmChart chart,
  required ChordCatalog catalog,
  required double chartStartMs,
  double calibrationMs = 0,
  int sampleRate = 44100,
}) {
  final engine = ChordDetectionEngine(
    sampleRate: sampleRate,
    onsetDetector: OnsetDetector.forRhythmGame(sampleRate: sampleRate),
    strumClusterMs: 90,
  )..setTarget(catalog.chordById(chart.bars.first.chordId)!);
  final diag = DetectionDiagnostics(echo: false)
    ..attachTo(engine.onsetDetector, engine.matcher);
  var onsets = 0;
  final peakRejections = <String, int>{};
  final hop = engine.onsetDetector.onHop!;
  engine.onsetDetector.onHop = (r) {
    hop(r);
    if (r.onset) onsets++;
    if (r.isPeak && !r.onset) {
      for (final reason in r.rejectReasons) {
        peakRejections[reason] = (peakRejections[reason] ?? 0) + 1;
      }
    }
  };

  final judge = RhythmJudge(chart, perfectWindowMs: 80, goodWindowMs: 170);
  final referee = GuitarStrokeReferee(
    judge: judge,
    verifier: StrokeVerifier(engine.matcher, referenceA4Hz: catalog.referenceA4Hz),
    chordForBar: (i) => catalog.chordById(chart.bars[i].chordId),
  );
  final outcomes = <CaptureOutcome, int>{};
  final decisions = <CaptureDecision>[];
  var currentBar = -1;

  const chunk = 1764; // ~40 ms, like the recorder
  for (var s = 0; s < audio.length; s += chunk) {
    final e = min(audio.length, s + chunk);
    engine.addSamples(Float32List.sublistView(audio, s, e));
    final now = e * 1000 / sampleRate - chartStartMs;

    // Same bar tracking as the screen (target chord for the chord bonus).
    final bar = chart.barAt(max(0.0, now + 60));
    if (bar != null && bar.index != currentBar) {
      currentBar = bar.index;
      engine.setTarget(catalog.chordById(bar.chordId)!);
    }

    for (final c in engine.takeCaptures()) {
      final heard = c.onsetSample * 1000 / sampleRate - chartStartMs - calibrationMs;
      // Like the screen: strokes arriving during the count-in are ignored.
      if (now < 0) continue;
      final d = referee.onCapture(heard, c, nowMs: now);
      diag.decision(d);
      decisions.add(d);
      outcomes[d.outcome] = (outcomes[d.outcome] ?? 0) + 1;
    }
    judge.advance(now - calibrationMs - referee.trim.correctionMs - 260);
  }
  judge.advance(double.infinity);
  diag.detach();
  return GameRunResult(
    judge: judge,
    outcomes: outcomes,
    onsets: onsets,
    peakRejections: peakRejections,
    decisions: decisions,
    log: diag.lines,
  );
}

/// Reads a 16-bit PCM mono WAV (as written by DetectionDiagnostics).
(Float32List, int) readWav(File file) {
  final bytes = file.readAsBytesSync();
  final data = ByteData.sublistView(bytes);
  final rate = data.getUint32(24, Endian.little);
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final size = data.getUint32(offset + 4, Endian.little);
    if (id == 'data') {
      final n = min(size, bytes.length - offset - 8) ~/ 2;
      final out = Float32List(n);
      for (var i = 0; i < n; i++) {
        out[i] = data.getInt16(offset + 8 + 2 * i, Endian.little) / 32768.0;
      }
      return (out, rate);
    }
    offset += 8 + size;
  }
  throw FormatException('no data chunk in ${file.path}');
}
