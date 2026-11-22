import 'dart:math';

import '../audio/chord_detection_engine.dart';
import '../audio/spectrum_frame.dart';
import '../models/chord_definition.dart';
import 'latency_calibration.dart';
import 'rhythm_chart.dart';
import 'rhythm_judge.dart';
import 'stroke_verifier.dart';

/// What the guitar-mode referee did with one captured strum.
enum CaptureOutcome {
  /// Right notes, fresh, in time: judged as a hit.
  hit,

  /// Right notes, but another attack may still turn out to be the real
  /// stroke for this note: kept as the note's candidate until
  /// [GuitarStrokeReferee.flush] commits it (or a stronger attack replaces
  /// it).
  held,

  /// Right notes, but a stronger attack is already the candidate for this
  /// note: ignored.
  outranked,

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

  /// The same attack was delivered again: ignored (an attack is judged once).
  duplicate,
}

class CaptureDecision {
  const CaptureDecision({
    required this.outcome,
    required this.timeMs,
    this.note,
    this.input,
    this.detail = '',
    this.onsetSample,
  });

  final CaptureOutcome outcome;

  /// Chart time of the strum after latency correction.
  final double timeMs;
  final RhythmNote? note;

  /// The judge's verdict for [CaptureOutcome.hit].
  final InputOutcome? input;

  /// Verifier reason, for diagnostics.
  final String detail;

  /// Sample clock of the attack this decision is about (diagnostics).
  final int? onsetSample;

  String toLogLine() {
    final n = note;
    final noteText = n == null
        ? 'note=-'
        : 'note#${n.index} ${n.kind.name}${n.stringNumber == null ? '' : '/s${n.stringNumber}'}'
            ' @${n.timeMs.round()} dt=${(timeMs - n.timeMs).round()}ms';
    final judged = input?.result?.judgement.name;
    return 't=${timeMs.round()} ${outcome.name}${judged == null ? '' : '($judged)'} '
        '$noteText${onsetSample == null ? '' : ' sample=$onsetSample'} | $detail';
  }
}

/// A verified attack waiting to be committed to its note.
class _Candidate {
  _Candidate({
    required this.note,
    required this.timeMs,
    required this.own,
    required this.detail,
    required this.onsetSample,
    required this.strokeStartSample,
    required this.superseded,
    required this.strong,
    required this.lead,
  });

  final RhythmNote note;
  final double timeMs;

  /// How clearly this attack itself was a new stroke
  /// ([GuitarStrokeReferee.ownStrength]).
  final double own;
  final String detail;
  final int onsetSample;

  /// Attacks with the same value are one stroke (see
  /// [StrumCapture.strokeStartSample]).
  final int strokeStartSample;

  /// See [GuitarStrokeReferee.isSuperseded].
  final bool superseded;
  final bool strong;

  /// This attack's own sound, when a next attack cut into its capture.
  final SpectrumFrame? lead;
}

/// Guitar-mode judging of the rhythm game, without any UI: takes captured
/// strums and decides hit / wrong notes / ignored. The game screen and the
/// benches use this class, so the benches measure exactly what the app does.
///
/// **One stroke per note, the best one.** A ringing chord can produce an
/// attack shortly before the player's real stroke (its strings "breathing",
/// a finger leaving the old chord). Such an attack can pass the note check —
/// a weak ↑ over a ringing chord looks much like the chord ringing, and an
/// attack's capture (the 126 ms after it) can even contain the real strum
/// that follows. Committing the *first* acceptable attack therefore scored
/// the note early and threw the player's real stroke away as an extra.
/// Instead, an attack is committed at once only when it is strong and no
/// other attack followed inside its capture; otherwise it is held for
/// [holdMs] as the note's candidate, and the attack whose own sound is the
/// strongest new sound wins. Measured with
/// `test/bench/judgment_integrity_bench_test.dart`, which knows which stroke
/// produced every judgement.
class GuitarStrokeReferee {
  GuitarStrokeReferee({
    required this.judge,
    required this.verifier,
    required this.chordForBar,
    LatencyTrim? trim,
    this.holdMs = 150,
    this.supersedeMaxStrength = 0.3,
    this.supersedeMaxRatio = 0.6,
  }) : trim = trim ?? LatencyTrim();

