import 'package:flutter/material.dart';

import '../../services/progress_service.dart';
import '../app_theme.dart';

/// Three small stars showing how well a chord is known.
class MasteryStars extends StatelessWidget {
  const MasteryStars({super.key, required this.mastery, this.size = 14});

  final ChordMastery mastery;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: mastery.label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Icon(
              i < mastery.stars ? Icons.star_rounded : Icons.star_border_rounded,
              size: size,
              color: i < mastery.stars
                  ? AppColors.amberBright
                  : AppColors.textMuted.withValues(alpha: 0.45),
            ),
        ],
      ),
    );
  }
}

/// "בתרגול · 7 פריטות מוצלחות" line for a chord.
String chordProgressSubtitle(ChordProgress p) {
  if (p.hits == 0) return 'עוד לא נוגן בהצלחה';
  final count = p.hits == 1 ? 'פריטה מוצלחת אחת' : '${p.hits} פריטות מוצלחות';
  return '${p.mastery.label} · $count';
}
