import 'package:flutter/material.dart';

import '../app_theme.dart';

/// Explains strum symbols and the eighth-note counting grid.
Future<void> showStrummingHelpSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.all(Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.textMuted.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'איך קוראים את דפוס הפריטה?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'כל משבצת ברצף היא שמינית (או רבע, לפי הדפוס). '
                  'עקבו אחרי החץ המודגש והקשיבו לדוגמת השמע.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                const _HelpRow(
                  symbol: '↓',
                  title: 'פריטה למטה (Down)',
                  body:
                      'פריטה מלמעלה למטה עם האגודל או המפרט — מהמיתרים הנמוכים אל הגבוהים.',
                ),
                const _HelpRow(
                  symbol: '↑',
                  title: 'פריטה למעלה (Up)',
                  body:
                      'פריטה מלמטה למעלה — לרוב קלה וקצרה יותר מפריטה למטה.',
                ),
                const _HelpRow(
                  symbol: '✕',
                  title: 'השתקה / Slap (Mute)',
                  body:
                      'פריטה תוך חסימת המיתרים בכף היד — צליל קצר ו«יבש», בלי אקורד מצלצל.',
                ),
                const _HelpRow(
                  symbol: '-',
                  title: 'השהיה (Rest)',
                  body:
                      'שומרים על הרצף בלי לפרוט — היד ממשיכה בתנועה, אבל אין מכה על המיתרים.',
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.turquoise.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'רשת הקצב (שמיניות)',
                        style: TextStyle(
                          color: AppColors.turquoise,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'במשקל 4/4 עם שמיניות סופרים:',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 13,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '1  ·  ו  ·  2  ·  ו  ·  3  ·  ו  ·  4  ·  ו',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'המספרים (1–4) הם הפעימות החזקות; '
                        '«ו» הן השמיניות שביניהן. '
                        'בדפוס עם חלוקה ל־2, כל חץ עומד על פעימה או על «ו».',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('הבנתי'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _HelpRow extends StatelessWidget {
  const _HelpRow({
    required this.symbol,
    required this.title,
    required this.body,
  });

  final String symbol;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.textMuted.withValues(alpha: 0.25),
              ),
            ),
            child: Text(
              symbol,
              style: const TextStyle(
                color: AppColors.amberBright,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
