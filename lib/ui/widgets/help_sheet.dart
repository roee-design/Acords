import 'package:flutter/material.dart';

import '../app_theme.dart';

/// Which screen the help sheet is about.
enum HelpTopic {
  home,
  freePlay,
  chordLibrary,
  practice,
  transitions,
  tuner,
  chordBlitz,
}

class HelpSection {
  const HelpSection({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;
}

class HelpContent {
  const HelpContent({
    required this.title,
    required this.subtitle,
    required this.sections,
  });

  final String title;
  final String subtitle;
  final List<HelpSection> sections;

  static HelpContent forTopic(HelpTopic topic) {
    return switch (topic) {
      HelpTopic.home => const HelpContent(
          title: 'מסך הבית',
          subtitle: 'כאן בוחרים איך לתרגל',
          sections: [
            HelpSection(
              title: 'מה המסך הזה עושה?',
              body:
                  'מסך הבית הוא נקודת הכניסה לאפליקציה. מכאן בוחרים מצב אימון ומגיעים לכל שאר חלקי האפליקציה.',
            ),
            HelpSection(
              title: 'מצב האימון',
              body:
                  '• אימון אקורד בודד — תרגול ממוקד של אקורד אחד לפי רמת קושי, עם משוב חי מהמיקרופון.\n'
                  '• ספריית האקורדים (לשונית אקורדים) מחולקת ל־5 רמות: פתוחים, שביעיות, בארה ופאוור.',
            ),
            HelpSection(
              title: 'הלשוניות בתחתית',
              body:
                  '• בית — המסך הנוכחי.\n'
                  '• זיהוי חופשי — מנגנים כל אקורד והאפליקציה מזהה אותו לבד.\n'
                  '• אקורדים — ספרייה ללמוד איך לאחוז כל אקורד (דיאגרמת סריגים).\n'
                  '• טיונר — כוונון מיתר בודד לפי סטייה בסנטים.',
            ),
            HelpSection(
              title: 'לפני שמתחילים',
              body:
                  'בפעם הראשונה תתבקשו לאשר הרשאת מיקרופון. בלי זה הזיהוי והמשוב החי לא יעבדו. מומלץ לנגן בסביבה שקטה יחסית.',
            ),
          ],
        ),
      HelpTopic.freePlay => const HelpContent(
          title: 'זיהוי חופשי',
          subtitle: 'מנגנים — האפליקציה מזהה',
          sections: [
            HelpSection(
              title: 'למה זה משמש?',
              body:
                  'מצב לבדיקה עצמית: בלי לבחור אקורד מראש. מנגנים — והאפליקציה מציגה איזה אקורד שמעה, עם דיאגרמה וטיפים.',
            ),
            HelpSection(
              title: 'איך משתמשים?',
              body:
                  '1. לוחצים "התחל זיהוי".\n'
                  '2. מנגנים אקורד בגיטרה.\n'
                  '3. רואים את שם האקורד למעלה, דיאגרמת סריגים, וטיפ בעברית למטה.\n'
                  '4. כדי לעצור — לוחצים "עצור האזנה".',
            ),
            HelpSection(
              title: 'מה הצבעים אומרים?',
              body:
                  '• ירוק — המיתר נשמע נכון.\n'
                  '• אדום — המיתר חסר, חלש או לא מדויק.\n'
                  '• X — מיתר מושתק (לא לנגן).\n'
                  '• O — מיתר פתוח (לתת לו לצלצל בלי ללחוץ).',
            ),
            HelpSection(
              title: 'טיונר וטיפים',
              body:
                  'כרטיס הטיפ בתחתית מסביר בעברית מה לתקן — למשל "נראה שאתה חוסם את המיתר השלישי". כשהכל מדויק יופיע אפקט הצלחה. לכוונון מיתר בודד לפי סנטים — עברו ללשונית "טיונר".',
            ),
          ],
        ),
      HelpTopic.chordLibrary => const HelpContent(
          title: 'ספריית אקורדים',
          subtitle: 'ללמוד איך לאחוז כל אקורד',
          sections: [
            HelpSection(
              title: 'למה זה משמש?',
              body:
                  'מסך למידה ויזואלי — בלי מיקרופון. כאן רואים את דיאגרמת הסריגים של כל אקורד, כמו בחוברות אקורדים.',
            ),
            HelpSection(
              title: 'איך משתמשים?',
              body:
                  '1. בוחרים טאב לפי רמת קושי (1–5).\n'
                  '2. לוחצים על כרטיס אקורד.\n'
                  '3. נפתחת חלונית עם דיאגרמה מוגדלת של האחיזה.\n'
                  '4. אפשר לסגור ולעבור לאקורד אחר.',
            ),
            HelpSection(
              title: 'איך קוראים את הדיאגרמה?',
              body:
                  '• O — מיתר פתוח (לא ללחוץ).\n'
                  '• X — מיתר מושתק (לא לנגן).\n'
                  '• עיגול עם מספר — מספר האצבע (1 מורה, 2 אמה, 3 קמיצה, 4 זרת).\n'
                  '• מספרים בצד — מספר הסריג; אם האקורד גבוה על הצוואר הדיאגרמה מתחילה מסריג 2/3.\n'
                  '• מתחת לכל מיתר: מספר המיתר ותו (6·E עבה → 1·e דק).',
            ),
            HelpSection(
              title: 'טיפ למתחילים',
              body:
                  'למדו כאן את האחיזה קודם, ואז עברו ל"אימון אקורד בודד" כדי לתרגל עם משוב מהמיקרופון.',
            ),
          ],
        ),
      HelpTopic.practice => const HelpContent(
          title: 'אימון אקורד בודד',
          subtitle: 'תרגול ממוקד עד שהאקורד יציב',
          sections: [
            HelpSection(
              title: 'למה זה משמש?',
              body:
                  'בוחרים אקורד אחד ומתרגלים אותו שוב ושוב. האפליקציה מאזינה ומציגה משוב חי על כל מיתר — מושלם לשיפור דיוק ואחיזה.',
            ),
            HelpSection(
              title: 'איך משתמשים?',
              body:
                  '1. בוחרים אקורד מהרשימה.\n'
                  '2. לוחצים "התחל האזנה".\n'
                  '3. מנגנים את אותו אקורד.\n'
                  '4. עוקבים אחרי הדיאגרמה וכרטיס הטיפ.\n'
                  '5. אפשר להחליף אקורד בכל רגע מהרשימה.',
            ),
            HelpSection(
              title: 'מה רואים בזמן תרגול?',
              body:
                  '• שם האקורד כמטרה + אפקט הצלחה כשהוא מושלם.\n'
                  '• דיאגרמת סריגים עם צבעים חיים (ירוק/אדום).\n'
                  '• כרטיס טיפ בעברית — מה לתקן עכשיו.\n'
                  '• לכוונון מיתר בודד — השתמשו בלשונית "טיונר".',
            ),
            HelpSection(
              title: 'מתי לעבור הלאה?',
              body:
                  'כשהאקורד יוצא ירוק ומושלם באופן קבוע — אפשר לנסות זיהוי חופשי, או אימון מעברים עם אקורד נוסף.',
            ),
          ],
        ),
      HelpTopic.transitions => const HelpContent(
          title: 'אימון מעברי אקורדים',
          subtitle: 'מעבר חלק בין שני אקורדים בקצב — חוק 1-2-3-4',
          sections: [
            HelpSection(
              title: 'למה זה משמש?',
              body:
                  'אחרי שכבר מכירים אחיזה בסיסית — כאן מתרגלים לעבור בין שני אקורדים בזמן, כמו בשיר. יש מטרונום (גם עם סאונד), קצב ומשוב גיימיפייד.',
            ),
            HelpSection(
              title: 'חוק הפעימות 1-2-3-4',
              body:
                  'כל מידה = 4 פעימות. כך מתנהגים בכל פעימה:\n\n'
                  '① פעימה 1 — 🎸 פריטה! (Strum)\n'
                  'פריטה חזקה ומדויקת על האקורד הנוכחי. זו הפעימה שבה האפליקציה מצפה לשמוע את האקורד.\n\n'
                  '②③ פעימות 2–3 — 🎶 תן לצליל להדהד (Let it Ring)\n'
                  'החזיקו את האקורד יציב. אל תחליפו אצבעות עדיין — תנו למיתרים לצלצל.\n\n'
                  '④ פעימה 4 — 🤚 החלף! (Switch)\n'
                  'הרמו את היד והתחילו להעביר את האצבעות לכיוון האקורד הבא, כדי להספיק להגיע אליו בדיוק בפעימה 1 הבאה.',
            ),
            HelpSection(
              title: 'איך זה נראה בזמן אמת?',
              body:
                  'פעימה:   1        2        3        4        1 …\n'
                  'פעולה:  🎸פריטה  🎶הדהד  🎶הדהד  🤚החלף  🎸פריטה …\n'
                  'יעד:     אקורד א׳ ──────────────►  אקורד ב׳\n\n'
                  'טיפ: התחילו לאט (BPM נמוך) עד שהמעבר בפעימה 4 יוצא חלק.',
            ),
            HelpSection(
              title: 'איך מתחילים?',
              body:
                  '1. בוחרים אקורד א׳ ואקורד ב׳.\n'
                  '2. מגדירים BPM במד המהירות.\n'
                  '3. אפשר להפעיל "האצה הדרגתית" ו/או "סאונד מטרונום 🔊".\n'
                  '4. לוחצים "התחל אימון" ועוקבים אחרי הפעימות והכרטיסים.',
            ),
            HelpSection(
              title: 'מה קורה בזמן האימון?',
              body:
                  '• המטרונום מציג פעימות 1–4 (ומנגן קליק אם הסאונד פעיל).\n'
                  '• מוצג האקורד הנוכחי שצריך לנגן עכשיו.\n'
                  '• מוצג גם האקורד הבא — כדי להתכונן בפעימה 4.\n'
                  '• משוב כמו "בזמן!" או "פספסת את הקצב".',
            ),
            HelpSection(
              title: 'האצה הדרגתית',
              body:
                  'כשהאפשרות פעילה: אחרי כמה מעברים מושלמים ברצף — ה-BPM עולה מעט. אחרי פספוסים — הוא יורד. כך התרגול מתאים את עצמו לרמה שלכם.',
            ),
          ],
        ),
      HelpTopic.tuner => const HelpContent(
          title: 'טיונר',
          subtitle: 'כוונון מיתר לפי סטייה בסנטים',
          sections: [
            HelpSection(
              title: 'למה זה משמש?',
              body:
                  'כאן כווננים מיתר אחד בכל פעם. אפשר לבחור איזה מיתר מנגנים — ואז הסטייה נמדדת מול היעד של אותו מיתר פתוח. במצב "אוטו" מזוהים רק 6 המיתרים הפתוחים (לא תווים כרומטיים אחרים).',
            ),
            HelpSection(
              title: 'איך משתמשים?',
              body:
                  '1. בוחרים מיתר (למשל 6 · low E) — או משאירים "אוטו".\n'
                  '2. לוחצים "התחל טיונר".\n'
                  '3. מנגנים מיתר פתוח בלבד.\n'
                  '4. מתקנים עד שהמחוג במרכז והטקסט אומר "מכוון היטב!".\n'
                  'אם מופיע "נא לנגן מיתר פתוח" — הצליל רחוק מכל מיתר פתוח.',
            ),
            HelpSection(
              title: 'מה המחוג אומר?',
              body:
                  '• מרכז (כמעט 0 סנט) — מכוון.\n'
                  '• מספר חיובי — גבוה מדי, צריך להוריד את הצליל.\n'
                  '• מספר שלילי — נמוך מדי, צריך להעלות את הצליל.\n'
                  'עד ±5 סנט נחשב מכוון היטב.',
            ),
            HelpSection(
              title: 'טיפ',
              body:
                  'בחירת מיתר מקלה על הכיוונון, במיוחד במיתרים העבים. אל תנגנו אקורד שלם — רק מיתר אחד. אם יש רעש ברקע, הזיהוי פחות יציב.',
            ),
          ],
        ),
      HelpTopic.chordBlitz => const HelpContent(
          title: 'אתגר האקורדים',
          subtitle: 'משחק זמן מוגבל לתרגול מעברים מהירים',
          sections: [
            HelpSection(
              title: 'חוקי המשחק',
              body:
                  '• מתחילים עם 30 שניות על השעון.\n'
                  '• כל אקורד נכון מעניק +100 נקודות ו-+3 שניות.\n'
                  '• רצף של 5 אקורדים נכונים מעניק בונוס נוסף של +5 שניות.\n'
                  '• המטרה: להשיג את הניקוד הגבוה ביותר לפני שהזמן נגמר.',
            ),
            HelpSection(
              title: 'רמות וקבוצות',
              body:
                  'אפשר לבחור רמת קושי (1–5), את כל הרמות יחד, או לבנות קבוצה מותאמת אישית של אקורדים מהספרייה. השיא האישי נשמר בנפרד לכל בחירה.',
            ),
            HelpSection(
              title: 'ציון שליטה',
              body:
                  'בסיום מוצג זמן ממוצע לאקורד ודירוג שליטה (S / A / B / C) לפי מהירות המעברים שלכם.',
            ),
          ],
        ),
    };
  }
}

/// Circle with "?" — opens contextual help for [topic].
class HelpButton extends StatelessWidget {
  const HelpButton({
    super.key,
    required this.topic,
    this.size = 36,
  });

  final HelpTopic topic;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => showHelpSheet(context, topic),
        customBorder: const CircleBorder(),
        child: Ink(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.surfaceElevated,
            border: Border.all(
              color: AppColors.turquoise.withValues(alpha: 0.45),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            Icons.help_outline_rounded,
            size: size * 0.55,
            color: AppColors.turquoise,
            textDirection: TextDirection.ltr,
          ),
        ),
      ),
    );
  }
}

