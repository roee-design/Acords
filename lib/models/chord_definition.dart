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
  });

  /// String number: 6 = low E, 1 = high E.
  final int string;
  final int fret;
  final String noteName;
  final int midi;

  factory ChordNote.fromJson(Map<String, dynamic> json) {
    return ChordNote(
      string: json['string'] as int,
      fret: json['fret'] as int,
      noteName: json['noteName'] as String,
      midi: json['midi'] as int,
    );
  }
}

class ChordDefinition {
  const ChordDefinition({
    required this.id,
    required this.displayName,
    required this.fingering,
    required this.notes,
  });

  final String id;
  final String displayName;

  /// Six-character pattern from string 6 to string 1 (e.g. "x32010").
  final String fingering;
  final List<ChordNote> notes;

  factory ChordDefinition.fromJson(Map<String, dynamic> json) {
    return ChordDefinition(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      fingering: json['fingering'] as String,
      notes: (json['notes'] as List<dynamic>)
          .map((e) => ChordNote.fromJson(e as Map<String, dynamic>))
          .toList(),
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
}
