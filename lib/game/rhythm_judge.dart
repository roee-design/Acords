import 'dart:math';

import '../models/strumming_pattern.dart';
import 'rhythm_chart.dart';

enum Judgement { perfect, good, miss }

/// Direction of a player stroke (screen swipe); null = unknown (mic / tap).
enum StrokeDirection { down, up }

/// Outcome of one note, kept for animations and the results screen.
class NoteResult {
  const NoteResult({
    required this.judgement,
    required this.atMs,
    this.offsetMs,
    this.wrongDirection = false,
    this.wrongNotes = false,
  });

  final Judgement judgement;

  /// Chart time at which the judgement happened.
  final double atMs;

  /// Input time − note time (negative = early). Null for misses.
  final double? offsetMs;
  final bool wrongDirection;

  /// Missed because the mic heard the wrong notes at this time.
  final bool wrongNotes;
}

/// Result of feeding one input to [RhythmJudge.input].
class InputOutcome {
  const InputOutcome({this.note, this.result, this.onRest = false});

  /// Note that was hit, or null for an extra stroke.
  final RhythmNote? note;
  final NoteResult? result;

  /// Extra stroke that landed on a rest of the pattern.
  final bool onRest;

  bool get isExtra => note == null;
}

/// Pure timing judge — no Flutter, fully testable.
class RhythmJudge {
  RhythmJudge(
    this.chart, {
    this.perfectWindowMs = 70,
    this.goodWindowMs = 140,
  });

  final RhythmChart chart;
  final double perfectWindowMs;
  final double goodWindowMs;

  final Map<int, NoteResult> results = {};
  var _nextUnjudged = 0;

  int combo = 0;
  int maxCombo = 0;
  int score = 0;
  int extras = 0;
  final List<double> _offsets = [];

  int get perfects =>
      results.values.where((r) => r.judgement == Judgement.perfect).length;
  int get goods =>
      results.values.where((r) => r.judgement == Judgement.good).length;
  int get misses =>
      results.values.where((r) => r.judgement == Judgement.miss).length;
  int get judgedCount => results.length;
  bool get isFinished => results.length >= chart.notes.length;

  /// Score multiplier from the current combo: ×1 … ×4.
  int get multiplier => min(4, 1 + combo ~/ 8);

  /// 0–1 weighted accuracy over judged notes (perfect 1, good 0.6).
  double get accuracy {
    if (results.isEmpty) return 0;
    return (perfects + goods * 0.6) / results.length;
  }

  /// Accuracy over the whole chart (unplayed notes count as misses).
  double get finalAccuracy {
    if (chart.notes.isEmpty) return 0;
    return (perfects + goods * 0.6) / chart.notes.length;
  }

  int get stars {
    final a = finalAccuracy;
    if (a >= 0.92) return 3;
    if (a >= 0.78) return 2;
    if (a >= 0.6) return 1;
    return 0;
  }

  /// Median timing offset of hit notes (negative = player tends to be early).
  double? get medianOffsetMs {
    if (_offsets.length < 4) return null;
    final s = [..._offsets]..sort();
    return s[s.length ~/ 2];
  }

  /// Marks notes whose window has passed as missed. Returns them.
  List<RhythmNote> advance(double nowMs) {
    final missed = <RhythmNote>[];
    while (_nextUnjudged < chart.notes.length) {
      final note = chart.notes[_nextUnjudged];
      if (results.containsKey(note.index)) {
        _nextUnjudged++;
        continue;
      }
      if (nowMs - note.timeMs <= goodWindowMs) break;
      results[note.index] = NoteResult(judgement: Judgement.miss, atMs: nowMs);
      combo = 0;
      missed.add(note);
      _nextUnjudged++;
    }
    return missed;
  }

