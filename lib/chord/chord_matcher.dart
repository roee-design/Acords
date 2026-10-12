import 'dart:math';

import '../audio/fft_processor.dart';
import '../audio/frequency_utils.dart';
import '../audio/spectrum_frame.dart';
import '../models/chord_definition.dart';
import '../models/feedback_result.dart';

/// Compares one analysed frame to the expected chord and builds per-string
/// feedback.
///
/// Decisions are relative, not absolute:
/// * a chord note counts as present by its level relative to the strongest
///   component in the guitar band ([SpectrumFrame.bandPeak]) and the noise
///   floor, so the result does not depend on playing volume or mic gain;
/// * pitch is judged relative to the whole guitar's tuning offset (median of
///   the clearly present notes), so a guitar that is uniformly a few cents off
///   still matches while a single mis-fretted string does not;
/// * a clear spectral peak that no chord note (or its overtones) explains marks
///   the frame as "not this chord". Without this check every chord that
///   *contains* the target chord matched it (G7 → G, A → A5, C → Am7 …).
class ChordMatcher {
  ChordMatcher({
    required this.fftProcessor,
    this.strongRelativeDb = -26,
    this.weakRelativeDb = -36,
    this.extraNoteRelativeDb = -18,
    this.strongNoiseRatio = 6,
    this.weakNoiseRatio = 3,
    this.minimumDetectionInputLevel = 0.004,
    this.perfectCentsTolerance = 25,
    this.closeCentsTolerance = 55,
    this.wrongNoteCentsTolerance = 90,
    this.maxTuningShiftCents = 40,
  });

  final FftProcessor fftProcessor;

  /// Note level (vs the band peak) at or above which a string is "detected".
  final double strongRelativeDb;

  /// Note level at or above which a string is at least "weak".
  final double weakRelativeDb;

  /// Unexplained peaks at or above this level (vs band peak) reject the chord.
  final double extraNoteRelativeDb;

  final double strongNoiseRatio;
  final double weakNoiseRatio;

  /// RMS gate that rejects very quiet room noise before chord scoring begins.
  final double minimumDetectionInputLevel;

  final double perfectCentsTolerance;
  final double closeCentsTolerance;
  final double wrongNoteCentsTolerance;
  final double maxTuningShiftCents;

  static double _dbToRatio(double db) => pow(10, db / 20).toDouble();

  /// Legacy entry point: full-window magnitudes from [fftProcessor].
  ChordFeedback evaluate({
    required ChordDefinition chord,
    required List<double> magnitudes,
    required double referenceA4Hz,
    required double inputLevel,
  }) {
    return evaluateFrame(
      chord: chord,
      frame: SpectrumFrame(
        magnitudes: magnitudes,
        fftSize: fftProcessor.fftSize,
        sampleRate: fftProcessor.sampleRate,
        inputLevel: inputLevel,
      ),
      referenceA4Hz: referenceA4Hz,
    );
  }

