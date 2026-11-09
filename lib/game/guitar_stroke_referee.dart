import '../audio/chord_detection_engine.dart';
import '../models/chord_definition.dart';
import 'latency_calibration.dart';
import 'rhythm_chart.dart';
import 'rhythm_judge.dart';
import 'stroke_verifier.dart';

/// What the guitar-mode referee did with one captured strum.
enum CaptureOutcome {
  /// Right notes, fresh, in time: judged as a hit.
  hit,

  /// Heard at a note's time but with the wrong notes. The note stays open
  /// for a correct stroke; if none comes it is reported as wrong notes.
  wrongNotes,

  /// Not a new stroke (noise, or the chord ringing on): ignored.
  notFresh,

  /// A weak stroke with no strong stroke shortly before it: ignored (a
  /// ringing chord cannot score on its own).
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

  /// Timing windows of guitar mode (the mic adds jitter a touch screen does
  /// not have, so they are a little wider than touch mode's 70 / 140 ms).
  static const double perfectWindowMs = 80;
  static const double goodWindowMs = 170;

  /// A strum reaches the referee only after the mic latency plus the time
  /// needed to analyse its notes; a note must not be called missed before
  /// then. Added to the calibrated latency.
  static const double judgeDelayMs = 260;

  final RhythmJudge judge;
  final StrokeVerifier verifier;
  final ChordDefinition? Function(int barIndex) chordForBar;

  /// In-game fine-tuning of the mic latency (bounded, see [LatencyTrim]).
  final LatencyTrim trim;

  /// How long after a strong stroke weak strokes still count, in beats.
  static const double activeBeats = 2.25;

  /// Notes at whose time a stroke with the wrong notes was heard. They stay
  /// open: a correct stroke inside the window still counts (the wrong one may
  /// have been a false attack while changing chords). If none comes, the miss
  /// is reported as "wrong notes".
  final Set<int> _wrongSeen = {};

  /// Chart time of the last strong stroke (see [StrokeVerifier.lastStrong]).
  double? _lastStrongMs;

  /// True when [note] was missed and a wrong-notes stroke was heard for it;
  /// also flags it in the judge. Call for notes the judge just declared
  /// missed.
  bool resolveMissed(RhythmNote note) {
    if (!_wrongSeen.contains(note.index)) return false;
    judge.flagWrongNotes(note);
    return true;
  }

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
        _wrongSeen.add(note.index);
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
        // A weak stroke (a soft ↑, a light finger note, a muted "chk") looks
        // too much like a ringing chord to count on its own: it needs a
        // strong stroke shortly before it. A chord left ringing never
        // produces strong strokes, so it cannot score.
        final strong = verifier.lastStrong;
        final last = _lastStrongMs;
        final active = last != null &&
            t - last <= activeBeats * judge.chart.beatMs &&
            t >= last;
        if (!strong && !active) {
          return CaptureDecision(
            outcome: CaptureOutcome.unanchored,
            timeMs: t,
            note: note,
            detail: '$detail · weak, no strong stroke in the last '
                '$activeBeats beats',
          );
        }
        if (strong) _lastStrongMs = t;
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