/// Opens a dark bottom sheet with help for [topic].
Future<void> showHelpSheet(BuildContext context, HelpTopic topic) {
  final content = HelpContent.forTopic(topic);

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
      return Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: DraggableScrollableSheet(
          initialChildSize: 0.72,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black54,
                    blurRadius: 24,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.textMuted.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: Row(
                      children: [
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.turquoise.withValues(alpha: 0.15),
                            border: Border.all(
                              color: AppColors.turquoise.withValues(alpha: 0.4),
                            ),
                          ),
                          child: const Icon(
                            Icons.help_rounded,
                            color: AppColors.turquoise,
                            size: 22,
                            textDirection: TextDirection.ltr,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                content.title,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                content.subtitle,
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                          color: AppColors.textMuted,
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 16),
                  Expanded(
                    child: ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                      itemCount: content.sections.length +
                          (topic == HelpTopic.transitions ? 1 : 0),
                      separatorBuilder: (_, _) => const SizedBox(height: 14),
                      itemBuilder: (context, index) {
                        if (topic == HelpTopic.transitions && index == 1) {
                          return const _TransitionsBeatGuide();
                        }
                        final sectionIndex =
                            topic == HelpTopic.transitions && index > 1
                                ? index - 1
                                : index;
                        final section = content.sections[sectionIndex];
                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: AppColors.turquoise.withValues(alpha: 0.18),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                section.title,
                                style: const TextStyle(
                                  color: AppColors.turquoise,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                section.body,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 14,
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    },
  );
}

/// Visual 1-2-3-4 beat guide for chord-transition help.
class _TransitionsBeatGuide extends StatelessWidget {
  const _TransitionsBeatGuide();

  static const _beats = [
    (
      beat: '1',
      emoji: '🎸',
      title: 'פריטה! (Strum)',
      body: 'פריטה חזקה ומדויקת על האקורד הנוכחי.',
      color: AppColors.amberBright,
    ),
    (
      beat: '2–3',
      emoji: '🎶',
      title: 'תן לצליל להדהד',
      body: 'החזיקו את האקורד יציב — אל תחליפו אצבעות עדיין.',
      color: AppColors.turquoise,
    ),
    (
      beat: '4',
      emoji: '🤚',
      title: 'החלף! (Switch)',
      body: 'הרמו את היד והעבירו אצבעות לאקורד הבא — להספיק עד פעימה 1.',
      color: AppColors.amber,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            AppColors.turquoise.withValues(alpha: 0.12),
            AppColors.amber.withValues(alpha: 0.08),
            AppColors.surfaceElevated,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.turquoise.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '📜 חוק 1-2-3-4 — בקצרה',
            style: TextStyle(
              color: AppColors.turquoise,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < _beats.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _BeatStepCard(
              beat: _beats[i].beat,
              emoji: _beats[i].emoji,
              title: _beats[i].title,
              body: _beats[i].body,
              accent: _beats[i].color,
            ),
          ],
        ],
      ),
    );
  }
}

class _BeatStepCard extends StatelessWidget {
  const _BeatStepCard({
    required this.beat,
    required this.emoji,
    required this.title,
    required this.body,
    required this.accent,
  });

  final String beat;
  final String emoji;
  final String title;
  final String body;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: 0.18),
              border: Border.all(color: accent.withValues(alpha: 0.6)),
            ),
            child: Text(
              beat,
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.w900,
                fontSize: beat.length > 1 ? 12 : 16,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$emoji  $title',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
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