  /// Judges a stroke at chart time [timeMs].
  InputOutcome input(double timeMs, {StrokeDirection? direction}) {
    advance(timeMs);
    RhythmNote? best;
    var bestDist = double.infinity;
    for (var i = _nextUnjudged; i < chart.notes.length; i++) {
      final note = chart.notes[i];
      final d = timeMs - note.timeMs;
      if (d < -goodWindowMs) break;
      if (results.containsKey(note.index)) continue;
      if (d.abs() < bestDist) {
        bestDist = d.abs();
        best = note;
      }
    }

    if (best == null || bestDist > goodWindowMs) {
      extras++;
      return InputOutcome(onRest: _isNearRest(timeMs));
    }

    final offset = timeMs - best.timeMs;
    final wrongDirection = direction != null &&
        ((best.kind == PatternEventKind.down &&
                direction == StrokeDirection.up) ||
            (best.kind == PatternEventKind.up &&
                direction == StrokeDirection.down));
    final judgement = offset.abs() <= perfectWindowMs && !wrongDirection
        ? Judgement.perfect
        : Judgement.good;
    final result = NoteResult(
      judgement: judgement,
      atMs: timeMs,
      offsetMs: offset,
      wrongDirection: wrongDirection,
    );
    results[best.index] = result;
    _offsets.add(offset);
    combo++;
    maxCombo = max(maxCombo, combo);
    score += (judgement == Judgement.perfect ? 100 : 60) * multiplier;
    return InputOutcome(note: best, result: result);
  }

  /// Applies a swipe direction learnt shortly after the touch was judged.
  /// Returns true when the note was downgraded for the wrong direction.
  bool applyDirection(int noteIndex, StrokeDirection direction) {
    final result = results[noteIndex];
    if (result == null || result.judgement == Judgement.miss) return false;
    final note = chart.notes[noteIndex];
    final wrong = (note.kind == PatternEventKind.down &&
            direction == StrokeDirection.up) ||
        (note.kind == PatternEventKind.up &&
            direction == StrokeDirection.down);
    if (!wrong || result.wrongDirection) return false;
    if (result.judgement == Judgement.perfect) {
      score = max(0, score - 40 * multiplier);
    }
    results[noteIndex] = NoteResult(
      judgement: Judgement.good,
      atMs: result.atMs,
      offsetMs: result.offsetMs,
      wrongDirection: true,
    );
    return true;
  }

  /// Number of strokes heard at a note's time with the wrong notes.
  int wrongNotes = 0;

  /// The player strummed at [note]'s time but the mic heard the wrong notes
  /// (no chord held, wrong strings): the note counts as missed.
  void markWrongNotes(RhythmNote note, double atMs) {
    if (results.containsKey(note.index)) return;
    results[note.index] = NoteResult(
      judgement: Judgement.miss,
      atMs: atMs,
      wrongNotes: true,
    );
    wrongNotes++;
    combo = 0;
  }

  /// Unjudged note closest to [timeMs] within the good window, if any.
  RhythmNote? noteNear(double timeMs) {
    RhythmNote? best;
    var bestDist = double.infinity;
    for (var i = _nextUnjudged; i < chart.notes.length; i++) {
      final note = chart.notes[i];
      final d = timeMs - note.timeMs;
      if (d < -goodWindowMs) break;
      if (results.containsKey(note.index)) continue;
      if (d.abs() <= goodWindowMs && d.abs() < bestDist) {
        bestDist = d.abs();
        best = note;
      }
    }
    return best;
  }

  /// True when some note in the [windowMs] before [note] was hit — i.e. the
  /// player is actively playing. ↑ strums and i/m/a notes need this: a chord
  /// left ringing can look like a soft ↑ to the mic, but never like the ↓
  /// (or thumb) that always precedes them when someone really plays.
  bool hasRecentHitBefore(RhythmNote note, double windowMs) {
    for (var i = note.index - 1; i >= 0; i--) {
      final prev = chart.notes[i];
      if (note.timeMs - prev.timeMs > windowMs) break;
      final r = results[prev.index];
      if (r != null && r.judgement != Judgement.miss) return true;
    }
    return false;
  }

  /// Adds a bonus (e.g. chord confirmed for a bar).
  void addBonus(int points) => score += points;

  bool _isNearRest(double timeMs) {
    final slot = (timeMs / chart.slotMs).round();
    if (slot < 0) return false;
    final events = chart.pattern.events;
    if (events.isEmpty) return false;
    final inBar = slot % chart.pattern.slotsPerBar;
    return !events[inBar % events.length].isSounding;
  }
}
