import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// One saved Chord Blitz high-score record (points + mastery grade).
class BlitzHighScoreRecord {
  const BlitzHighScoreRecord({
    required this.score,
    required this.gradeLetter,
    this.averageSeconds,
  });

  final int score;
  final String gradeLetter;
  final double? averageSeconds;

  bool get hasScore => score > 0;

  Map<String, dynamic> toJson() => {
        'score': score,
        'grade': gradeLetter,
        if (averageSeconds != null) 'avg': averageSeconds,
      };

  factory BlitzHighScoreRecord.fromJson(Map<String, dynamic> json) {
    return BlitzHighScoreRecord(
      score: (json['score'] as num?)?.toInt() ?? 0,
      gradeLetter: (json['grade'] as String?) ?? '—',
      averageSeconds: (json['avg'] as num?)?.toDouble(),
    );
  }

  static const empty = BlitzHighScoreRecord(score: 0, gradeLetter: '—');
}

/// Chord Blitz prefs — high scores in SharedPreferences, keyed per pool.
class BlitzPrefs {
  BlitzPrefs._();

  static const _customChordIdsKey = 'blitz_custom_chord_ids';

  /// e.g. `blitz_highscore_level_1` … `blitz_highscore_level_5`
  static String highScoreKeyForLevel(int level) =>
      'blitz_highscore_level_$level';

  static String get highScoreKeyAll => 'blitz_highscore_all';

  static String get highScoreKeyCustom => 'blitz_highscore_custom';

  static Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  static Future<BlitzHighScoreRecord> getHighScoreRecord(String key) async {
    final prefs = await _prefs();
    final raw = prefs.getString(key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          return BlitzHighScoreRecord.fromJson(decoded);
        }
        if (decoded is Map) {
          return BlitzHighScoreRecord.fromJson(
            decoded.map((k, v) => MapEntry(k.toString(), v)),
          );
        }
      } catch (_) {}
    }
    // Legacy: int-only score under the same key.
    final legacy = prefs.getInt(key);
    if (legacy != null && legacy > 0) {
      return BlitzHighScoreRecord(score: legacy, gradeLetter: '—');
    }
    return BlitzHighScoreRecord.empty;
  }

  static Future<int> getHighScore(String key) async {
    return (await getHighScoreRecord(key)).score;
  }

  static Future<void> saveHighScoreIfBest({
    required String key,
    required int score,
    required String gradeLetter,
    double? averageSeconds,
  }) async {
    final current = await getHighScoreRecord(key);
    if (score <= current.score) return;

    final prefs = await _prefs();
    final record = BlitzHighScoreRecord(
      score: score,
      gradeLetter: gradeLetter,
      averageSeconds: averageSeconds,
    );
    await prefs.setString(key, jsonEncode(record.toJson()));
  }

  static Future<List<String>> loadCustomChordIds() async {
    final prefs = await _prefs();
    return prefs.getStringList(_customChordIdsKey) ?? const [];
  }

  static Future<void> saveCustomChordIds(List<String> ids) async {
    final prefs = await _prefs();
    await prefs.setStringList(_customChordIdsKey, ids);
  }
}
