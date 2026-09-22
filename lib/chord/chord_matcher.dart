import 'dart:math';
import '../audio/fft_processor.dart';
import '../audio/frequency_utils.dart';
import '../models/chord_definition.dart';
import '../models/feedback_result.dart';

/// Compares live FFT magnitudes to the expected chord profile and builds

/// per-string feedback messages.

class ChordMatcher {

  ChordMatcher({
    required this.fftProcessor,
    this.weakRatio = 0.65,
    this.missingRatio = 0.35,
    this.harmonicWeights = const [1.0, 0.65, 0.35, 0.2],
    this.noiseFloorMultiplier = 14.0,
    this.minimumStrongThreshold = 0.004,
    this.inputLevelScale = 0.3,
    this.silenceInputLevel = 0.008,
    this.minimumDetectionInputLevel = 0.012,
    this.perfectCentsTolerance = 25,
    this.closeCentsTolerance = 55,
    this.wrongNoteCentsTolerance = 90,
  });
  final FftProcessor fftProcessor;
  final double weakRatio;
  final double missingRatio;
  final List<double> harmonicWeights;
  final double noiseFloorMultiplier;
  final double minimumStrongThreshold;
  final double inputLevelScale;
  final double silenceInputLevel;
  /// RMS gate that rejects very quiet room noise before chord scoring begins.
  final double minimumDetectionInputLevel;
  final double perfectCentsTolerance;
  final double closeCentsTolerance;
  final double wrongNoteCentsTolerance;

