import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How well a chord is known, from confirmed strummed hits.
enum ChordMastery {
  /// Never played successfully.
  none,

  /// At least one confirmed hit.
  started,

  /// 5+ hits.
  practicing,

  /// 15+ hits on at least 2 different days.
  mastered,
}

extension ChordMasteryLabel on ChordMastery {
  String get label => switch (this) {
        ChordMastery.none => 'עוד לא נוגן',
        ChordMastery.started => 'התחלה',
        ChordMastery.practicing => 'בתרגול',
        ChordMastery.mastered => 'בשליטה',
      };

  /// 0–3 stars for compact UI.
  int get stars => index;
}

class ChordProgress {
  ChordProgress({
    this.hits = 0,
    Set<String>? days,
    this.bestSeconds,
    this.lastPlayed,
  }) : days = days ?? <String>{};

  int hits;

  /// Distinct practice days (yyyy-mm-dd), newest kept, capped.
  final Set<String> days;

  /// Fastest target-shown → chord-confirmed time (Blitz / song steps).
  double? bestSeconds;
  String? lastPlayed;

  ChordMastery get mastery {
    if (hits >= 15 && days.length >= 2) return ChordMastery.mastered;
    if (hits >= 5) return ChordMastery.practicing;
    if (hits >= 1) return ChordMastery.started;
    return ChordMastery.none;
  }

  Map<String, dynamic> toJson() => {
        'hits': hits,
        'days': days.toList(),
        if (bestSeconds != null) 'best': bestSeconds,
        if (lastPlayed != null) 'last': lastPlayed,
      };

  factory ChordProgress.fromJson(Map<String, dynamic> json) => ChordProgress(
        hits: (json['hits'] as num?)?.toInt() ?? 0,
        days: {
          for (final d in (json['days'] as List<dynamic>? ?? const []))
            d as String,
        },
        bestSeconds: (json['best'] as num?)?.toDouble(),
        lastPlayed: json['last'] as String?,
      );
}

class SongProgress {
  SongProgress({this.guidedStep = 0, this.completions = 0, this.lastPlayed});

  /// Highest guided-path step completed (0 = none … 3 = full song).
  int guidedStep;

  /// Times the full song was played through (chord-gated).
  int completions;
  String? lastPlayed;

  bool get isCompleted => completions > 0;

  Map<String, dynamic> toJson() => {
        'step': guidedStep,
        'done': completions,
        if (lastPlayed != null) 'last': lastPlayed,
      };

  factory SongProgress.fromJson(Map<String, dynamic> json) => SongProgress(
        guidedStep: (json['step'] as num?)?.toInt() ?? 0,
        completions: (json['done'] as num?)?.toInt() ?? 0,
        lastPlayed: json['last'] as String?,
      );
}

/// Local learning progress (SharedPreferences, one JSON document).
///
/// Loaded once at startup ([load]); reads are synchronous so screens can
/// render immediately, writes are persisted in the background. Listen to it
/// (it is a [ChangeNotifier]) to refresh badges.
class ProgressService extends ChangeNotifier {
  ProgressService({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  static final ProgressService instance = ProgressService();

  static const _storageKey = 'acords_progress_v1';
  static const _maxDays = 60;

  final DateTime Function() _clock;

  final Map<String, ChordProgress> _chords = {};
  final Map<String, SongProgress> _songs = {};
  final Map<String, int> _strumStages = {};
  final Map<String, int> _gameStars = {};
  final Map<String, int> _gameScores = {};
  final Map<String, int> _calibration = {};
  final Set<String> _practiceDays = {};
  int? _lastDifficulty;
  String? _lastChordId;
  var _loaded = false;

  bool get isLoaded => _loaded;
  int? get lastDifficulty => _lastDifficulty;
  String? get lastChordId => _lastChordId;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        _restore(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (error) {
      debugPrint('[Acords Progress] load failed: $error');
    }
    _loaded = true;
    notifyListeners();
  }

  void _restore(Map<String, dynamic> json) {
    final chords = json['chords'] as Map<String, dynamic>? ?? const {};
    for (final e in chords.entries) {
      _chords[e.key] = ChordProgress.fromJson(e.value as Map<String, dynamic>);
    }
    final songs = json['songs'] as Map<String, dynamic>? ?? const {};
    for (final e in songs.entries) {
      _songs[e.key] = SongProgress.fromJson(e.value as Map<String, dynamic>);
    }
    void readInts(String key, Map<String, int> into) {
      final m = json[key] as Map<String, dynamic>? ?? const {};
      for (final e in m.entries) {
        into[e.key] = (e.value as num).toInt();
      }
    }

    readInts('strum', _strumStages);
    readInts('gameStars', _gameStars);
    readInts('gameScores', _gameScores);
    readInts('calibration', _calibration);
    _practiceDays.addAll([
      for (final d in (json['days'] as List<dynamic>? ?? const [])) d as String,
    ]);
    _lastDifficulty = (json['lastLevel'] as num?)?.toInt();
    _lastChordId = json['lastChord'] as String?;
  }

  Map<String, dynamic> toJson() => {
        'chords': {for (final e in _chords.entries) e.key: e.value.toJson()},
        'songs': {for (final e in _songs.entries) e.key: e.value.toJson()},
        'strum': _strumStages,
        'gameStars': _gameStars,
        'gameScores': _gameScores,
        'calibration': _calibration,
        'days': _practiceDays.toList(),
        if (_lastDifficulty != null) 'lastLevel': _lastDifficulty,
        if (_lastChordId != null) 'lastChord': _lastChordId,
      };

  Future<void>? _pendingSave;

  void _changed() {
    notifyListeners();
    _pendingSave ??= Future<void>.delayed(const Duration(milliseconds: 300), () async {
      _pendingSave = null;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_storageKey, jsonEncode(toJson()));
      } catch (error) {
        debugPrint('[Acords Progress] save failed: $error');
      }
    });
  }

