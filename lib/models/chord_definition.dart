class GuitarStringTuning {
  const GuitarStringTuning({
    required this.index,
    required this.name,
    required this.openMidi,
  });

  final int index;
  final String name;
  final int openMidi;

  factory GuitarStringTuning.fromJson(Map<String, dynamic> json) {
    return GuitarStringTuning(
      index: json['index'] as int,
      name: json['name'] as String,
      openMidi: json['openMidi'] as int,
    );
  }
}

class ChordNote {
  const ChordNote({
    required this.string,
    required this.fret,
    required this.noteName,
    required this.midi,
    this.finger,
  });

  /// String number: 6 = low E, 1 = high E.
  final int string;
  final int fret;
  final String noteName;
  final int midi;

  /// Fretting finger: 1=index, 2=middle, 3=ring, 4=pinky. Null for open.
  final int? finger;

  factory ChordNote.fromJson(Map<String, dynamic> json) {
    return ChordNote(
      string: json['string'] as int,
      fret: json['fret'] as int,
      noteName: json['noteName'] as String,
      midi: json['midi'] as int,
      finger: (json['finger'] as num?)?.toInt(),
    );
  }
}

/// Difficulty / technique labels used across library + practice filters.
class ChordDifficultyLevels {
  ChordDifficultyLevels._();

  static const int min = 1;
  static const int max = 5;

  static const Map<int, String> shortLabels = {
    1: 'רמה 1',
    2: 'רמה 2',
    3: 'רמה 3',
    4: 'רמה 4',
    5: 'רמה 5',
  };

  static const Map<int, String> categories = {
    1: 'אקורדים פתוחים בסיסיים',
    2: 'פתוחים מתקדמים ושביעיות',
    3: 'אקורדי בארה בסיסיים',
    4: 'אקורדי בארה מתקדמים',
    5: "פאוור צ'ורדס",
  };

  static String labelFor(int difficulty) =>
      shortLabels[difficulty] ?? 'רמה $difficulty';

  static String categoryFor(int difficulty) =>
      categories[difficulty] ?? 'כללי';
}

class ChordDefinition {
  const ChordDefinition({
    required this.id,
    required this.displayName,
    required this.fingering,
    required this.notes,
    this.difficulty = 1,
    this.category = 'אקורדים פתוחים בסיסיים',
  });

  final String id;
  final String displayName;

  /// Six-character pattern from string 6 to string 1 (e.g. "x32010").
  final String fingering;
  final List<ChordNote> notes;

  /// Practice level 1–5.
  final int difficulty;

  /// Technique / style category (Hebrew).
  final String category;

  factory ChordDefinition.fromJson(Map<String, dynamic> json) {
    final difficulty = (json['difficulty'] as num?)?.toInt() ?? 1;
    return ChordDefinition(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      fingering: json['fingering'] as String,
      notes: (json['notes'] as List<dynamic>)
          .map((e) => ChordNote.fromJson(e as Map<String, dynamic>))
          .toList(),
      difficulty: difficulty.clamp(ChordDifficultyLevels.min, ChordDifficultyLevels.max),
      category: (json['category'] as String?) ??
          ChordDifficultyLevels.categoryFor(difficulty),
    );
  }

  /// Returns the expected note for [stringNumber], or null if not played (x).
  ChordNote? noteForString(int stringNumber) {
    for (final note in notes) {
      if (note.string == stringNumber) {
        return note;
      }
    }
    return null;
  }

  /// True when this string should not be strummed (marked x in fingering).
  bool isStringMuted(int stringNumber) {
    final index = 6 - stringNumber;
    if (index < 0 || index >= fingering.length) {
      return true;
    }
    return fingering[index].toLowerCase() == 'x';
  }

  /// First absolute fret shown on the 4-fret diagram (1 = nut visible).
  int get diagramBaseFret {
    final fretted = notes.where((n) => n.fret > 0).map((n) => n.fret);
    if (fretted.isEmpty) return 1;
    final maxFret = fretted.reduce((a, b) => a > b ? a : b);
    if (maxFret <= 4) return 1;
    return maxFret - 3;
  }
}

class ChordCatalog {
  const ChordCatalog({
    required this.chords,
    required this.referenceA4Hz,
    required this.strings,
  });

  final List<ChordDefinition> chords;
  final double referenceA4Hz;
  final List<GuitarStringTuning> strings;

  factory ChordCatalog.fromJson(Map<String, dynamic> json) {
    final tuning = json['tuning'] as Map<String, dynamic>;
    return ChordCatalog(
      referenceA4Hz: (tuning['referenceA4Hz'] as num).toDouble(),
      strings: (tuning['strings'] as List<dynamic>)
          .map((e) => GuitarStringTuning.fromJson(e as Map<String, dynamic>))
          .toList(),
      chords: (json['chords'] as List<dynamic>)
          .map((e) => ChordDefinition.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  ChordDefinition? chordById(String id) {
    for (final chord in chords) {
      if (chord.id == id) {
        return chord;
      }
    }
    return null;
  }

  List<ChordDefinition> chordsForDifficulty(int difficulty) {
    final list = chords.where((c) => c.difficulty == difficulty).toList();
    list.sort((a, b) => a.displayName.compareTo(b.displayName));
    return list;
  }

  /// All chords sorted by difficulty then name.
  List<ChordDefinition> get chordsByDifficultyThenName {
    final list = [...chords];
    list.sort((a, b) {
      final byDiff = a.difficulty.compareTo(b.difficulty);
      if (byDiff != 0) return byDiff;
      return a.displayName.compareTo(b.displayName);
    });
    return list;
  }
}
