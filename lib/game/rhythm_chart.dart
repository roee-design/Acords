import '../models/song_definition.dart';
import '../models/strumming_pattern.dart';

/// One stroke the player must hit.
class RhythmNote {
  RhythmNote({
    required this.index,
    required this.timeMs,
    required this.kind,
    required this.barIndex,
    this.stringNumber,
    this.fingerLabel,
  });

  final int index;

  /// Time from chart start (first bar = 0).
  final double timeMs;
  final PatternEventKind kind;
  final int barIndex;
  final int? stringNumber;
  final String? fingerLabel;

  bool get isDown => kind == PatternEventKind.down;
  bool get isUp => kind == PatternEventKind.up;
}

/// One bar: the chord to hold (and, in song mode, the lyrics sung over it).
class RhythmBar {
  const RhythmBar({
    required this.index,
    required this.startMs,
    required this.endMs,
    required this.chordId,
    this.lyrics = '',
    this.lineIndex,
    this.segmentIndex,
  });

  final int index;
  final double startMs;
  final double endMs;
  final String chordId;
  final String lyrics;

  /// Song line / segment this bar belongs to (song mode).
  final int? lineIndex;
  final int? segmentIndex;
}

/// Timed notes + bars for one game run.
///
/// Each bar plays the pattern once; a pattern shorter than a bar (e.g. half a
/// bar of arpeggio) repeats to fill it. Rests become gaps — strumming there
/// counts as an extra stroke.
class RhythmChart {
  RhythmChart._({
    required this.notes,
    required this.bars,
    required this.bpm,
    required this.pattern,
    required this.slotMs,
    required this.song,
  });

  final List<RhythmNote> notes;
  final List<RhythmBar> bars;
  final int bpm;
  final StrummingPattern pattern;
  final double slotMs;
  final SongDefinition? song;

  double get beatMs => 60000.0 / bpm;
  double get barMs => slotMs * pattern.slotsPerBar;
  double get durationMs => bars.isEmpty ? 0 : bars.last.endMs;

  /// Bar containing [timeMs] (clamped), or null before/after the chart.
  RhythmBar? barAt(double timeMs) {
    if (bars.isEmpty || timeMs < 0 || timeMs >= durationMs) return null;
    final i = (timeMs / barMs).floor().clamp(0, bars.length - 1);
    return bars[i];
  }

  /// Practice run: [chordIds] in order, each for one bar, repeated [rounds]×.
  factory RhythmChart.forPattern({
    required StrummingPattern pattern,
    required List<String> chordIds,
    required int bpm,
    int rounds = 2,
  }) {
    final chords = [
      for (var r = 0; r < rounds; r++) ...chordIds,
    ];
    return RhythmChart._build(
      pattern: pattern,
      bpm: bpm,
      bars: [for (final c in chords) (c, '', null, null)],
      song: null,
    );
  }

  /// Song run: one bar per chord segment, with its lyrics.
  factory RhythmChart.forSong({
    required SongDefinition song,
    required StrummingPattern pattern,
    required int bpm,
  }) {
    final bars = <(String, String, int?, int?)>[];
    for (var li = 0; li < song.lines.length; li++) {
      final line = song.lines[li];
      for (var si = 0; si < line.segments.length; si++) {
        final seg = line.segments[si];
        final id = seg.chordId;
        if (id == null || id.isEmpty) continue;
        bars.add((id, seg.lyrics, li, si));
      }
    }
    return RhythmChart._build(
      pattern: pattern,
      bpm: bpm,
      bars: bars,
      song: song,
    );
  }

  factory RhythmChart._build({
    required StrummingPattern pattern,
    required int bpm,
    required List<(String, String, int?, int?)> bars,
    required SongDefinition? song,
  }) {
    final slotMs = 60000.0 / bpm / pattern.subdivision;
    final slotsPerBar = pattern.slotsPerBar;
    final barMs = slotMs * slotsPerBar;
    final events = pattern.events;
    final notes = <RhythmNote>[];
    final outBars = <RhythmBar>[];
    for (var b = 0; b < bars.length; b++) {
      final start = b * barMs;
      outBars.add(
        RhythmBar(
          index: b,
          startMs: start,
          endMs: start + barMs,
          chordId: bars[b].$1,
          lyrics: bars[b].$2,
          lineIndex: bars[b].$3,
          segmentIndex: bars[b].$4,
        ),
      );
      if (events.isEmpty) continue;
      for (var slot = 0; slot < slotsPerBar; slot++) {
        final e = events[slot % events.length];
        if (!e.isSounding) continue;
        notes.add(
          RhythmNote(
            index: notes.length,
            timeMs: start + slot * slotMs,
            kind: e.kind,
            barIndex: b,
            stringNumber: e.stringNumber,
            fingerLabel: e.fingerLabel,
          ),
        );
      }
    }
    return RhythmChart._(
      notes: notes,
      bars: outBars,
      bpm: bpm,
      pattern: pattern,
      slotMs: slotMs,
      song: song,
    );
  }
}