  /// See [isSuperseded]. Set from the measured own-sound strength of real
  /// stroke starts vs. false attacks before a real stroke (phone simulation,
  /// `test/bench/judgment_integrity_bench_test.dart`).
  final double supersedeMaxStrength;
  final double supersedeMaxRatio;

  /// True when the attack of [capture] is not a stroke of its own: a next
  /// attack cut into its capture, and its own sound up to that attack was
  /// weak ([supersedeMaxStrength]) and much weaker than the whole capture
  /// ([supersedeMaxRatio]) — the fresh sound it holds was played at the next
  /// attack.
  bool isSuperseded(StrumCapture capture) {
    final lead = capture.leadFrame;
    if (lead == null) return false;
    final own = StrokeVerifier.attackStrength(lead, capture.residual);
    if (own >= supersedeMaxStrength) return false;
    final full = StrokeVerifier.attackStrength(capture.frame, capture.residual);
    return own < supersedeMaxRatio * full;
  }

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

  /// How long (chart time after it) a held candidate waits for a stronger
  /// attack. Any attack that late has been captured by the time
  /// [judgeDelayMs] has passed after it (capture 126 ms + delivery).
  /// 0 = commit the first acceptable attack (the previous behaviour).
  final double holdMs;

  /// How long after a strong stroke weak strokes still count, in beats.
  static const double activeBeats = 2.25;

  /// Notes at whose time a stroke with the wrong notes was heard. They stay
  /// open: a correct stroke inside the window still counts (the wrong one may
  /// have been a false attack while changing chords). If none comes, the miss
  /// is reported as "wrong notes".
  final Set<int> _wrongSeen = {};

  /// Held candidate per note index.
  final Map<int, _Candidate> _held = {};

  /// Attacks already seen (sample clock), so a re-delivered capture can
  /// never judge a second note.
  final Set<int> _seen = {};

  /// Chart time of the last strong stroke (see [StrokeVerifier.lastStrong]),
  /// committed or held.
  double? _lastStrongMs;

  /// Notes with a held candidate (diagnostics / tests).
  int get heldCount => _held.length;

  /// How clearly the attack of [capture] itself was a new stroke: attack
  /// strength of its own sound — up to the next attack when one cut into the
  /// capture ([StrumCapture.leadFrame]), else the whole capture.
  static double ownStrength(StrumCapture capture) =>
      StrokeVerifier.attackStrength(
        capture.leadFrame ?? capture.frame,
        capture.residual,
      );

  /// Two attacks of one stroke: does the later one ([capture]) add more new
  /// sound over the earlier one's own sound than the earlier one added over
  /// the sound before the stroke? A false attack just before a strum (a
  /// ringing chord "breathing") has little sound of its own and the strum
  /// adds a lot over it; the first strings of a real strum are loud on their
  /// own and its later strings add little.
  bool _addsMore(StrumCapture capture, _Candidate earlier) {
    final lead = earlier.lead;
    if (lead == null) return earlier.superseded;
    final gain = StrokeVerifier.attackStrength(capture.frame, lead.magnitudes);
    return gain > earlier.own;
  }

  /// True when [note] was missed and a wrong-notes stroke was heard for it;
  /// also flags it in the judge. Call for notes the judge just declared
  /// missed.
  bool resolveMissed(RhythmNote note) {
    if (!_wrongSeen.contains(note.index)) return false;
    judge.flagWrongNotes(note);
    return true;
  }

  /// Commits every held candidate whose wait is over. Call it *before*
  /// [RhythmJudge.advance], so a held note is judged rather than declared
  /// missed. Returns the hits.
  ///
  /// [judgedUntilMs]: the value passed to `advance` (a held note is always
  /// committed before its window could be declared missed).
  /// [capturedUntilMs]: stroke time (same scale as `heardMs` minus the trim)
  /// up to which every attack's capture has already been passed to
  /// [onCapture] — from the audio sample clock (see
  /// `ChordDetectionEngine.captureLagSamples`). With it a candidate is
  /// committed as soon as no rival can still arrive (~150 ms of audio after
  /// the hold ends) instead of waiting for the conservative miss deadline.
  List<CaptureDecision> flush(double judgedUntilMs, {double? capturedUntilMs}) {
    if (_held.isEmpty) return const [];
    final due = [
      for (final c in _held.values)
        if (c.timeMs + holdMs < judgedUntilMs ||
            (capturedUntilMs != null && c.timeMs + holdMs <= capturedUntilMs) ||
            c.note.timeMs + judge.goodWindowMs < judgedUntilMs)
          c,
    ]..sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return [for (final c in due) _commit(c)];
  }

