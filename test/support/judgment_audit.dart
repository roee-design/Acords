import 'dart:math';
import 'dart:typed_data';

import 'package:chord_trainer/audio/chord_detection_engine.dart';
import 'package:chord_trainer/game/guitar_stroke_referee.dart';
import 'package:chord_trainer/game/rhythm_chart.dart';
import 'package:chord_trainer/game/rhythm_judge.dart';
import 'package:chord_trainer/models/chord_definition.dart';
import 'package:chord_trainer/models/strumming_pattern.dart';

import 'game_replay.dart';
import 'realistic_sim.dart';

/// One capture the referee saw, with the physical stroke that produced it.
class AuditedCapture {
  AuditedCapture(this.decision, this.onsetMs, this.stroke, this.sinceStrokeMs, this.capture);

  final CaptureDecision decision;
  final StrumCapture capture;

  /// Attack time in true chart time (audio time minus the true mic latency).
  final double onsetMs;

  /// Note index of the stroke the player was making when this attack
  /// happened (null: no stroke started within [AuditResult.ringMs] before).
  final int? stroke;
  final double sinceStrokeMs;
}

/// Ground-truth audit of one guitar-mode round: for every judgement, did it
/// come from the stroke the player made for that note?
class AuditResult {
  AuditResult(this.run, this.captures, this.played, this.chart);

  /// Attacks more than this long after the last stroke began are not part
  /// of it (the chord ringing on, noise).
  static const double ringMs = 250;

  final GameRunResult run;
  final List<AuditedCapture> captures;

  /// Chart time each note was really played (null = not played).
  final List<double?> played;
  final RhythmChart chart;

  Iterable<AuditedCapture> get hits =>
      captures.where((c) => c.decision.outcome == CaptureOutcome.hit);

  /// Hits whose audio came from the stroke of the note they were credited to.
  int get correctHits =>
      hits.where((c) => c.stroke == c.decision.note!.index).length;

  /// Hits credited to a note whose own stroke did not produce them (a
  /// neighbour's stroke, its echo, or nothing at all).
  List<AuditedCapture> get misattributed =>
      hits.where((c) => c.stroke != c.decision.note!.index).toList();

  /// Hits with no stroke at all behind them (ringing, noise).
  int get phantomHits => hits.where((c) => c.stroke == null).length;

  /// Physical strokes that were credited more than once.
  int get duplicateCredits {
    final per = <int, int>{};
    for (final c in hits) {
      if (c.stroke != null) per[c.stroke!] = (per[c.stroke!] ?? 0) + 1;
    }
    return per.values.where((n) => n > 1).fold(0, (a, n) => a + n - 1);
  }

  /// Played notes that were not credited by their own stroke.
  int get playedNotCredited {
    final credited = {
      for (final c in hits)
        if (c.stroke == c.decision.note!.index) c.stroke!,
    };
    var n = 0;
    for (var i = 0; i < played.length; i++) {
      if (played[i] != null && !credited.contains(i)) n++;
    }
    return n;
  }

  int get playedCount => played.whereType<double>().length;

  /// Judged time − really played time, for correctly attributed hits.
  List<double> get timingErrors => [
        for (final c in hits)
          if (c.stroke == c.decision.note!.index)
            c.decision.timeMs - played[c.stroke!]!,
      ];

  /// How long after the player really played each correctly attributed
  /// hit was shown (chart time of the decision − played time). Includes the
  /// phone's mic latency.
  List<double> get feedbackDelays => [
        for (final c in hits)
          if (c.stroke == c.decision.note!.index &&
              run.decidedAtMs[c.capture.onsetSample] != null)
            run.decidedAtMs[c.capture.onsetSample]! - played[c.stroke!]!,
      ];

  /// Notes the judge scored as hits (any cause).
  int get scoredHits => run.hits;

  String describe(AuditedCapture c) {
    final n = c.decision.note!;
    final s = c.stroke;
    return 'note#${n.index}(${n.kind.name}@${n.timeMs.round()}) credited by '
        '${s == null ? 'NO stroke' : 'stroke of note#$s (${chart.notes[s].kind.name}@${chart.notes[s].timeMs.round()}) '
            '+${c.sinceStrokeMs.round()}ms into it'} · ${c.decision.toLogLine()}';
  }
}

/// Replays [audio] like the app and audits each judgement against the true
/// strokes. [played]: chart time each note was really played (null = not
/// played); [trueLatencyMs]: the simulated phone's latency.
AuditResult auditRound({
  required RhythmChart chart,
  required ChordCatalog catalog,
  required List<double?> played,
  required double trueLatencyMs,
  required double calibrationMs,
  required Float32List audio,
  double chartStartMs = 1000,
  int chunkSamples = 1764,
  double? holdMs,
  int Function(int chunkIndex)? chunkOf,
  double processingDelayMs = 0,
  bool deliverTwice = false,
}) {
  final starts = <(double, int)>[
    for (var i = 0; i < played.length; i++)
      if (played[i] != null && chart.notes[i].kind != PatternEventKind.pause)
        (played[i]!, i),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  final captures = <AuditedCapture>[];
  final run = replayGame(
    audio: audio,
    chart: chart,
    catalog: catalog,
    chartStartMs: chartStartMs,
    calibrationMs: calibrationMs,
    chunkSamples: chunkSamples,
    holdMs: holdMs,
    chunkOf: chunkOf,
    processingDelayMs: processingDelayMs,
    deliverTwice: deliverTwice,
    onCapture: (d, c) {
      final onset = c.onsetSample * 1000 / 44100 - chartStartMs - trueLatencyMs;
      // The stroke being made: the latest one that began before this attack
      // (a little slack: the detector can fire a few ms early).
      int? stroke;
      var since = double.infinity;
      for (final (t, i) in starts) {
        if (t > onset + 30) break;
        stroke = i;
        since = onset - t;
      }
      if (since > AuditResult.ringMs) stroke = null;
      captures.add(AuditedCapture(d, onset, stroke, since, c));
    },
  );
  return AuditResult(run, captures, played, chart);
}

/// Convenience: a simulated correct performance through [mic].
AuditResult auditCorrectPlaying({
  required RhythmChart chart,
  required ChordCatalog catalog,
  required PlayerModel player,
  required PhoneMic mic,
  required int seed,
  double? calibrationMs,
  int chunkSamples = 1764,
  double? holdMs,
}) {
  final perf = perform(chart: chart, catalog: catalog, player: player, seed: seed * 100 + 1);
  final audio = applyPhoneMic(perf.dry, mic, seed: seed);
  return auditRound(
    chart: chart,
    catalog: catalog,
    played: [
      for (final n in chart.notes)
        n.kind == PatternEventKind.pause ? null : perf.playedMs[n.index],
    ],
    trueLatencyMs: mic.latencyMs,
    calibrationMs: calibrationMs ?? mic.latencyMs + 20,
    audio: audio,
    chunkSamples: chunkSamples,
    holdMs: holdMs,
  );
}

double median(List<double> v) {
  if (v.isEmpty) return double.nan;
  final s = [...v]..sort();
  return s[s.length ~/ 2];
}

double quantile(List<double> v, double p) {
  if (v.isEmpty) return double.nan;
  final s = [...v]..sort();
  return s[(p * (s.length - 1)).round().clamp(0, s.length - 1)];
}

double maxAbs(List<double> v) => v.isEmpty ? 0 : v.map((x) => x.abs()).reduce(max);

extension JudgementCount on RhythmJudge {
  int get hitCount => perfects + goods;
}