  /// [residual]: spectrum captured just before the latest strum (same
  /// scale as [frame]). A peak that was already ringing then and has not grown
  /// is the previous chord dying away, not a note of this strum, so it does not
  /// count as a foreign note.
  ChordFeedback evaluateFrame({
    required ChordDefinition chord,
    required SpectrumFrame frame,
    required double referenceA4Hz,
    List<double>? residual,
  }) {
    final inputLevel = frame.inputLevel;
    if (inputLevel < minimumDetectionInputLevel || frame.bandPeak <= 0) {
      return _waitingFeedback(chord, inputLevel);
    }

    final strongLevel = max(
      frame.bandPeak * _dbToRatio(strongRelativeDb),
      frame.noiseFloor * strongNoiseRatio,
    );
    final weakLevel = max(
      frame.bandPeak * _dbToRatio(weakRelativeDb),
      frame.noiseFloor * weakNoiseRatio,
    );
    if (frame.bandPeak < frame.noiseFloor * strongNoiseRatio) {
      // Only hiss in the guitar band.
      return _waitingFeedback(chord, inputLevel);
    }

    final activeNotes = <ChordNote>[
      for (var s = 6; s >= 1; s--)
        if (!chord.isStringMuted(s) && chord.noteForString(s) != null)
          chord.noteForString(s)!,
    ];
    final fundamentals = {
      for (final n in activeNotes) n.string: midiToHz(n.midi, a4Hz: referenceA4Hz),
    };

    // --- 1. Per-note evidence --------------------------------------------
    final evidence = <int, _NoteEvidence>{};
    for (final note in activeNotes) {
      evidence[note.string] = _noteEvidence(
        frame,
        fundamentals[note.string]!,
        otherFundamentals: [
          for (final e in fundamentals.entries)
            if (e.key != note.string) e.value,
        ],
        weakLevel: weakLevel,
      );
    }

    // --- 2. Whole-guitar tuning offset -----------------------------------
    final confident = <double>[
      for (final e in evidence.values)
        if (e.level >= strongLevel &&
            e.cents != null &&
            e.cents!.abs() <= wrongNoteCentsTolerance)
          e.cents!,
    ]..sort();
    var shift = 0.0;
    if (confident.length >= 3) {
      shift = confident[confident.length ~/ 2]
          .clamp(-maxTuningShiftCents, maxTuningShiftCents)
          .toDouble();
    }

    // --- 3. Per-string status --------------------------------------------
    final stringFeedback = <StringFeedback>[];
    var activeStringCount = 0;
    var inTuneCount = 0;
    var closeCount = 0;

    for (var stringNumber = 6; stringNumber >= 1; stringNumber--) {
      final note = chord.isStringMuted(stringNumber)
          ? null
          : chord.noteForString(stringNumber);
      if (note == null) {
        stringFeedback.add(
          StringFeedback(
            stringNumber: stringNumber,
            stringLabel: stringLabel(stringNumber),
            expectedNote: '—',
            expectedHz: 0,
            status: NoteStatus.notInChord,
            energy: 0,
            message: chord.isStringMuted(stringNumber)
                ? 'אין לנגן במיתר זה באקורד ${chord.displayName}.'
                : 'מיתר זה לא בשימוש בצורת האקורד הזו.',
          ),
        );
        continue;
      }

      activeStringCount++;
      final ev = evidence[stringNumber]!;
      final cents = ev.cents;
      final relCents = cents == null ? double.infinity : (cents - shift).abs();

      final NoteStatus status;
      final String message;
      if (ev.level < weakLevel ||
          cents == null ||
          relCents > wrongNoteCentsTolerance) {
        status = NoteStatus.missing;
        message = _missingMessage(note);
      } else if (ev.level >= strongLevel && relCents <= perfectCentsTolerance) {
        status = NoteStatus.detected;
        inTuneCount++;
        closeCount++;
        message =
            'מיתר ${stringLabel(stringNumber)} מדויק (${note.noteName}, ${cents.abs().toStringAsFixed(0)} סנט).';
      } else if (relCents <= closeCentsTolerance) {
        status = NoteStatus.weak;
        closeCount++;
        message = ev.level >= strongLevel
            ? _closeMessage(note, cents - shift)
            : _weakMessage(note);
      } else {
        status = NoteStatus.weak;
        message = _closeMessage(note, cents - shift);
      }

      stringFeedback.add(
        StringFeedback(
          stringNumber: stringNumber,
          stringLabel: stringLabel(stringNumber),
          expectedNote: note.noteName,
          expectedHz: fundamentals[stringNumber]!,
          status: status,
          energy: ev.level,
          message: message,
          fret: note.fret,
          pitchCentsOffset: cents,
        ),
      );
    }

    // --- 4. Foreign notes -------------------------------------------------
    final extra = _strongestUnexplainedPeak(
      frame,
      fundamentals.values.toList(),
      shift,
      residual,
    );
    String? extraMessage;
    if (extra != null) {
      extraMessage = _extraNoteMessage(chord, extra.hz, referenceA4Hz);
    }

    var matchStatus = _resolveMatchStatus(
      activeStringCount: activeStringCount,
      inTuneCount: inTuneCount,
      closeCount: closeCount,
    );
    if (extra != null && matchStatus == ChordMatchStatus.perfect) {
      matchStatus = ChordMatchStatus.close;
    }

    return ChordFeedback(
      chordId: chord.id,
      chordName: chord.displayName,
      matchStatus: matchStatus,
      stringFeedback: stringFeedback,
      summary: _summaryForStatus(matchStatus),
      noiseFloor: frame.noiseFloor,
      inputLevel: inputLevel,
      extraNoteMessage: extraMessage,
      extraNoteHz: extra?.hz,
      tuningShiftCents: confident.length >= 3 ? shift : null,
    );
  }

