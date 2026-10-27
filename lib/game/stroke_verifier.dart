import 'dart:math';

import '../audio/spectrum_frame.dart';
import '../chord/chord_matcher.dart';
import '../models/chord_definition.dart';
import '../models/feedback_result.dart';
import '../models/strumming_pattern.dart';

/// Why a stroke heard by the mic did or did not count.
enum StrokeCheck {
  /// The right notes, freshly played.
  ok,

  /// Notes missing (bass / chord tones / the expected string) or foreign
  /// notes present — e.g. strumming open strings without holding the chord.
  wrongNotes,

  /// Nothing new was played: the "strum" was noise or the previous chord
  /// ringing on.
  noFreshSound,
}

/// Checks *what* a strum or pluck contained, not only when it happened.
///
/// Rules (all relative, so they work at any volume):
/// * ↓ strum — no foreign note; the chord's bass string sounds; every pitch
///   class of the chord sounds; at most one string missing; and the chord's
///   notes got clearly louder than just before the strum.
/// * ↑ strum — the same, except the bass is not required (an up-stroke only
///   reaches the thin strings) and freshness is measured on the top strings.
/// * finger note (p/i/m/a) — the expected string's note sounds, got clearly
///   louder, and nothing foreign rings.
/// * ✕ mute — percussive, only needs a fresh attack (not checked here).
class StrokeVerifier {
  StrokeVerifier(
    this.matcher, {
    this.referenceA4Hz = 440,
    this.downFreshness = 0.28,
    this.upFreshness = 0.12,
    this.noteFreshness = 0.2,
  });

  final ChordMatcher matcher;
  final double referenceA4Hz;

  /// Minimum [freshness] score of a ↓ strum (mean log rise of the chord's
  /// partials across the attack). Real down strums score ≥ 0.29 in 90% of
  /// synthetic cases, a chord merely ringing on stays below 0.3.
  final double downFreshness;

  /// ↑ strums hit strings that are still ringing hard from the ↓ just before,
  /// so they lift the spectrum less; a lower bar avoids missing them.
  final double upFreshness;

  /// Same for a single plucked note.
  final double noteFreshness;

  StrokeCheck check({
    required ChordDefinition chord,
    required PatternEventKind kind,
    int? stringNumber,
    required SpectrumFrame frame,
    List<double>? residual,
  }) {
    if (kind == PatternEventKind.mute || kind == PatternEventKind.pause) {
      return StrokeCheck.ok;
    }
    final feedback = matcher.evaluateFrame(
      chord: chord,
      frame: frame,
      referenceA4Hz: referenceA4Hz,
      residual: residual,
    );
    if (feedback.matchStatus == ChordMatchStatus.waiting) {
      return StrokeCheck.noFreshSound;
    }

    final active = feedback.activeStringFeedback;
    if (active.isEmpty) return StrokeCheck.wrongNotes;
    bool sounds(StringFeedback s) =>
        s.status == NoteStatus.detected || s.status == NoteStatus.weak;

    if (kind == PatternEventKind.finger) {
      final expected = _fingerNote(chord, stringNumber);
      if (expected == null) return StrokeCheck.wrongNotes;
      final fb = feedback.stringFeedback
          .where((s) => s.stringNumber == expected.string)
          .firstOrNull;
      if (fb == null || !sounds(fb)) return StrokeCheck.wrongNotes;
      if (feedback.extraNoteHz != null) return StrokeCheck.wrongNotes;
      if (!_isFresh(
        frame,
        residual,
        _upperPartials([_hz(expected.midi)]),
        // The thumb's bass note is the anchor of an arpeggio: same strict
        // bar as a ↓ strum. i/m/a notes ring over each other → lower bar.
        (stringNumber ?? 6) >= 4 ? downFreshness : noteFreshness,
      )) {
        return StrokeCheck.noFreshSound;
      }
      return StrokeCheck.ok;
    }

    // Strums.
    if (feedback.extraNoteHz != null) return StrokeCheck.wrongNotes;
    final down = kind != PatternEventKind.up;
    final sounding = active.where(sounds).toList();
    if (sounding.length < active.length - (down ? 1 : 2)) {
      return StrokeCheck.wrongNotes;
    }
    final soundingPcs = {
      for (final s in sounding)
        chord.noteForString(s.stringNumber)!.midi % 12,
    };
    if (!soundingPcs.containsAll(chord.pitchClasses)) {
      return StrokeCheck.wrongNotes;
    }
    if (down) {
      final bass = active.first; // ordered 6 → 1, so the lowest string
      if (!sounds(bass)) return StrokeCheck.wrongNotes;
    }

    final notes = [
      for (var s = 6; s >= 1; s--)
        if (!chord.isStringMuted(s) && chord.noteForString(s) != null)
          chord.noteForString(s)!,
    ];
    final fresh = down ? notes : notes.reversed.take(4).toList();
    if (!_isFresh(
      frame,
      residual,
      _upperPartials([for (final n in fresh) _hz(n.midi)]),
      down ? downFreshness : upFreshness,
    )) {
      return StrokeCheck.noFreshSound;
    }
    return StrokeCheck.ok;
  }

