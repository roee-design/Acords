import '../audio/chord_detection_engine.dart';
import '../models/chord_definition.dart';
import '../models/strumming_pattern.dart';
import 'latency_calibration.dart';
import 'rhythm_chart.dart';
import 'rhythm_judge.dart';
import 'stroke_verifier.dart';

/// What the guitar-mode referee did with one captured strum.
enum CaptureOutcome {
  /// Right notes, fresh, in time: judged as a hit.
  hit,

  /// Heard at a note's time but with the wrong notes: that note is missed.
  wrongNotes,

  /// Not a new stroke (noise, or the chord ringing on): ignored.
  notFresh,

  /// ↑ or i/m/a with no hit in the beat before it: ignored (a ringing chord
  /// cannot score on its own).
  unanchored,

  /// No unjudged note within the timing window: counted as an extra stroke.
  noNote,
}

class CaptureDecision {
  const CaptureDecision({
    required this.outcome,
    required this.timeMs,
    this.note,
    this.input,
    this.detail = '',
  });

  final CaptureOutcome outcome;

  /// Chart time of the strum after latency correction.
  final double timeMs;
  final RhythmNote? note;

  /// The judge's verdict for [CaptureOutcome.hit].
  final InputOutcome? input;

  /// Verifier reason, for diagnostics.
  final String detail;

  String toLogLine() {
    final n = note;
    final noteText = n == null
        ? 'note=-'
        : 'note#${n.index} ${n.kind.name}${n.stringNumber == null ? '' : '/s${n.stringNumber}'}'
            ' @${n.timeMs.round()} dt=${(timeMs - n.timeMs).round()}ms';
    final judged = input?.result?.judgement.name;
    return 't=${timeMs.round()} ${outcome.name}${judged == null ? '' : '($judged)'} '
        '$noteText | $detail';
  }
}

/// Guitar-mode judging of the rhythm game, without any UI: takes captured
/// strums and decides hit / wrong notes / ignored. The game screen and the
/// false-positive bench both use this class, so the bench measures exactly
/// what the app does.
class GuitarStrokeReferee {
  GuitarStrokeReferee({
    required this.judge,
    required this.verifier,
    required this.chordForBar,
    LatencyTrim? trim,
  }) : trim = trim ?? LatencyTrim();

  final RhythmJudge judge;
  final StrokeVerifier verifier;
  final ChordDefinition? Function(int barIndex) chordForBar;

  /// In-game fine-tuning of the mic latency (bounded, see [LatencyTrim]).
  final LatencyTrim trim;

  /// [heardMs]: chart time of the strum minus the calibrated mic latency
  /// (the trim is applied here). [nowMs]: current chart time.
  CaptureDecision onCapture(
    double heardMs,
    StrumCapture capture, {
    required double nowMs,
  }) {
    final t = heardMs - trim.correctionMs;
    final note = judge.noteNear(t);
    if (note == null) {
      judge.extras++;
      return CaptureDecision(
        outcome: CaptureOutcome.noNote,
        timeMs: t,
        detail: 'no unjudged note within ±${judge.goodWindowMs.round()}ms',
      );
    }
    final chord = chordForBar(note.barIndex);
    if (chord == null) {
      return CaptureDecision(
        outcome: CaptureOutcome.noNote,
        timeMs: t,
        note: note,
        detail: 'unknown chord',
      );
    }
    final check = verifier.check(
      chord: chord,
      kind: note.kind,
      stringNumber: note.stringNumber,
      frame: capture.frame,
      residual: capture.residual,
    );
    final detail = '${chord.displayName}: ${verifier.lastDetail}';
    switch (check) {
      case StrokeCheck.wrongNotes:
        judge.markWrongNotes(note, nowMs);
        return CaptureDecision(
          outcome: CaptureOutcome.wrongNotes,
          timeMs: t,
          note: note,
          detail: detail,
        );
      case StrokeCheck.noFreshSound:
        return CaptureDecision(
          outcome: CaptureOutcome.notFresh,
          timeMs: t,
          note: note,
          detail: detail,
        );
      case StrokeCheck.ok:
        // ↑ and i/m/a only count while actually playing (see RhythmJudge).
        final needsAnchor = note.kind == PatternEventKind.up ||
            (note.kind == PatternEventKind.finger &&
                (note.stringNumber ?? 6) < 4);
        if (needsAnchor &&
            !judge.hasRecentHitBefore(note, judge.chart.beatMs * 1.05)) {
          return CaptureDecision(
            outcome: CaptureOutcome.unanchored,
            timeMs: t,
            note: note,
            detail: '$detail · no hit in the previous beat',
          );
        }
        // Small, bounded fine-tuning from verified strokes.
        trim.add(t - note.timeMs);
        final input = judge.input(t);
        return CaptureDecision(
          outcome: CaptureOutcome.hit,
          timeMs: t,
          note: note,
          input: input,
          detail: detail,
        );
    }
  }
}