  ChordFeedback evaluate({
    required ChordDefinition chord,
    required List<double> magnitudes,
    required double referenceA4Hz,
    required double inputLevel,
  }) {
    if (inputLevel < _requiredInputLevel) {
      return _waitingFeedback(chord, inputLevel);
    }
    final noiseFloor = fftProcessor.estimateNoiseFloor(magnitudes);
    final strongThreshold = max(
      max(noiseFloor * noiseFloorMultiplier, inputLevel * inputLevelScale),
      minimumStrongThreshold,
    );
    final stringFeedback = <StringFeedback>[];
    var activeStringCount = 0;
    var inTuneCount = 0;
    var closeCount = 0;
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
            message: 'אין לנגן במיתר זה באקורד ${chord.displayName}.',
            fret: null,
          ),
        );
        continue;
      }
      final note = chord.noteForString(stringNumber);
      if (note == null) {
        stringFeedback.add(
          StringFeedback(
            stringNumber: stringNumber,
            stringLabel: stringLabel(stringNumber),
            expectedNote: '—',
            expectedHz: 0,
            status: NoteStatus.notInChord,
            energy: 0,
            message: 'מיתר זה לא בשימוש בצורת האקורד הזו.',
            fret: null,
          ),
        );
        continue;
      }
      activeStringCount++;
      final expectedHz = midiToHz(note.midi, a4Hz: referenceA4Hz);
      // Phone mics + FFT bin width (~5.4 Hz) make low E (~82 Hz) ≈1 bin ≈100¢ —
      // fixed 25¢ "perfect" is unrealistically hard for open E / Em bass notes.
      final perfectCents = _perfectCentsToleranceFor(expectedHz);
      final closeCents = _closeCentsToleranceFor(expectedHz);
      final wrongCents = _wrongNoteCentsToleranceFor(expectedHz);
      final noteStrongThreshold =
          strongThreshold * _energyThresholdScaleFor(expectedHz);
      final noteWeakThreshold = noteStrongThreshold * weakRatio;
      final noteMissingThreshold = noteStrongThreshold * missingRatio;
      final profile = TargetFrequencyProfile(
        fundamentalHz: expectedHz,
        harmonicWeights: _harmonicWeightsFor(expectedHz),
      );
      final energy = profile.score(
        magnitudes,
        fftProcessor.fftSize,
        fftProcessor.sampleRate,
      );
      final peakEnergy = profile.peakEnergy(
        magnitudes,
        fftProcessor.fftSize,
        fftProcessor.sampleRate,
      );
      final centsOffset = profile.estimatePitchCentsOffset(
        magnitudes,
        fftProcessor.fftSize,
        fftProcessor.sampleRate,
      );
      final absCents = centsOffset?.abs() ?? double.infinity;
      final NoteStatus status;
      final String message;
      if (peakEnergy < noteMissingThreshold ||
          absCents > wrongCents ||
          energy < noteMissingThreshold) {
        status = NoteStatus.missing;
        message = _missingMessage(note);
      } else if (energy >= noteStrongThreshold && absCents <= perfectCents) {
        status = NoteStatus.detected;
        inTuneCount++;
        closeCount++;
        message =
            'מיתר ${stringLabel(stringNumber)} מדויק (${note.noteName}, ${absCents.toStringAsFixed(0)} סנט).';
      } else if (energy >= noteWeakThreshold && absCents <= closeCents) {
        status = NoteStatus.weak;
        closeCount++;
        message = _closeMessage(note, centsOffset);
      } else if (energy >= noteWeakThreshold) {
        status = NoteStatus.weak;
        message = _weakMessage(note);
      } else {
        status = NoteStatus.missing;
        message = _missingMessage(note);
      }
      stringFeedback.add(
        StringFeedback(
          stringNumber: stringNumber,
          stringLabel: stringLabel(stringNumber),
          expectedNote: note.noteName,
          expectedHz: expectedHz,
          status: status,
          energy: energy,
          message: message,
          fret: note.fret,
          pitchCentsOffset: centsOffset,
        ),
      );
    }
    final matchStatus = _resolveMatchStatus(
      chord: chord,
      stringFeedback: stringFeedback,
      activeStringCount: activeStringCount,
      inTuneCount: inTuneCount,
      closeCount: closeCount,
    );
    return ChordFeedback(
      chordId: chord.id,
      chordName: chord.displayName,
      matchStatus: matchStatus,
      stringFeedback: stringFeedback,
      summary: _summaryForStatus(matchStatus),
      noiseFloor: noiseFloor,
      inputLevel: inputLevel,
    );
  }

  ChordMatchStatus _resolveMatchStatus({
    required ChordDefinition chord,
    required List<StringFeedback> stringFeedback,
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

    // Open E (and similar 6-string shapes): allow one weak low bass string when
    // every other active string is in tune and all strings are at least close.
    if (_isBassHeavyOpenShape(chord) &&
        closeCount == activeStringCount &&
        inTuneCount >= activeStringCount - 1) {
      final softBass = stringFeedback.where(
        (s) =>
            s.status == NoteStatus.weak &&
            s.expectedHz > 0 &&
            s.expectedHz < 130,
      );
      if (softBass.length == 1) {
        return ChordMatchStatus.perfect;
      }
    }

    if (closeCount >= max(1, (activeStringCount / 2).ceil())) {
      return ChordMatchStatus.close;
    }
    return ChordMatchStatus.notDetected;
  }

  /// Full 6-string open shapes anchored on low E (E, Em, E7…) are the hardest
  /// for phone mics because of E2 / octave doubling.
  bool _isBassHeavyOpenShape(ChordDefinition chord) {
    if (chord.notes.length < 6) return false;
    final lowE = chord.noteForString(6);
    return lowE != null && lowE.midi <= 40;
  }

  /// Wider cents windows for low fundamentals (FFT bin ≈ 5.4 Hz).
  double _perfectCentsToleranceFor(double hz) {
    if (hz < 100) return 110;
    if (hz < 140) return 70;
    if (hz < 200) return 45;
    return perfectCentsTolerance;
  }

  double _closeCentsToleranceFor(double hz) {
    if (hz < 100) return 160;
    if (hz < 140) return 110;
    if (hz < 200) return 70;
    return closeCentsTolerance;
  }

  double _wrongNoteCentsToleranceFor(double hz) {
    if (hz < 100) return 200;
    if (hz < 140) return 140;
    return wrongNoteCentsTolerance;
  }

  /// Favor H2/H3 on bass notes — phone mics often miss the fundamental.
  List<double> _harmonicWeightsFor(double hz) {
    if (hz < 100) return const [0.45, 1.0, 0.75, 0.4];
    if (hz < 140) return const [0.7, 0.95, 0.55, 0.3];
    return harmonicWeights;
  }

  double _energyThresholdScaleFor(double hz) {
    if (hz < 100) return 0.55;
    if (hz < 140) return 0.72;
    return 1.0;
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
            fret: null,
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
          message: 'ממתין לנגינה…',
          fret: note?.fret,
        ),
      );
    }
    return ChordFeedback(
      chordId: chord.id,
      chordName: chord.displayName,
      matchStatus: ChordMatchStatus.waiting,
      stringFeedback: stringFeedback,
      summary: _summaryForStatus(ChordMatchStatus.waiting),
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
    if (inputLevel < _requiredInputLevel) {
      return freePlayWaiting(inputLevel);
    }
    ChordFeedback? best;
    var bestScore = -1;
    for (final chord in chords) {
      final feedback = evaluate(
        chord: chord,
        magnitudes: magnitudes,
        referenceA4Hz: referenceA4Hz,
        inputLevel: inputLevel,
      );
      final score = _matchScore(feedback);
      if (score > bestScore) {
        bestScore = score;
        best = feedback;
      }
    }
    return best ?? freePlayWaiting(inputLevel);
  }

  int _matchScore(ChordFeedback feedback) {
    final statusScore = switch (feedback.matchStatus) {
      ChordMatchStatus.perfect => 400,
      ChordMatchStatus.close => 300,
      ChordMatchStatus.notDetected => 100,
      ChordMatchStatus.waiting => 0,
    };
    final detected = feedback.stringFeedback
        .where((s) => s.status == NoteStatus.detected)
        .length;
    return statusScore + detected * 10;
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
            fret: null,
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
          message: 'בחר אקורד ולחץ "התחל האזנה".',
          fret: note?.fret,
        ),
      );
    }
    return ChordFeedback(
      chordId: chord.id,
      chordName: chord.displayName,
      matchStatus: ChordMatchStatus.waiting,
      stringFeedback: stringFeedback,
      summary: 'בחר אקורד ולחץ "התחל האזנה".',
      noiseFloor: 0,
      inputLevel: 0,
    );
  }
  double get _requiredInputLevel => max(silenceInputLevel, minimumDetectionInputLevel);
}