  /// Note a finger stroke should play: the chord's note on that string, or
  /// for the thumb (p) on a string the chord mutes, the chord's bass note.
  ChordNote? _fingerNote(ChordDefinition chord, int? stringNumber) {
    final s = stringNumber ?? 6;
    if (!chord.isStringMuted(s)) {
      final n = chord.noteForString(s);
      if (n != null) return n;
    }
    if (s >= 4) {
      for (var b = 6; b >= 1; b--) {
        if (!chord.isStringMuted(b) && chord.noteForString(b) != null) {
          return chord.noteForString(b);
        }
      }
    }
    return null;
  }

  /// 1st–6th harmonics of [fundamentals] (below 4 kHz).
  ///
  /// Upper partials of a string die out within a few hundred ms while the
  /// fundamental rings on, so a new pick/finger attack lifts them sharply
  /// even on a string that is still ringing (an ↑ right after a ↓), whereas a
  /// chord that is only ringing on has them steadily falling.
  List<double> _upperPartials(List<double> fundamentals) => [
        for (final f in fundamentals)
          for (final k in const [1, 2, 3, 4, 5, 6])
            if (f * k < 4000) f * k,
      ];

  double _hz(int midi) =>
      referenceA4Hz * pow(2, (midi - 69) / 12).toDouble();

  /// How much "new" sound appeared at [freqs]: mean of the positive
  /// log-magnitude rises from just before the strum to just after it.
  ///
  /// A chord that only rings on decays everywhere (score ≈ 0); a new attack
  /// lifts its partials (score clearly > 0), even on strings that were still
  /// ringing. Logs make it independent of volume; the noise floor keeps
  /// silent bins from producing random rises.
  static double freshness(
    SpectrumFrame frame,
    List<double> residual,
    List<double> freqs,
  ) {
    if (freqs.isEmpty) return 0;
    final floor = max(frame.noiseFloor * 3, frame.bandPeak * 0.003) + 1e-9;
    var sum = 0.0;
    for (final f in freqs) {
      final tol = max(frame.binHz * 1.6, f * 0.03);
      final after = frame.peakNear(f, tol)?.magnitude ?? 0;
      final lo = max(0, ((f - tol) / frame.binHz).floor());
      final hi = min(residual.length - 1, ((f + tol) / frame.binHz).ceil());
      var before = 0.0;
      for (var b = lo; b <= hi; b++) {
        before = max(before, residual[b]);
      }
      final rise = log(max(after, floor)) - log(max(before, floor));
      if (rise > 0) sum += rise;
    }
    return sum / freqs.length;
  }

  bool _isFresh(
    SpectrumFrame frame,
    List<double>? residual,
    List<double> freqs,
    double threshold,
  ) {
    if (residual == null) return true;
    return freshness(frame, residual, freqs) >= threshold;
  }
}
