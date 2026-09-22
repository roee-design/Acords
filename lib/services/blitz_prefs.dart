import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Local persistence for Chord Blitz high scores and custom chord groups.
///
/// Stored as JSON under the app documents directory (survives app restarts).
class BlitzPrefs {
  BlitzPrefs._();

  static const _fileName = 'blitz_prefs.json';

  static String highScoreKeyForLevel(int level) => 'level_$level';

  static String get highScoreKeyAll => 'all';

  static String get highScoreKeyCustom => 'custom';

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<Map<String, dynamic>> _read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return {};
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (_) {}
    return {};
  }

  static Future<void> _write(Map<String, dynamic> data) async {
    final file = await _file();
    await file.writeAsString(jsonEncode(data));
  }

  static Future<int> getHighScore(String key) async {
    final data = await _read();
    final scores = data['highScores'];
    if (scores is Map && scores[key] is num) {
      return (scores[key] as num).toInt();
    }
    return 0;
  }

  static Future<void> saveHighScoreIfBest(String key, int score) async {
    final data = await _read();
    final scores = Map<String, dynamic>.from(
      (data['highScores'] as Map?)?.map(
            (k, v) => MapEntry(k.toString(), v),
          ) ??
          {},
    );
    final current = (scores[key] as num?)?.toInt() ?? 0;
    if (score > current) {
      scores[key] = score;
      data['highScores'] = scores;
      await _write(data);
    }
  }

  static Future<List<String>> loadCustomChordIds() async {
    final data = await _read();
    final ids = data['customChordIds'];
    if (ids is List) {
      return ids.map((e) => e.toString()).toList();
    }
    return const [];
  }

  static Future<void> saveCustomChordIds(List<String> ids) async {
    final data = await _read();
    data['customChordIds'] = ids;
    await _write(data);
  }
}