  /// Strength and pitch of one expected note.
  ///
  /// Low strings reach a phone mic mostly through their overtones, so for
  /// notes below ~170 Hz the 2nd/3rd harmonics also count — but only when that
  /// harmonic is not itself another note of the chord, or when the fundamental
  /// is at least faintly present. Otherwise a missing C3 would be "found" in
  /// the C4 an octave up.
  _NoteEvidence _noteEvidence(
    SpectrumFrame frame,
    double hz, {
    required List<double> otherFundamentals,
    required double weakLevel,
  }) {
    final h1 = frame.peakNear(hz, _toleranceHz(frame, hz, 60));
    var level = h1?.magnitude ?? 0;
    double? cents = h1 == null ? null : _cents(h1.hz, hz);

    if (hz < 170) {
      final fundamentalPresent = level >= weakLevel * 0.5;
      for (final k in const [2, 3]) {
        final hk = hz * k;
        final peak = frame.peakNear(hk, _toleranceHz(frame, hk, 60));
        if (peak == null) continue;
        // "Shared" = another chord note (or one of its low overtones) sits on
        // this harmonic, so the peak proves nothing about this string.
        final shared = otherFundamentals.any((f) {
          for (var j = 1; j <= 4; j++) {
            if ((f * j - hk).abs() <= _toleranceHz(frame, hk, 50)) return true;
          }
          return false;
        });
        if (shared && !fundamentalPresent) continue;
        // Overtones of a bass string are naturally weaker than a mid string's
        // fundamental; scale so a healthy H2 counts like a fundamental.
        final scaled = peak.magnitude * (k == 2 ? 0.8 : 0.6);
        if (scaled > level) {
          level = scaled;
          final kc = _cents(peak.hz / k, hz);
          // Prefer the fundamental's reading when it is clearly there.
          if (h1 == null || h1.magnitude < weakLevel) cents = kc;
        }
      }
    }
    return _NoteEvidence(level: level, cents: cents);
  }

  SpectralPeak? _strongestUnexplainedPeak(
    SpectrumFrame frame,
    List<double> fundamentals,
    double shiftCents,
    List<double>? residual,
  ) {
    final minLevel = max(
      frame.bandPeak * _dbToRatio(extraNoteRelativeDb),
      frame.noiseFloor * strongNoiseRatio * 1.5,
    );
    final shiftRatio = pow(2, shiftCents / 1200).toDouble();
    for (final peak in frame.peaks) {
      if (peak.magnitude < minLevel) break; // sorted strongest first
      var explained = false;
      for (final f0 in fundamentals) {
        final f = f0 * shiftRatio;
        final k = (peak.hz / f).round();
        if (k < 1 || k > 14) continue;
        if ((peak.hz - k * f).abs() <= _toleranceHz(frame, k * f, 45)) {
          explained = true;
          break;
        }
      }
      if (!explained && residual != null) {
        var before = 0.0;
        for (var b = max(0, peak.bin - 1);
            b <= min(residual.length - 1, peak.bin + 1);
            b++) {
          before = max(before, residual[b]);
        }
        if (peak.magnitude <= before * 1.6) explained = true;
      }
      if (!explained) return peak;
    }
    return null;
  }

  double _toleranceHz(SpectrumFrame frame, double hz, double cents) {
    final byCents = hz * (pow(2, cents / 1200).toDouble() - 1);
    return max(byCents, frame.binHz * 1.6);
  }

  static double _cents(double measuredHz, double targetHz) =>
      1200 * log(measuredHz / targetHz) / ln2;

