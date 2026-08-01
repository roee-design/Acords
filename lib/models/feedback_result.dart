/// Overall chord recognition state shown in the summary banner.
enum ChordMatchStatus {
  /// Mic is on but input is too quiet to analyze.
  waiting,

  /// Audible input but no meaningful match to the target chord.
  notDetected,

  /// Some strings are close; tuning or fingering still needs work.
  close,

  /// All active strings match their target frequencies within tolerance.
  perfect,
}

enum NoteStatus {
  /// String should ring but energy is below detection threshold.
  missing,

  /// Partial energy — finger pressure or position issue.
  weak,

  /// Fundamental + harmonics exceed threshold.
  detected,

  /// String is not part of this chord voicing (x in fingering).
  notInChord,

  /// Waiting for user to start listening.
  idle,
}

class StringFeedback {
  const StringFeedback({
    required this.stringNumber,
    required this.stringLabel,
    required this.expectedNote,
    required this.expectedHz,
    required this.status,
    required this.energy,
    required this.message,
    this.fret,
    this.pitchCentsOffset,
  });

  final int stringNumber;
  final String stringLabel;
  final String expectedNote;
  final double expectedHz;
  final NoteStatus status;
  final double energy;
  final String message;
  final int? fret;

  /// Signed cents deviation of the detected peak from [expectedHz]. Null if no peak.
  final double? pitchCentsOffset;

  bool get isIssue =>
      status == NoteStatus.missing || status == NoteStatus.weak;
}

class ChordFeedback {
  const ChordFeedback({
    required this.chordId,
    required this.chordName,
    required this.matchStatus,
    required this.stringFeedback,
    required this.summary,
    required this.noiseFloor,
    required this.inputLevel,
  });

  final String chordId;
  final String chordName;
  final ChordMatchStatus matchStatus;

  bool get isPerfect => matchStatus == ChordMatchStatus.perfect;

  /// One entry per guitar string (6 → 1), including muted strings.
  final List<StringFeedback> stringFeedback;
  final String summary;
  final double noiseFloor;

  /// RMS of the last analyzed frame (0–1) for UI level meter.
  final double inputLevel;

  List<StringFeedback> get activeStringFeedback => stringFeedback
      .where((s) => s.status != NoteStatus.notInChord)
      .toList();

  List<StringFeedback> get issues =>
      stringFeedback.where((s) => s.isIssue).toList();

  /// Average signed cents deviation across active strings with pitch data.
  double? get averageCentsOffset {
    final offsets = stringFeedback
        .where(
          (s) =>
              s.pitchCentsOffset != null &&
              s.status != NoteStatus.notInChord &&
              s.status != NoteStatus.idle,
        )
        .map((s) => s.pitchCentsOffset!)
        .toList();
    if (offsets.isEmpty) {
      return null;
    }
    return offsets.reduce((a, b) => a + b) / offsets.length;
  }
}
