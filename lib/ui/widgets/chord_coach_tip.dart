import 'package:flutter/material.dart';

import '../../models/feedback_result.dart';
import '../app_theme.dart';

/// Hebrew coaching tip derived from live string feedback.
class ChordCoachTip {
  const ChordCoachTip({
    required this.message,
    required this.tone,
  });

  final String message;
  final ChordMatchStatus tone;

  static ChordCoachTip fromFeedback({
    required bool listening,
    required ChordFeedback? feedback,
    String idleMessage =
        'לחץ "התחל האזנה" ונגן את האקורד — הדיאגרמה תאיר לפי הצליל.',
  }) {
    if (!listening) {
      return ChordCoachTip(
        message: idleMessage,
        tone: ChordMatchStatus.waiting,
      );
    }

    if (feedback == null ||
        feedback.matchStatus == ChordMatchStatus.waiting) {
      return const ChordCoachTip(
        message: 'ממתין לצליל… נגן את האקורד בבירור.',
        tone: ChordMatchStatus.waiting,
      );
    }

    if (feedback.matchStatus == ChordMatchStatus.perfect) {
      return const ChordCoachTip(
        message: 'מושלם! כל המיתרים נשמעים מדויק. 🎸',
        tone: ChordMatchStatus.perfect,
      );
    }

    final issues = feedback.issues;
    if (issues.isEmpty) {
      if (feedback.matchStatus == ChordMatchStatus.close) {
        return const ChordCoachTip(
          message: 'כמעט שם — כוון מעט את האצבעות או לחץ חזק יותר.',
          tone: ChordMatchStatus.close,
        );
      }
      return ChordCoachTip(
        message: feedback.summary,
        tone: feedback.matchStatus,
      );
    }

    final missing =
        issues.where((s) => s.status == NoteStatus.missing).toList();
    final weak = issues.where((s) => s.status == NoteStatus.weak).toList();

    if (missing.isNotEmpty) {
      final hebrew = hebrewStringName(missing.first.stringNumber);
      return ChordCoachTip(
        message: 'נראה שאתה חוסם את המיתר $hebrew.',
        tone: ChordMatchStatus.notDetected,
      );
    }

    if (weak.isNotEmpty) {
      final s = weak.first;
      final hebrew = hebrewStringName(s.stringNumber);
      final cents = s.pitchCentsOffset;
      if (cents != null && cents.abs() > 25) {
        final dir = cents > 0 ? 'גבוה מדי' : 'נמוך מדי';
        return ChordCoachTip(
          message: 'המיתר $hebrew נשמע $dir — הזז מעט את האצבע.',
          tone: ChordMatchStatus.close,
        );
      }
      return ChordCoachTip(
        message: 'המיתר $hebrew נשמע חלש — לחץ חזק יותר על הסריג.',
        tone: ChordMatchStatus.close,
      );
    }

    return ChordCoachTip(
      message: feedback.summary,
      tone: feedback.matchStatus,
    );
  }

  static String hebrewStringName(int stringNumber) {
    return switch (stringNumber) {
      1 => 'הראשון (הדק)',
      2 => 'השני',
      3 => 'השלישי',
      4 => 'הרביעי',
      5 => 'החמישי',
      6 => 'השישי (העבה)',
      _ => 'מספר $stringNumber',
    };
  }
}

/// Dark rounded card with summarized Hebrew coaching feedback.
class ChordCoachTipCard extends StatelessWidget {
  const ChordCoachTipCard({
    super.key,
    required this.tip,
    required this.listening,
    required this.feedback,
  });

  final ChordCoachTip tip;
  final bool listening;
  final ChordFeedback? feedback;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.feedbackColors(tip.tone);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.border, width: 1.5),
        boxShadow: tip.tone == ChordMatchStatus.perfect
            ? [
                BoxShadow(
                  color: AppColors.success.withValues(alpha: 0.22),
                  blurRadius: 14,
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                tip.tone == ChordMatchStatus.perfect
                    ? Icons.emoji_events_rounded
                    : tip.tone == ChordMatchStatus.waiting
                        ? Icons.music_note_rounded
                        : Icons.tips_and_updates_rounded,
                color: colors.text,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                tip.tone == ChordMatchStatus.perfect
                    ? 'משוב'
                    : 'טיפ לשיפור',
                style: TextStyle(
                  color: colors.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            tip.message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 16,
              height: 1.35,
            ),
          ),
          if (listening) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (feedback?.inputLevel ?? 0).clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: Colors.black26,
                color: AppColors.turquoise,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