  String _extraNoteMessage(
    ChordDefinition chord,
    double hz,
    double referenceA4Hz,
  ) {
    // Name the muted string if the foreign note is (an octave of) its open
    // pitch — the most common beginner slip.
    const openMidi = {6: 40, 5: 45, 4: 50, 3: 55, 2: 59, 1: 64};
    for (var s = 6; s >= 1; s--) {
      if (!chord.isStringMuted(s)) continue;
      final open = midiToHz(openMidi[s]!, a4Hz: referenceA4Hz);
      for (final k in const [1, 2, 3]) {
        if ((_cents(hz, open * k)).abs() <= 40) {
          return 'המיתר ${_hebrewOrdinal(s)} מצלצל — באקורד ${chord.displayName} לא פורטים עליו.';
        }
      }
    }
    final midi = (69 + 12 * log(hz / referenceA4Hz) / ln2).round();
    final name = _noteNames[midi % 12];
    return 'נשמע צליל $name שלא שייך ל־${chord.displayName} — בדוק שכל אצבע על הסריג הנכון.';
  }

  static const _noteNames = [
    'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B',
  ];

  static String _hebrewOrdinal(int s) => switch (s) {
        1 => 'הראשון (הדק)',
        2 => 'השני',
        3 => 'השלישי',
        4 => 'הרביעי',
        5 => 'החמישי',
        6 => 'השישי (העבה)',
        _ => '$s',
      };

  ChordMatchStatus _resolveMatchStatus({
    required int activeStringCount,
    required int inTuneCount,
    required int closeCount,
  }) {
    if (activeStringCount == 0) {
      return ChordMatchStatus.notDetected;
    }
    if (inTuneCount == activeStringCount) {
      return ChordMatchStatus.perfect;
    }
    if (closeCount >= max(1, (activeStringCount / 2).ceil())) {
      return ChordMatchStatus.close;
    }
    return ChordMatchStatus.notDetected;
  }

  String _summaryForStatus(ChordMatchStatus status) {
    switch (status) {
      case ChordMatchStatus.perfect:
        return 'מושלם! 🎸';
      case ChordMatchStatus.close:
        return 'קרוב, תמשיך לנסות וכוונו את המיתרים';
      case ChordMatchStatus.notDetected:
        return 'לא זוהה אקורד';
      case ChordMatchStatus.waiting:
        return 'ממתין לצליל...';
    }
  }

  ChordFeedback _waitingFeedback(ChordDefinition chord, double inputLevel) {
    return _placeholderFeedback(
      chord,
      inputLevel: inputLevel,
      noteMessage: 'ממתין לנגינה…',
      summary: _summaryForStatus(ChordMatchStatus.waiting),
    );
  }

  ChordFeedback _placeholderFeedback(
    ChordDefinition chord, {
    required double inputLevel,
    required String noteMessage,
    required String summary,
  }) {
    final stringFeedback = <StringFeedback>[];
    for (var stringNumber = 6; stringNumber >= 1; stringNumber--) {
      if (chord.isStringMuted(stringNumber)) {
        stringFeedback.add(
          StringFeedback(
            stringNumber: stringNumber,
            stringLabel: stringLabel(stringNumber),
            expectedNote: '—',
            expectedHz: 0,
            status: NoteStatus.notInChord,
            energy: 0,
            message: 'לא באקורד זה.',
          ),
        );
        continue;
      }
      final note = chord.noteForString(stringNumber);
      stringFeedback.add(
        StringFeedback(
          stringNumber: stringNumber,
          stringLabel: stringLabel(stringNumber),
          expectedNote: note?.noteName ?? '—',
          expectedHz: note != null ? midiToHz(note.midi) : 0,
          status: NoteStatus.idle,
          energy: 0,
          message: noteMessage,
          fret: note?.fret,
        ),
      );
    }
    return ChordFeedback(
      chordId: chord.id,
      chordName: chord.displayName,
      matchStatus: ChordMatchStatus.waiting,
      stringFeedback: stringFeedback,
      summary: summary,
      noiseFloor: 0,
      inputLevel: inputLevel,
    );
  }

