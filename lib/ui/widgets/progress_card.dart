import 'package:flutter/material.dart';

import '../../models/chord_definition.dart';
import '../../services/progress_service.dart';
import '../app_theme.dart';
import '../navigation/app_page_route.dart';
import '../practice_screen.dart';

/// Home-screen summary of the player's progress with a "continue" shortcut.
class ProgressCard extends StatelessWidget {
  const ProgressCard({super.key, required this.catalog});

  final ChordCatalog catalog;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ProgressService.instance,
      builder: (context, _) {
        final progress = ProgressService.instance;
        final ids = catalog.chords.map((c) => c.id).toList();
        final started = progress.startedCount(ids);
        final mastered = progress.masteredCount(ids);
        final streak = progress.dayStreak;
        final suggested = progress.suggestedDifficulty({
          for (var level = ChordDifficultyLevels.min;
              level <= ChordDifficultyLevels.max;
              level++)
            level: catalog
                .chordsForDifficulty(level)
                .map((c) => c.id)
                .toList(),
        });
        final lastChord = progress.lastChordId == null
            ? null
            : catalog.chordById(progress.lastChordId!);

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: AppTheme.cardDecoration(
            borderColor: AppColors.turquoise.withValues(alpha: 0.3),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.insights_rounded,
                    color: AppColors.turquoise,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'ההתקדמות שלך',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (streak > 0)
                    Text(
                      '🔥 $streak ${streak == 1 ? 'יום' : 'ימים'} ברצף',
                      style: const TextStyle(
                        color: AppColors.amberBright,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: ids.isEmpty ? 0 : started / ids.length,
                  minHeight: 8,
                  backgroundColor:
                      AppColors.textMuted.withValues(alpha: 0.15),
                  color: AppColors.turquoise,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                started == 0
                    ? 'עוד לא נוגנו אקורדים — התחילו באימון אקורד בודד.'
                    : 'נוגנו $started מתוך ${ids.length} אקורדים · $mastered בשליטה מלאה',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
              if (suggested != null) ...[
                const SizedBox(height: 4),
                Text(
                  'מומלץ לתרגל עכשיו: ${ChordDifficultyLevels.labelFor(suggested)} · ${ChordDifficultyLevels.categoryFor(suggested)}',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
              ],
              if (lastChord != null) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      AppPageRoute<void>(
                        page: PracticeScreen(
                          catalog: catalog,
                          initialChord: lastChord,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text('המשך מאיפה שהפסקת · ${lastChord.displayName}'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
