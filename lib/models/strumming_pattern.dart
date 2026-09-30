/// One event in a strumming / fingerpicking pattern.
enum PatternEventKind {
  down,
  up,
  mute,
  pause,
  /// Single-string pluck (arpeggio / fingerstyle).
  finger,
}

/// One slot in a bar: strum stroke or fingerpicked string.
class PatternEvent {
  const PatternEvent({
    required this.kind,
    this.stringNumber,
    this.fingerLabel,
  });

  final PatternEventKind kind;

  /// Guitar string 1 (high E) … 6 (low E). Set for [PatternEventKind.finger].
  final int? stringNumber;

  /// Classical finger label: p / i / m / a.
  final String? fingerLabel;

  bool get isSounding =>
      kind != PatternEventKind.pause;

  String get symbol {
    switch (kind) {
      case PatternEventKind.down:
        return '↓';
      case PatternEventKind.up:
        return '↑';
      case PatternEventKind.mute:
        return '✕';
      case PatternEventKind.pause:
        return '-';
      case PatternEventKind.finger:
        if (fingerLabel != null && fingerLabel!.isNotEmpty) {
          return fingerLabel!;
        }
        return '${stringNumber ?? '?'}';
    }
  }

  /// Open-string pitch used for arpeggio preview (A4=440).
  double? get previewHz {
    if (kind != PatternEventKind.finger) return null;
    final s = stringNumber;
    if (s == null) return null;
    return switch (s) {
      6 => 82.41,
      5 => 110.0,
      4 => 146.83,
      3 => 196.0,
      2 => 246.94,
      1 => 329.63,
      _ => 220.0,
    };
  }

  static PatternEvent parse(String raw) {
    final t = raw.trim();
    switch (t) {
      case '↓':
      case 'D':
      case 'd':
      case 'down':
        return const PatternEvent(kind: PatternEventKind.down);
      case '↑':
      case 'U':
      case 'u':
      case 'up':
        return const PatternEvent(kind: PatternEventKind.up);
      case '✕':
      case 'x':
      case 'X':
      case 'mute':
        return const PatternEvent(kind: PatternEventKind.mute);
      case '-':
      case '_':
      case 'pause':
      case 'rest':
        return const PatternEvent(kind: PatternEventKind.pause);
      case 'p':
      case 'P':
        return const PatternEvent(
          kind: PatternEventKind.finger,
          stringNumber: 6,
          fingerLabel: 'p',
        );
      case 'i':
      case 'I':
        return const PatternEvent(
          kind: PatternEventKind.finger,
          stringNumber: 3,
          fingerLabel: 'i',
        );
      case 'm':
      case 'M':
        return const PatternEvent(
          kind: PatternEventKind.finger,
          stringNumber: 2,
          fingerLabel: 'm',
        );
      case 'a':
      case 'A':
        return const PatternEvent(
          kind: PatternEventKind.finger,
          stringNumber: 1,
          fingerLabel: 'a',
        );
      default:
        final n = int.tryParse(t);
        if (n != null && n >= 1 && n <= 6) {
          return PatternEvent(
            kind: PatternEventKind.finger,
            stringNumber: n,
            fingerLabel: '$n',
          );
        }
        throw FormatException('Unknown pattern event: $raw');
    }
  }
}

/// Legacy alias used across the app.
typedef StrumStroke = PatternEventKind;

extension StrumStrokeX on PatternEventKind {
  String get symbol => PatternEvent(kind: this).symbol;

  static PatternEventKind fromSymbol(String raw) =>
      PatternEvent.parse(raw).kind;
}

/// A repeating strumming / arpeggio pattern (one bar of subdivisions).
class StrummingPattern {
  const StrummingPattern({
    required this.id,
    required this.name,
    required this.beatsPerBar,
    required this.events,
    this.subdivision = 2,
    this.description = '',
    this.defaultBpm = 80,
    this.practiceChordIds = const [],
  });

  final String id;
  final String name;
  final String description;

  /// Beats in one bar (e.g. 4 for 4/4, 3 for waltz).
  final int beatsPerBar;

  /// Subdivisions per beat (2 = eighths, 3 = triplets, 4 = sixteenths).
  final int subdivision;

  /// Suggested BPM for learning this pattern.
  final int defaultBpm;

  /// Chord ids from the catalog used in the guided path.
  final List<String> practiceChordIds;

  /// One entry per subdivision slot across the bar.
  final List<PatternEvent> events;

  /// Back-compat for call sites that still say `strokes`.
  List<PatternEvent> get strokes => events;

  int get slotsPerBar => beatsPerBar * subdivision;

  bool get isArpeggio =>
      events.any((e) => e.kind == PatternEventKind.finger);

  factory StrummingPattern.fromJson(Map<String, dynamic> json) {
    final raw = json['strokes'] ?? json['events'];
    final List<PatternEvent> events;
    if (raw is String) {
      events = raw
          .split(RegExp(r'\s+'))
          .where((s) => s.isNotEmpty)
          .map(PatternEvent.parse)
          .toList();
    } else if (raw is List) {
      events = raw.map((e) => PatternEvent.parse(e.toString())).toList();
    } else {
      throw FormatException('strokes/events must be a string or list');
    }

    final practice = (json['practiceChordIds'] as List<dynamic>? ?? const [])
        .map((e) => e.toString())
        .toList();

    return StrummingPattern(
      id: json['id'] as String? ?? 'pattern',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      beatsPerBar: (json['beatsPerBar'] as num?)?.toInt() ?? 4,
      subdivision: (json['subdivision'] as num?)?.toInt() ?? 2,
      defaultBpm: (json['bpm'] as num?)?.toInt() ??
          (json['defaultBpm'] as num?)?.toInt() ??
          80,
      practiceChordIds: practice,
      events: events,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'beatsPerBar': beatsPerBar,
        'subdivision': subdivision,
        'bpm': defaultBpm,
        'practiceChordIds': practiceChordIds,
        'strokes': events.map((e) => e.symbol).join(' '),
      };
}