  String get _today {
    final d = _clock();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  void _markPracticeDay() {
    _practiceDays.add(_today);
    if (_practiceDays.length > _maxDays) {
      final sorted = _practiceDays.toList()..sort();
      _practiceDays.remove(sorted.first);
    }
  }

  // --- Chords --------------------------------------------------------------

  ChordProgress chord(String chordId) => _chords[chordId] ?? ChordProgress();

  ChordMastery masteryOf(String chordId) => chord(chordId).mastery;

  /// Records a confirmed strummed chord. [seconds]: time from when the chord
  /// was asked for until it was confirmed, when meaningful.
  void recordChordHit(String chordId, {double? seconds}) {
    if (chordId.isEmpty) return;
    final p = _chords.putIfAbsent(chordId, ChordProgress.new);
    p.hits++;
    final today = _today;
    p.days.add(today);
    if (p.days.length > _maxDays) {
      final sorted = p.days.toList()..sort();
      p.days.remove(sorted.first);
    }
    p.lastPlayed = today;
    if (seconds != null && seconds > 0) {
      final best = p.bestSeconds;
      if (best == null || seconds < best) p.bestSeconds = seconds;
    }
    _markPracticeDay();
    _changed();
  }

  int masteredCount(Iterable<String> chordIds) =>
      chordIds.where((id) => masteryOf(id) == ChordMastery.mastered).length;

  int startedCount(Iterable<String> chordIds) =>
      chordIds.where((id) => masteryOf(id) != ChordMastery.none).length;

  /// Lowest difficulty that still has a chord below "practicing", given
  /// chord ids per difficulty. Null when everything is at least practicing.
  int? suggestedDifficulty(Map<int, List<String>> chordIdsByDifficulty) {
    final levels = chordIdsByDifficulty.keys.toList()..sort();
    for (final level in levels) {
      final ids = chordIdsByDifficulty[level]!;
      if (ids.any((id) => masteryOf(id).index < ChordMastery.practicing.index)) {
        return level;
      }
    }
    return null;
  }

  void rememberPracticeSelection({required int difficulty, required String chordId}) {
    if (_lastDifficulty == difficulty && _lastChordId == chordId) return;
    _lastDifficulty = difficulty;
    _lastChordId = chordId;
    _changed();
  }

  // --- Songs / strumming -----------------------------------------------------

  SongProgress song(String songId) => _songs[songId] ?? SongProgress();

  void recordSongGuidedStep(String songId, int step) {
    final p = _songs.putIfAbsent(songId, SongProgress.new);
    if (step > p.guidedStep) p.guidedStep = step;
    p.lastPlayed = _today;
    _markPracticeDay();
    _changed();
  }

  void recordSongCompleted(String songId) {
    final p = _songs.putIfAbsent(songId, SongProgress.new);
    p.completions++;
    if (p.guidedStep < 3) p.guidedStep = 3;
    p.lastPlayed = _today;
    _markPracticeDay();
    _changed();
  }

  /// Highest completed stage (0–3) of a strumming pattern's guided path.
  int strumStage(String patternId) => _strumStages[patternId] ?? 0;

  void recordStrumStage(String patternId, int stage) {
    if (stage <= strumStage(patternId)) return;
    _strumStages[patternId] = stage;
    _markPracticeDay();
    _changed();
  }

  // --- Rhythm game ---------------------------------------------------------

  /// Best stars (0–3) for a game run, keyed e.g. `pattern:basic_44:2` or
  /// `song:amazing_grace`.
  int gameStars(String key) => _gameStars[key] ?? 0;

  int gameBestScore(String key) => _gameScores[key] ?? 0;

  /// Stores a finished run; returns true when it is a new best score.
  bool recordGameResult(String key, {required int stars, required int score}) {
    final newBest = score > gameBestScore(key);
    if (stars > gameStars(key)) _gameStars[key] = stars;
    if (newBest) _gameScores[key] = score;
    _markPracticeDay();
    _changed();
    return newBest;
  }

  /// Latency correction (ms) learned from the count-in, per input mode.
  int calibrationMs(String mode) => _calibration[mode] ?? (mode == 'mic' ? 150 : 0);

  void setCalibrationMs(String mode, int ms) {
    _calibration[mode] = ms;
    _changed();
  }

  // --- Streak ------------------------------------------------------------------

  /// Consecutive practice days ending today (or yesterday, so the streak is
  /// not shown as broken before today's practice).
  int get dayStreak {
    if (_practiceDays.isEmpty) return 0;
    var day = DateTime(_clock().year, _clock().month, _clock().day);
    String key(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    if (!_practiceDays.contains(key(day))) {
      day = day.subtract(const Duration(days: 1));
      if (!_practiceDays.contains(key(day))) return 0;
    }
    var streak = 0;
    while (_practiceDays.contains(key(day))) {
      streak++;
      day = DateTime(day.year, day.month, day.day - 1);
    }
    return streak;
  }

  /// Test helper: wipe in-memory state.
  @visibleForTesting
  void debugReset() {
    _chords.clear();
    _songs.clear();
    _strumStages.clear();
    _gameStars.clear();
    _gameScores.clear();
    _calibration.clear();
    _practiceDays.clear();
    _lastDifficulty = null;
    _lastChordId = null;
    _loaded = false;
  }
}