  String _missingMessage(ChordNote note) {
    final label = stringLabel(note.string);
    if (note.fret == 0) {
      return 'מיתר $label חסר — התו הפתוח ${note.noteName} לא נשמע.';
    }
    return 'מיתר $label חסר או מושתק (${note.noteName}, סריג ${note.fret}).';
  }

  String _weakMessage(ChordNote note) {
    final label = stringLabel(note.string);
    return 'מיתר $label נשמע חלש (${note.noteName}) — לחץ חזק יותר או בדוק את האצבעות.';
  }

  String _closeMessage(ChordNote note, double? centsOffset) {
    final label = stringLabel(note.string);
    if (centsOffset == null) {
      return 'מיתר $label קרוב (${note.noteName}) — כוון מעט את האצבע.';
    }
    final direction = centsOffset > 0 ? 'גבוה מדי' : 'נמוך מדי';
    return 'מיתר $label קרוב אבל $direction (${centsOffset.abs().toStringAsFixed(0)} סנט).';
  }

  /// Picks the best-matching chord from [chords] for free-play identification.
  ChordFeedback identifyBestChord({
    required List<ChordDefinition> chords,
    required List<double> magnitudes,
    required double referenceA4Hz,
    required double inputLevel,
  }) {
    return identifyBestChordFrame(
      chords: chords,
      frame: SpectrumFrame(
        magnitudes: magnitudes,
        fftSize: fftProcessor.fftSize,
        sampleRate: fftProcessor.sampleRate,
        inputLevel: inputLevel,
      ),
      referenceA4Hz: referenceA4Hz,
    );
  }

  ChordFeedback identifyBestChordFrame({
    required List<ChordDefinition> chords,
    required SpectrumFrame frame,
    required double referenceA4Hz,
    List<double>? residual,
  }) {
    if (frame.inputLevel < minimumDetectionInputLevel) {
      return freePlayWaiting(frame.inputLevel);
    }

    ChordFeedback? best;
    var bestScore = double.negativeInfinity;
    for (final chord in chords) {
      final feedback = evaluateFrame(
        chord: chord,
        frame: frame,
        referenceA4Hz: referenceA4Hz,
        residual: residual,
      );
      if (feedback.matchStatus == ChordMatchStatus.waiting) {
        return freePlayWaiting(frame.inputLevel);
      }
      final score = _matchScore(feedback);
      if (score > bestScore) {
        bestScore = score;
        best = feedback;
      }
    }
    return best ?? freePlayWaiting(frame.inputLevel);
  }

  double _matchScore(ChordFeedback feedback) {
    final statusScore = switch (feedback.matchStatus) {
      ChordMatchStatus.perfect => 400.0,
      ChordMatchStatus.close => 300.0,
      ChordMatchStatus.notDetected => 100.0,
      ChordMatchStatus.waiting => 0.0,
    };
    final active = feedback.activeStringFeedback;
    final detected =
        active.where((s) => s.status == NoteStatus.detected).length;
    // More matched strings = more specific voicing (E over E5); a foreign note
    // costs the equivalent of two strings.
    return statusScore +
        detected * 10 -
        (active.length - detected) * 4 -
        (feedback.extraNoteHz != null ? 20 : 0);
  }

  /// Waiting state for free-play mode before audio is detected.
  ChordFeedback freePlayWaiting(double inputLevel) {
    return ChordFeedback(
      chordId: '',
      chordName: '?',
      matchStatus: ChordMatchStatus.waiting,
      stringFeedback: const [],
      summary: 'נגן אקורד…',
      noiseFloor: 0,
      inputLevel: inputLevel,
    );
  }

  /// Idle placeholder before listening starts.
  ChordFeedback idleFeedback(ChordDefinition chord) {
    return _placeholderFeedback(
      chord,
      inputLevel: 0,
      noteMessage: 'בחר אקורד ולחץ "התחל האזנה".',
      summary: 'בחר אקורד ולחץ "התחל האזנה".',
    );
  }
}

class _NoteEvidence {
  const _NoteEvidence({required this.level, required this.cents});

  final double level;
  final double? cents;
}