  CaptureDecision _commit(_Candidate c) {
    _held.remove(c.note.index);
    // Small, bounded fine-tuning from verified strokes.
    trim.add(c.timeMs - c.note.timeMs);
    final input = judge.inputFor(c.note, c.timeMs);
    return CaptureDecision(
      outcome: CaptureOutcome.hit,
      timeMs: c.timeMs,
      note: c.note,
      input: input,
      detail: c.detail,
      onsetSample: c.onsetSample,
    );
  }

  /// [heardMs]: chart time of the strum minus the calibrated mic latency
  /// (the trim is applied here). [nowMs]: current chart time.
  CaptureDecision onCapture(
    double heardMs,
    StrumCapture capture, {
    required double nowMs,
  }) {
    final t = heardMs - trim.correctionMs;
    final sample = capture.onsetSample;
    if (!_seen.add(sample)) {
      return CaptureDecision(
        outcome: CaptureOutcome.duplicate,
        timeMs: t,
        detail: 'attack already judged',
        onsetSample: sample,
      );
    }
    final note = judge.noteNear(t);
    if (note == null) {
      judge.extras++;
      return CaptureDecision(
        outcome: CaptureOutcome.noNote,
        timeMs: t,
        detail: 'no unjudged note within ±${judge.goodWindowMs.round()}ms',
        onsetSample: sample,
      );
    }
    final chord = chordForBar(note.barIndex);
    if (chord == null) {
      return CaptureDecision(
        outcome: CaptureOutcome.noNote,
        timeMs: t,
        note: note,
        detail: 'unknown chord',
        onsetSample: sample,
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
          onsetSample: sample,
        );
      case StrokeCheck.noFreshSound:
        return CaptureDecision(
          outcome: CaptureOutcome.notFresh,
          timeMs: t,
          note: note,
          detail: detail,
          onsetSample: sample,
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
            onsetSample: sample,
          );
        }
        if (strong) _lastStrongMs = max(_lastStrongMs ?? t, t);
        final candidate = _Candidate(
          note: note,
          timeMs: t,
          own: ownStrength(capture),
          detail: '$detail · own ${ownStrength(capture).toStringAsFixed(2)}',
          onsetSample: sample,
          strokeStartSample: capture.strokeStartSample,
          superseded: isSuperseded(capture),
          strong: strong,
          lead: capture.leadFrame,
        );
        final rival = _held[note.index];
        if (rival != null) {
          // Two attacks of one stroke: the stroke happened at the first one,
          // unless that one was only the lead-in to this one. (Own strengths
          // cannot be compared here: a later attack of the same stroke is
          // measured against the sound from before the stroke began, so it
          // includes the whole stroke.) Attacks of different strokes: the
          // clearer new sound wins.
          final sameStroke =
              rival.strokeStartSample == candidate.strokeStartSample;
          final wins = sameStroke
              ? _addsMore(capture, rival)
              : candidate.own > rival.own;
          if (!wins) {
            final out = CaptureDecision(
              outcome: CaptureOutcome.outranked,
              timeMs: t,
              note: note,
              detail: '${candidate.detail} < held @${rival.timeMs.round()} '
                  '${sameStroke ? '(same stroke, earlier attack)' : 'own ${rival.own.toStringAsFixed(2)}'}',
              onsetSample: sample,
            );
            return out;
          }
        }
        // A strong attack with nothing after it inside its capture is
        // unambiguous: commit now (fast feedback). Otherwise wait.
        final clear = strong && capture.nextOnsetSample == null;
        if (holdMs <= 0 || clear) {
          _held.remove(note.index);
          return _commit(candidate);
        }
        _held[note.index] = candidate;
        return CaptureDecision(
          outcome: CaptureOutcome.held,
          timeMs: t,
          note: note,
          detail: '${candidate.detail}'
              '${rival == null ? '' : ' (replaces @${rival.timeMs.round()})'}',
          onsetSample: sample,
        );
    }
  }
}
