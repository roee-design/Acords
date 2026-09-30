import 'strumming_pattern.dart';

/// One lyric chunk with an optional chord above it.
class SongChordLyric {
  const SongChordLyric({
    this.chordId,
    this.lyrics = '',
  });

  /// Chord catalog id (e.g. `g_major`), or null for continuation / no chord.
  final String? chordId;

  /// Lyric text under this chord. Empty for instrumental / chord-only holds.
  final String lyrics;

  factory SongChordLyric.fromJson(Map<String, dynamic> json) {
    return SongChordLyric(
      chordId: json['chordId'] as String?,
      lyrics: json['lyrics'] as String? ?? '',
    );
  }
}

/// One display line of the song (several chord+lyric segments).
class SongLine {
  const SongLine({required this.segments});

  final List<SongChordLyric> segments;

  factory SongLine.fromJson(Map<String, dynamic> json) {
    final segs = (json['segments'] as List<dynamic>? ?? const [])
        .map((e) => SongChordLyric.fromJson(e as Map<String, dynamic>))
        .toList();
    return SongLine(segments: segs);
  }
}

/// Full song definition for strumming / lyrics practice.
class SongDefinition {
  const SongDefinition({
    required this.id,
    required this.title,
    required this.artist,
    required this.difficulty,
    required this.bpm,
    required this.pattern,
    required this.lines,
    this.instrumental = false,
    this.rtl = false,
    this.publicDomain = false,
  });

  final String id;
  final String title;
  final String artist;

  /// Practice level 1–5.
  final int difficulty;

  /// Suggested tempo for free-accompany mode.
  final int bpm;

  final StrummingPattern pattern;
  final List<SongLine> lines;

  /// Copyrighted / no lyrics — show chords & structure only.
  final bool instrumental;

  /// Hebrew (or other RTL) lyric layout.
  final bool rtl;

  /// Lyrics are public-domain source text (safe to ship verbatim).
  final bool publicDomain;

  /// Flat list of chord ids in play order (skips null / empty).
  List<String> get chordSequence {
    final out = <String>[];
    for (final line in lines) {
      for (final seg in line.segments) {
        final id = seg.chordId;
        if (id != null && id.isNotEmpty) {
          out.add(id);
        }
      }
    }
    return out;
  }

  factory SongDefinition.fromJson(Map<String, dynamic> json) {
    final patternJson = json['pattern'];
    final StrummingPattern pattern;
    if (patternJson is Map<String, dynamic>) {
      pattern = StrummingPattern.fromJson(patternJson);
    } else if (patternJson is String) {
      pattern = StrummingPattern(
        id: 'inline',
        name: '',
        beatsPerBar: 4,
        events: patternJson
            .split(RegExp(r'\s+'))
            .where((s) => s.isNotEmpty)
            .map(PatternEvent.parse)
            .toList(),
      );
    } else {
      throw FormatException('song ${json['id']} missing pattern');
    }

    return SongDefinition(
      id: json['id'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String? ?? '',
      difficulty: ((json['difficulty'] as num?)?.toInt() ?? 1).clamp(1, 5),
      bpm: (json['bpm'] as num?)?.toInt() ?? 80,
      pattern: pattern,
      lines: (json['lines'] as List<dynamic>? ?? const [])
          .map((e) => SongLine.fromJson(e as Map<String, dynamic>))
          .toList(),
      instrumental: json['instrumental'] as bool? ?? false,
      rtl: json['rtl'] as bool? ?? false,
      publicDomain: json['publicDomain'] as bool? ?? false,
    );
  }
}

/// Catalog loaded from [assets/songs.json].
class SongCatalog {
  const SongCatalog({required this.songs});

  final List<SongDefinition> songs;

  factory SongCatalog.fromJson(Map<String, dynamic> json) {
    return SongCatalog(
      songs: (json['songs'] as List<dynamic>? ?? const [])
          .map((e) => SongDefinition.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  SongDefinition? byId(String id) {
    for (final s in songs) {
      if (s.id == id) return s;
    }
    return null;
  }

  List<SongDefinition> forDifficulty(int difficulty) {
    final list = songs.where((s) => s.difficulty == difficulty).toList();
    list.sort((a, b) => a.title.compareTo(b.title));
    return list;
  }
}
