import 'package:chord_trainer/services/progress_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('mastery grows with hits and needs two days', () async {
    SharedPreferences.setMockInitialValues({});
    var now = DateTime(2026, 10, 1, 18);
    final p = ProgressService(clock: () => now);
    await p.load();

    expect(p.masteryOf('c_major'), ChordMastery.none);
    p.recordChordHit('c_major', seconds: 3.2);
    expect(p.masteryOf('c_major'), ChordMastery.started);
    for (var i = 0; i < 20; i++) {
      p.recordChordHit('c_major', seconds: 2.5);
    }
    expect(p.masteryOf('c_major'), ChordMastery.practicing,
        reason: 'one day only');
    now = DateTime(2026, 10, 2, 9);
    p.recordChordHit('c_major', seconds: 1.9);
    expect(p.masteryOf('c_major'), ChordMastery.mastered);
    expect(p.chord('c_major').bestSeconds, 1.9);
    expect(p.dayStreak, 2);
  });

  test('persists and restores', () async {
    SharedPreferences.setMockInitialValues({});
    final a = ProgressService(clock: () => DateTime(2026, 10, 5));
    await a.load();
    a.recordChordHit('g_major');
    a.recordSongGuidedStep('amazing_grace', 2);
    a.recordSongCompleted('hine_ma_tov');
    a.recordStrumStage('basic_44', 3);
    a.rememberPracticeSelection(difficulty: 2, chordId: 'c_7');
    await Future<void>.delayed(const Duration(milliseconds: 400));

    final b = ProgressService(clock: () => DateTime(2026, 10, 5));
    await b.load();
    expect(b.chord('g_major').hits, 1);
    expect(b.song('amazing_grace').guidedStep, 2);
    expect(b.song('hine_ma_tov').isCompleted, isTrue);
    expect(b.strumStage('basic_44'), 3);
    expect(b.lastDifficulty, 2);
    expect(b.lastChordId, 'c_7');
  });

  test('suggested difficulty is the lowest unfinished level', () async {
    SharedPreferences.setMockInitialValues({});
    final p = ProgressService(clock: () => DateTime(2026, 10, 5));
    await p.load();
    final levels = {
      1: ['c_major', 'g_major'],
      2: ['c_7'],
    };
    expect(p.suggestedDifficulty(levels), 1);
    for (var i = 0; i < 5; i++) {
      p.recordChordHit('c_major');
      p.recordChordHit('g_major');
    }
    expect(p.suggestedDifficulty(levels), 2);
  });

  test('streak survives until the day after, then breaks', () async {
    SharedPreferences.setMockInitialValues({});
    var now = DateTime(2026, 10, 10);
    final p = ProgressService(clock: () => now);
    await p.load();
    p.recordChordHit('e_minor');
    now = DateTime(2026, 10, 11);
    expect(p.dayStreak, 1);
    now = DateTime(2026, 10, 13);
    expect(p.dayStreak, 0);
  });
}
