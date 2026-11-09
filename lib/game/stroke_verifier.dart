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

  /// Chord tones missing or foreign notes present — e.g. strumming open
  /// strings without holding the chord.
  wrongNotes,

  /// Nothing new was played: the "strum" was noise or the previous chord
  /// ringing on.
  noFreshSound,
}

/// Checks *what* a strum or pluck contained, not only when it happened.
///
/// The rules were set against a simulation of real playing through phone
/// microphones (`test/bench/mic_deviation_bench_test.dart`): partial strums,
/// weak bass, room reverb, automatic gain, a guitar a few cents off.
///
/// * ↓ strum — no foreign note, every pitch class of the chord sounds, at
///   most two strings missing, the chord's partials clearly rose, and
///   strings of at least two different notes were freshly struck.
/// * ↑ strum — no foreign note, every pitch class of the chord sounds (the
///   ↓ before it is still ringing), and at least one of the thin strings was
///   freshly struck.
/// * finger note (p/i/m/a) — the expected string's note was freshly plucked
///   and nothing foreign rings.
/// * ✕ mute — percussive, nothing to check.
///
/// What is deliberately *not* required, because a phone cannot hear it:
/// * the chord's bass string — phone mics roll off below ~120–250 Hz and the
///   bass of most open chords is doubled an octave up, so its absence cannot
///   be told from its presence;
/// * silence on an open string below the chord that belongs to the chord
///   (low E under C or Am, A under D): a common, consonant slip.
///
/// Every accepted stroke is also graded [lastStrong]: a strong stroke proves
/// that someone is playing; a weak one (a soft ↑ over a ringing chord looks
/// much like the chord just ringing) only counts shortly after a strong one —
/// see `GuitarStrokeReferee`.
class StrokeVerifier {
  StrokeVerifier(
    this.matcher, {
    this.referenceA4Hz = 440,
    this.downFreshness = 0.26,
    this.upFreshness = 0.15,
    this.upStrongFreshness = 0.45,
    this.noteFreshness = 0.15,
    this.noteStrongFreshness = 0.30,
    this.minRisenPartials = 2,
    this.notePitchCents = 55,
  });

  final ChordMatcher matcher;
  final double referenceA4Hz;

  /// Minimum [freshness] of a ↓ strum over all the chord's partials.
  final double downFreshness;

  /// ↑ strums: freshness of the best of the four thin strings. Weak / strong.
  final double upFreshness;
  final double upStrongFreshness;

  /// How far off pitch a finger note may be.
  final double notePitchCents;

  /// Partials of a string (of its first six) that must rise for it to count
  /// as struck.
  final int minRisenPartials;

  /// Finger notes: freshness of the expected note's partials. Weak / strong.
  final double noteFreshness;
  final double noteStrongFreshness;

  /// Why the last [check] decided what it did (diagnostics), e.g.
  /// `chord tone missing (s4 E3 missing)` or `fresh 0.08 < 0.26`.
  String lastDetail = '';

  /// Freshness score computed by the last [check], if it got that far.
  double? lastFreshness;

  /// True when the last accepted stroke was unmistakably a new attack.
  bool lastStrong = false;

  StrokeCheck _verdict(StrokeCheck result, String detail) {
    lastDetail = detail;
    return result;
  }

  StrokeCheck check({
    required ChordDefinition chord,
    required PatternEventKind kind,
    int? stringNumber,
    required SpectrumFrame frame,
    List<double>? residual,
  }) {
    lastFreshness = null;
    lastStrong = false;
    if (kind == PatternEventKind.mute || kind == PatternEventKind.pause) {
      return _verdict(StrokeCheck.ok, 'percussive stroke, not checked');
    }
    final feedback = matcher.evaluateFrame(
      chord: chord,
      frame: frame,
      referenceA4Hz: referenceA4Hz,
      residual: residual,
      allowedExtraHz: _consonantOpenStrings(chord),
      residualGrowth: 1.15,
    );
    if (feedback.matchStatus == ChordMatchStatus.waiting) {
      return _verdict(
        StrokeCheck.noFreshSound,
        'too quiet (rms ${frame.inputLevel.toStringAsFixed(4)})',
      );
    }

    final active = feedback.activeStringFeedback;
    if (active.isEmpty) return _verdict(StrokeCheck.wrongNotes, 'no strings');
    bool sounds(StringFeedback s) =>
        s.status == NoteStatus.detected || s.status == NoteStatus.weak;
    String describe(StringFeedback s) =>
        's${s.stringNumber} ${s.expectedNote} ${s.status.name}';
    final extra = feedback.extraNoteHz;

    if (kind == PatternEventKind.finger) {
      final expected = _fingerNote(chord, stringNumber);
      if (expected == null) {
        return _verdict(StrokeCheck.wrongNotes, 'no note for string $stringNumber');
      }
      final hz = _hz(expected.midi);
      final fb = feedback.stringFeedback
          .where((s) => s.stringNumber == expected.string)
          .firstOrNull;
      // The expected string itself must have been plucked: several of its
      // own partials rose together. One shared overtone of another string
      // (the 3rd harmonic of an open A is the E of string 1) is not enough.
      final excited = _excitation(frame, residual, hz);
      final plucked = excited.fresh &&
          // Below ~170 Hz the octave above looks the same on a weak-bass mic
          // except for the odd partials.
          (hz >= 170 || excited.odd);
      // A single note is judged on a tighter pitch than a string inside a
      // strum (±55 cents instead of ±90): a voice or a TV near the phone
      // sweeps through pitches and would otherwise pass for the note.
      final inTune = fb != null &&
          sounds(fb) &&
          (fb.pitchCentsOffset?.abs() ?? double.infinity) <= notePitchCents;
      // …or, for a bass note the phone cannot hear directly, most of its
      // overtone series appeared at once. (Two shared overtones are not
      // enough: a note a fifth higher has exactly two.)
      final heard = inTune || (excited.count >= 4 && excited.odd);
      if (!heard) {
        return _verdict(
          StrokeCheck.wrongNotes,
          'expected note missing (${fb == null ? 's${expected.string}' : describe(fb)})',
        );
      }
      if (extra != null) {
        return _verdict(StrokeCheck.wrongNotes, 'foreign note ${extra.round()}Hz');
      }
      final score = _score(frame, residual, _partials([hz]));
      lastFreshness = score;
      if (score < noteFreshness || !plucked) {
        return _verdict(
          StrokeCheck.noFreshSound,
          plucked
              ? 'fresh ${score.toStringAsFixed(3)} < $noteFreshness'
              : 'string not plucked (${excited.count} partials rose)',
        );
      }
      lastStrong = score >= noteStrongFreshness;
      return _verdict(
        StrokeCheck.ok,
        's${expected.string} ${expected.noteName} fresh ${score.toStringAsFixed(3)}'
            '${lastStrong ? ' (strong)' : ''}',
      );
    }

    // Strums.
    if (extra != null) {
      return _verdict(StrokeCheck.wrongNotes, 'foreign note ${extra.round()}Hz');
    }
    final down = kind != PatternEventKind.up;
    final sounding = active.where(sounds).toList();
    final missing = [for (final s in active) if (!sounds(s)) describe(s)];
    final neededStrings = down ? max(2, active.length - 2) : min(2, active.length);
    if (sounding.length < neededStrings) {
      return _verdict(
        StrokeCheck.wrongNotes,
        'too many strings missing (${missing.join(', ')})',
      );
    }
    final soundingPcs = {
      for (final s in sounding)
        chord.noteForString(s.stringNumber)!.midi % 12,
    };
    final chordPcs = chord.pitchClasses;
    // Also for an ↑: it only strikes the thin strings, but the rest of the
    // chord is still ringing from the ↓ before it. (Open strings without a
    // chord, or a neighbouring chord, lack one of the chord's notes.)
    final neededPcs = chordPcs.length;
    if (soundingPcs.length < neededPcs) {
      return _verdict(
        StrokeCheck.wrongNotes,
        'chord tone missing (${missing.join(', ')})',
      );
    }

    final notes = [
      for (var s = 6; s >= 1; s--)
        if (!chord.isStringMuted(s) && chord.noteForString(s) != null)
          chord.noteForString(s)!,
    ];
    if (down) {
      final score = _score(
        frame,
        residual,
        _partials([for (final n in notes) _hz(n.midi)]),
      );
      lastFreshness = score;
      if (score < downFreshness) {
        return _verdict(
          StrokeCheck.noFreshSound,
          'fresh ${score.toStringAsFixed(3)} < $downFreshness',
        );
      }
      // A strum, not one plucked string: freshly struck strings of at least
      // two different notes (one string also lifts its octaves).
      final freshPcs = <int>{
        for (final n in notes)
          if (_excitation(frame, residual, _hz(n.midi)).fresh) n.midi % 12,
      };
      final neededFresh = min(2, chordPcs.length);
      if (freshPcs.length < neededFresh) {
        return _verdict(
          StrokeCheck.noFreshSound,
          'only ${freshPcs.length} freshly struck notes < $neededFresh',
        );
      }
      lastStrong = true;
    } else {
      // An ↑ reaches two to four thin strings: grade the freshest of them.
      var score = 0.0;
      for (final n in notes.reversed.take(4)) {
        if (!_excitation(frame, residual, _hz(n.midi)).fresh) continue;
        score = max(score, _score(frame, residual, _partials([_hz(n.midi)])));
      }
      lastFreshness = score;
      if (score < upFreshness) {
        return _verdict(
          StrokeCheck.noFreshSound,
          'fresh ${score.toStringAsFixed(3)} < $upFreshness',
        );
      }
      lastStrong = score >= upStrongFreshness;
    }
    return _verdict(
      StrokeCheck.ok,
      '${sounding.length}/${active.length} strings, fresh '
          '${lastFreshness!.toStringAsFixed(3)}${lastStrong ? ' (strong)' : ''}',
    );
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

  static const _openMidi = {6: 40, 5: 45, 4: 50, 3: 55, 2: 59, 1: 64};

  /// Open strings the chord shape mutes but whose note belongs to the chord
  /// (C/E, Am/E, D/A …): catching one in a strum is not a wrong chord.
  List<double> _consonantOpenStrings(ChordDefinition chord) {
    final pcs = chord.pitchClasses;
    return [
      for (var s = 6; s >= 1; s--)
        if (chord.isStringMuted(s) && pcs.contains(_openMidi[s]! % 12))
          _hz(_openMidi[s]!),
    ];
  }

  /// Whether the string sounding [hz] was itself struck: how many of its
  /// first six partials rose clearly (≥ 30 %) across the attack.
  ///
  /// `fresh`: at least three rose, one of them the 1st or 2nd — a single
  /// partial shared with another string does not qualify. `odd`: the 1st, 3rd
  /// or 5th rose, which the same note an octave up cannot produce.
  ({bool fresh, bool odd, int count}) _excitation(
    SpectrumFrame frame,
    List<double>? residual,
    double hz,
  ) {
    if (residual == null) return (fresh: true, odd: true, count: 6);
    final level = frame.bandPeak * 0.01; // −40 dB of the strongest component
    var count = 0;
    var odd = false;
    for (var k = 1; k <= 6; k++) {
      final f = hz * k;
      if (f >= 4000) break;
      final tol = max(frame.binHz * 1.6, f * 0.03);
      final after = frame.peakNear(f, tol)?.magnitude ?? 0;
      if (after < level) continue;
      if (after < 1.3 * _peakIn(residual, frame.binHz, f, tol)) continue;
      count++;
      if (k.isOdd) odd = true;
    }
    return (fresh: count >= minRisenPartials, odd: odd, count: count);
  }

  /// 1st–6th harmonics of [fundamentals] (below 4 kHz).
  List<double> _partials(List<double> fundamentals) => [
        for (final f in fundamentals)
          for (var k = 1; k <= 6; k++)
            if (f * k < 4000) f * k,
      ];

  double _hz(int midi) =>
      referenceA4Hz * pow(2, (midi - 69) / 12).toDouble();

  static double _peakIn(List<double> spectrum, double binHz, double f, double tol) {
    final lo = max(0, ((f - tol) / binHz).floor());
    final hi = min(spectrum.length - 1, ((f + tol) / binHz).ceil());
    var peak = 0.0;
    for (var b = lo; b <= hi; b++) {
      peak = max(peak, spectrum[b]);
    }
    return peak;
  }

  /// How much "new" sound appeared at [freqs]: mean of the positive
  /// log-magnitude rises from just before the stroke to just after it.
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
      final before = _peakIn(residual, frame.binHz, f, tol);
      final rise = log(max(after, floor)) - log(max(before, floor));
      if (rise > 0) sum += rise;
    }
    return sum / freqs.length;
  }

  /// How clearly a capture is a new stroke of *anything* (no chord needed):
  /// [freshness] over its twelve strongest spectral peaks. Used by the mic
  /// calibration, where the player may strum whatever they like. A real
  /// strum scores around 1; a ringing chord "breathing" stays below ~0.3.
  static double attackStrength(SpectrumFrame frame, List<double>? residual) {
    if (residual == null) return 1;
    final peaks = frame.peaks;
    if (peaks.isEmpty) return 0;
    return freshness(frame, residual, [for (final p in peaks.take(12)) p.hz]);
  }

  /// [freshness], or a clearly-fresh score when there is no "before" (the
  /// very first stroke of a session).
  double _score(SpectrumFrame frame, List<double>? residual, List<double> freqs) =>
      residual == null ? 1.0 : freshness(frame, residual, freqs);
}
