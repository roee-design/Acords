# מסמך מסירה — Chord Trainer (Acords)

מסמך עבודה שוטף למפתח / AI. **כל שינוי, באג או פיצ'ר מתועדים כאן בלבד.**
עודכן לאחרונה: **2026-11-22** (מסמך מלא — כל מה שנעשה עד עכשיו).

| | |
|---|---|
| **ריפו** | `https://github.com/roee-design/Acords` |
| **ענף העבודה** | `feature/detection-progress-content` (לא מוזג ל-`master`) |
| **עותק עבודה במחשב הזה** | `C:\Users\noam1\Acords\.claude\worktrees\detection-progress` (worktree של `C:\Users\noam1\Acords`) |
| **עותק היסטורי** | `c:\Users\Fisher-home\Desktop\chords` (המחשב הקודם) |
| **APK דיבאג אחרון** | `C:\Users\noam1\Downloads\acords_debug_1.0.2_1_guitar-sim-calibrated.apk` |

> **Release נעול:** `HANDOFF_2.md` + `releases/acords_v1.0.1.apk` = snapshot רשמי של **v1.0.1 (+1)**. **אין לערוך את `HANDOFF_2.md`.**

### חוקי עבודה (חובה אחרי כל פעולה)

1. בונים **APK דיבאג** → `build/app/outputs/flutter-apk/app-debug.apk` (לא מעתיקים ל־`releases/`).
2. מעדכנים את **`HANDOFF.md`** בלבד (מצב נוכחי + Build history).
3. **לא משנים ספי זיהוי בניחוש.** כל שינוי בזיהוי נמדד קודם בספסל (`test/bench`, סעיף 15) ואם יש — מול הקלטה אמיתית ממצב אבחון.

---

## תקציר מנהלים — מה האפליקציה עושה היום

אפליקציית Flutter בעברית ללימוד גיטרה, ששומעת את הנגינה דרך המיקרופון:

- **אימון אקורד בודד** — 52 אקורדים ב-5 רמות, משוב לכל מיתר (מדויק / חלש / חסר / צליל זר).
- **אתגר האקורדים** — 30 שניות, ניקוד, רצפים, שיאים.
- **זיהוי חופשי** — מנגנים מה שרוצים, האפליקציה מזהה את האקורד.
- **ספריית אקורדים** — דיאגרמות עם מספרי אצבעות, השמעת אקורד, כוכבי שליטה.
- **שירים** — 17 שירים (9 עם מילים מלאות מנחלת הכלל), חיפוש, סינון עברית/אנגלית, ז׳אנרים, רמות.
- **לימוד פריטות** — 11 דפוסים; לכל דפוס אנימציית גיטרה מתקרבת, משחק קצב ב-3 מהירויות ושיר לדוגמה.
- **משחק קצב** — פריטות מתקרבות על מסלול; משחקים בהחלקה על המסך או **עם גיטרה אמיתית** (המיקרופון בודק תזמון *וגם* שהצלילים נכונים).
- **טיונר** — YIN + חידוד ספקטרלי, דיוק ±1¢ בסימולציה.
- **מעקב התקדמות** — רמת שליטה לכל אקורד, רצף ימים, «המשך מאיפה שהפסקת».

**מצב:** כל הבדיקות האוטומטיות עוברות; הזיהוי נבדק ב**סימולציה** מקיפה — **עדיין לא אומת מול הקלטות אמיתיות** (ראו סעיף 16).

---

## מצב נוכחי — סבב פיתוח

| שדה | ערך |
|-----|-----|
| גרסת פיתוח (`pubspec.yaml`) | `1.0.2+1` |
| Release יציב (נעול) | `1.0.1+1` → `releases/acords_v1.0.1.apk` (~48.9MB) — ראו `HANDOFF_2.md` |
| APK דיבאג | `build/app/outputs/flutter-apk/app-debug.apk` (~183MB) |
| סביבה | Flutter (D:\downloads\flutter\flutter) + JDK של Android Studio (`D:\Program Files\Android\Android Studio\jbr`) |
| בדיקות | `flutter test` — **35 עוברות**, 9 ספסלים מדולגים (`--run-skipped`) |
| קומיט אחרון | `cb102bb` — Guitar mode: calibrate against a realistic player/phone simulation |

### סבבי העבודה מאז v1.0.1 (לפי סדר)

1. **2026-10-12 — מנוע זיהוי חדש** — `ChordDetectionEngine` (שעון דגימות), `OnsetDetector` (spectral flux), `ChordMatcher` יחסי עם דחיית צליל זר, פגיעה = פריטה חדשה + 2 פריימים מושלמים; טיונר YIN; `ProgressService`; +22 אקורדים, +8 שירים, +5 דפוסים; ספסל סינתטי.
2. **2026-10-13 — תיקון קריסה בפתיחה** — `MainActivity.kt` הוסתר ע״י כלל `chord_trainer/` ב-`.gitignore`; הכלל עוגן ל-`/chord_trainer/`.
3. **2026-10-14 — משחק קצב + שיעורי פריטה + ספריית שירים** — `RhythmGameScreen`, `StrumLessonScreen` + `GuitarStrumAnimation`, חיפוש/ז׳אנרים/שפה, מילים מלאות, ערכת נושא אינדיגו/סגול.
4. **2026-10-16 — מצב גיטרה, פריטות רכות** — `OnsetDetector.forRhythmGame`, מד מיקרופון, «נשמע!».
5. **2026-10-23 — מסך כיול מיקרופון** — `MicCalibrationScreen`, `LatencyCalibrator`; הוסר כיול-בספירה וכיול אוטומטי שהצטבר.
6. **2026-10-27 — אימות תוכן לכל פריטה** — `StrumCapture` + `StrokeVerifier` (פריטה אקראית בלי אקורד קיבלה קודם 72%); תיקון: פספוס הוכרז לפני שהאודיו הגיע.
7. **2026-11-01 — אבחון ומדידה** — לוגים מובנים, `GuitarStrokeReferee`, מצב אבחון (WAV+JSON), ספסל זיהויי שווא. בלי שינוי התנהגות.
8. **2026-11-09 — כיול מול סימולציה מציאותית** — `realistic_sim.dart` + `mic_deviation_bench`; נגינה נכונה בפריטה 58%→83%, כיול אמין 16/16.

---

## Build history

| תאריך | סוג | נתיב APK | מה נכנס לבנייה |
|--------|-----|----------|----------------|
| 2026-11-09 | debug | `build/app/outputs/flutter-apk/app-debug.apk` | `1.0.2+1`: **מצב גיטרה כויל מול סימולציה מציאותית** (`test/support/realistic_sim.dart`: נגן עם ג׳יטר/פריטות חלקיות/גיטרה לא מכוונת + מיקרופון טלפון עם השהיה, HPF, EQ, הד חדר, AGC, רעש; ספסל `test/bench/mic_deviation_bench_test.dart`). שינויים: (1) מנוע — לכידה עצמאית לכל התקפה (`StrumCapture`), ה״לפני״ נלקח מלפני תחילת הפריטה; גלאי המשחק refractory 58ms בלי כלל rise; (2) `StrokeVerifier` — בלי חובת בס, מיתר פתוח קונסוננטי מותר, צליל זר נפטר רק אם לא התחזק (×1.15), ״מיתר נפרט״ = ≥2 מתדריו עלו, ↓ דורש שני שמות תו חדשים, ציון חזק/חלש; (3) `GuitarStrokeReferee` — דחיית ״צלילים שגויים״ לא שורפת את התו, פריטה חלשה נספרת רק עד 2.25 פעמות אחרי חזקה (במקום כלל העוגן); (4) כיול — מפריטות מאומתות, המוקדמת מבין החזקות לכל הבהוב. תוצאות (16 תנאים): כיול אמין 16/16 (קודם 3/8), טעות 19±16ms; נגינה נכונה פריטה 58%→83%, בס+פריטה 76%→87%, ארפג׳ו 91%→92.5%; שווא: פריטה פתוחה בלי אקורד 0.5%, אקורד שגוי 1%, צלצול 3–4%, מיתר בודד אקראי 6–10% |
| 2026-11-01 | debug | `build/app/outputs/flutter-apk/app-debug.apk` | `1.0.2+1`: **אבחון ומדידה בלבד — בלי שינוי ספים/כללים** (מספרי כל הספסלים זהים לפני/אחרי): `OnsetHopRecord` לכל hop (RMS, floor, Flux, סף, hf, rise, cover, ONSET/סיבות דחייה); `ChordMatchRecord` (רמה ב-dB וסטייה בסנטים לכל מיתר, צליל זר); `StrokeVerifier.lastDetail`; לוגיקת מצב גיטרה הועברה ל-`GuitarStrokeReferee` (משותף לאפליקציה ולספסל); `DetectionDiagnostics` → logcat `[Acords Diag]` (LEVEL כל 250ms / PEAK / STROKE) + שמירת WAV+JSON+log בסוף סיבוב (מתג «מצב אבחון», debug בלבד); ספסל `test/bench/false_positive_bench_test.dart` (10 מקרי FP + 2 ביקורת, ושחזור הקלטות אמיתיות מ-`test/fixtures/recordings`) |
| 2026-10-27 | debug | `build/app/outputs/flutter-apk/app-debug.apk` | `1.0.2+1`: **משחק קצב — אימות תוכן לכל פריטה במצב גיטרה** (קודם נשפט רק תזמון → פריטה אקראית על 4 מיתרים פתוחים קיבלה 72%): `StrumCapture` מהמנוע (ספקטרום ~116ms אחרי הפריטה + ספקטרום לפניה), `StrokeVerifier` (↓: בס + כל צלילי האקורד + בלי צליל זר + צליל חדש; ↑: בלי חובת בס; p/i/m/a: הצליל של המיתר הצפוי, חדש), «עוגן»: ↑ ו-i/m/a נספרים רק אם הייתה פגיעה בפעמה האחרונה; פריטה עם צלילים שגויים = פספוס; **תיקון באג**: פספוס הוכרז לפני שהאודיו הגיע (עיכוב שיפוט = כיול+260ms במצב גיטרה); `OnsetDetector`: שער רעש אדפטיבי (×3 מעל הרקע, נלמד רק מרגעים שקטים) גם במנוע הרגיל. ספסל: אקורד נכון 89%, פריטה אקראית בלי אקורד 3.1%, רעש+דפיקות 0 |
| 2026-10-23 | debug | `build/app/outputs/flutter-apk/app-debug.apk` | `1.0.2+1`: **כיול מיקרופון למשחק הקצב** — מסך `MicCalibrationScreen` (עיגול מהבהב 70BPM, 2 הכנה + 10 פריטות, חציון+MAD, נשמר רק אם אמין) נפתח אוטומטית במשחק הגיטרה הראשון וזמין מההגדרות; `LatencyCalibrator`/`LatencyTrim` (`lib/game/latency_calibration.dart`); הוסר הכיול בספירה וה-auto-cal שנשמר בכל סיבוב (היה ננעל על התו הלא נכון ומצטבר); תיקון ±100ms בלבד תוך משחק, לא נשמר; חותמות זמן לפריטה לפי מיפוי שעון-אודיו מינימלי (בלי ג׳יטר עיבוד/מסירה); מפתח חדש `mic_v2` |
| 2026-10-16 | debug | `build/app/outputs/flutter-apk/app-debug.apk` | `1.0.2+1`: **משחק קצב — מצב גיטרה**: `OnsetDetector.forRhythmGame` (פריטה רכה באצבעות/ניילון: 55%→88% בספסל, 0 התראות בשקט); כיול השהיית מיקרופון אוטומטי תוך כדי משחק (חציון היסטים מול התו הקרוב, ברירת מחדל 150ms); חלונות ±80/±170ms במצב גיטרה; מד עוצמת מיקרופון + הבזק «נשמע!» + אזהרה כשלא שומעים גיטרה |
| 2026-10-14 | debug | `build/app/outputs/flutter-apk/app-debug.apk` | `1.0.2+1`: **משחק קצב** (`RhythmGameScreen` + `lib/game/`: מסלול בפרספקטיבה, שיפוט ±70/±140ms, קומבו, כוכבים, מצב גיטרה=onset מהמיקרופון + בונוס אקורד ✓ / מצב מסך=החלקה ↓↑ + צליל Karplus–Strong `GameSoundService`, כיול בספירה); **שיעור פריטה** (`StrumLessonScreen`: אנימציית גיטרה בתקריב `GuitarStrumAnimation` → משחק ב-3 מהירויות → שיר לדוגמה `exampleSongId`); **ספריית שירים** (חיפוש, עברית/אנגלית, ז׳אנרים, רמות, קיבוץ); **מילים מלאות** + `section` ל-9 שירים PD; `language`/`genre` לכל שיר; ערכת נושא אינדיגו/סגול; כפתור «משחק קצב» בנגן השירים |
| 2026-10-13 | debug | `build/app/outputs/flutter-apk/app-debug.apk` | `1.0.2+1`: **תיקון קריסה בפתיחה (שוב)** — `MainActivity.kt` לא היה בגיט כי הכלל `chord_trainer/` ב־`.gitignore` תפס גם את `android/app/src/main/kotlin/com/chordtrainer/chord_trainer/`; הכלל עוגן ל־`/chord_trainer/` והקובץ נוסף. אומת ב־BlueStacks (מופע `Pie64_1`). טקסט כרטיס פריטות: 11 דפוסים |
| 2026-10-12 | debug | `build/app/outputs/flutter-apk/app-debug.apk` | `1.0.2+1`: **מנוע זיהוי חדש** (`ChordDetectionEngine` + `OnsetDetector` + `ChordMatcher` יחסי עם דחיית צליל זר) — פגיעה דורשת פריטה חדשה; **טיונר YIN+חידוד ספקטרלי**; **`ProgressService`** + כרטיס התקדמות/כוכבים/תגיות; +22 אקורדים, +8 שירים PD, +5 דפוסים; בדיקות `test/` + ספסל סינתטי `test/bench` |
| 2026-09-25 | debug | `build/app/outputs/flutter-apk/app-debug.apk` | `1.0.2+1`: ארכיטקטורה — טאב «שירים»; לימוד פריטות (6 דפוסים + 3 שלבים); `StrumPreviewService` mediaPlayer+WAV+ארפג׳ו; תיבות ריקות ל־instrumental |
| 2026-09-25 | debug | `build/app/outputs/flutter-apk/app-debug.apk` | `1.0.2+1`: שירים — מסלול מודרך 3 שלבים + נגן חופשי; תיקון `StrumPreviewService` (טיקים ↓/↑/✕); `songs.json` PD + instrumental; RTL+LTR; תיקון פרמטר `activeSegment` ב־`SongLyricLineView` |
| 2026-09-24 | debug | `build/app/outputs/flutter-apk/app-debug.apk` | `1.0.2+1`: שירים/פריטות — עזרה (↓↑✕− + רשת 1־ו־2־ו); השמעת דפוס בלולאה (`StrumPreviewService`); 4 שירים מוכרים עם אקורדים/BPM/דפוס (בלי מילים מקוריות מטעמי ©) |
| 2026-09-23 | debug | `build/app/outputs/flutter-apk/app-debug.apk` | `1.0.2+1`: שירים ופריטות — מודלים + `songs.json` (3 שירי אימון) + `SongCatalogService`; `StrummingPatternWidget` (highlight לפי BPM); `SongPracticeScreen` (סינון רמה, זיהוי אקורד / ליווי BPM); כפתור במסך הבית |
| 2026-09-23 | **release v1.0.1** | `releases/acords_v1.0.1.apk` (~48.9MB) | נעילת Release `1.0.1+1` — ארכיון ב־`HANDOFF_2.md`; `pubspec` הועלה ל־`1.0.2+1` לסבב השירים/פריטות |
| 2026-09-23 | debug | `build/app/outputs/flutter-apk/app-debug.apk` | `1.0.1+1`: שחזור עברית ב־`chord_blitz_screen.dart` (mojibake UTF-8/cp1252 אחרי עריכה קודמת) — כל מחרוזות ה־UI חזרו לעברית תקינה |
| 2026-09-23 | debug | `build/app/outputs/flutter-apk/app-debug.apk` | `1.0.1+1`: תיקון שורש לשתי בעיות זיהוי — (א) אינטרפולציה פרבולית ב-`estimatePitchCentsOffset` (קוונטיזציית bin גרמה ל-E2/A2/E3 להיראות −35¢ ולהיכשל ב-±25¢); (ב) באתגר: 2 פריימי perfect רצופים + חובת onset (פריטה חדשה, RMS×1.8 מעל מינימום 80–400ms אחורה) תוך 1s מהצבת האקורד — מונע "החלקה" כשמציבים אצבעות על מיתרים שעדיין מצלצלים |
| 2026-09-23 | debug | `build/app/outputs/flutter-apk/app-debug.apk` | `1.0.1+1`: איפוס מנוע זיהוי למקור — הוסרו הקלות בס/E, H2-H3 rescue, אנטי-גלישה, flush מיוחד; grace 350ms + edge-trigger סטנדרטי באתגר |
| 2026-09-23 | debug | `build/app/outputs/flutter-apk/app-debug.apk` | `1.0.1+1`: זיהוי בס נמוך (E/A/D וכו׳) — ±40¢ מתחת ל-160Hz, משקל H2/H3 גבוה + rescue אם H1 חלש, ספי אנרגיה/RMS מופחתים ל-80–160Hz |
| 2026-09-23 | debug | `build/app/outputs/flutter-apk/app-debug.apk` | `1.0.1+1`: אתגר — הקשחת אנטי-גלישה (תו ייחודי vs אקורד קודם, דחייה אם prev≥3 מיתרים, grace 280ms אחרי פגיעה); סיום «התחל מחדש»→countdown / «תפריט האתגר»→setup; wakelock_plus |
| 2026-09-23 | debug | `build/app/outputs/flutter-apk/app-debug.apk` | `1.0.1+1`: אתגר — מניעת גלישה (flush+discard PCM, onset אחרי שקט, דחיית previousChord, דרישת root); סיום — «התחל מחדש»→countdown, «תפריט האתגר»→setup; wakelock_plus בזמן משחק |
| 2026-09-23 | debug | `build/app/outputs/flutter-apk/app-debug.apk` | `1.0.1+1`: אתגר — שיא תמיד עם Grade (`שיא אישי: N נק׳ \| Grade X` / `טרם נקבע שיא ברמה זו`); תיאור רמה צמוד לשבבי 1–5 (לא מתחת לקבוצה מותאמת); E — grace 150ms, 1-frame לבס, match הרמוניות עליונות ±40¢ |
| 2026-09-23 | debug | `build/app/outputs/flutter-apk/app-debug.apk` | `1.0.1+1`: אתגר — שיא דינמי מ-SharedPreferences לפי רמה (`blitz_highscore_level_N`/`all`/`custom`), טקסט `טרם נקבע שיא ברמה זו`; E — grace 150ms, בלי 2-frame לבס, match על הרמוניות עליונות ±40¢ (התעלמות מ-E2 חלש) |
| 2026-09-23 | debug | `build/app/outputs/flutter-apk/app-debug.apk` | `1.0.1+1`: אתגר — שיא בכרטיס רמה בפורמט `שיא אישי: N נק׳ \| Grade X` / `טרם נקבע שיא`; זיהוי: grace 550ms+flush+2 פריימים; הקלת E (סנטים/H2-H3/באס חלש) |
| 2026-09-23 | debug | `build/app/outputs/flutter-apk/app-debug.apk` | `1.0.1+1`: אתגר — ציון שליטה (S/A/B/C) בכרטיס השיא; SFX עשיר יותר (קומבו/דחיפות/שיא חדש); זיהוי — grace 550ms+flush באפר+2 פריימים לאישור; הקלת E (סנטים/H2-H3/באס חלש×2) |
| 2026-09-22 | debug | `build/app/outputs/flutter-apk/app-debug.apk` | `1.0.1+1`: תיקון קריסה בפתיחה — נוסף `MainActivity.kt` שחסר מהריפו (ClassNotFound); `kotlin-android` ב־gradle. הערה: החלפת APK ממחשב אחר דורשת הסרת התקנה קודמת (חתימה שונה) |
| 2026-09-22 | debug | `build/app/outputs/flutter-apk/app-debug.apk` | `1.0.1+1`: אתגר — בוטל +3ש׳ לכל אקורד, בונוס זמן רק ברצף 5 (+5); תיקון נתיב debug ל־`build/.../flutter-apk` (לא `releases/`) |
| 2026-09-22 | debug | `build/app/outputs/flutter-apk/app-debug.apk` | `1.0.1+1`: הקמת סביבה ב־Desktop\chords; חוקי עבודה — debug APK + HANDOFF אחרי כל פעולה; עותק ריליס: `releases/acords_v1.0.1.apk` |
| 2026-09-11 | debug | `build/app/outputs/flutter-apk/app-debug.apk` | `1.0.1+1`: דיאגרמת בארה כפס רציף; אתגר — SnackBar לקבוצה ריקה + מניעת overflow במסך הכנה |
| 2026-09-01 | debug | `build/app/outputs/flutter-apk/app-debug.apk` | `1.0.1+1`: אתגר אקורדים — שיא אישי, ספירה לאחור+SFX, עזרה, קבוצה מותאמת, ציון שליטה/מהירות ממוצעת |
| 2026-09-01 | debug | `build/app/outputs/flutter-apk/app-debug.apk` | `1.0.1+1`: הקלה בזיהוי אקורד E / מיתרים נמוכים (סובלנות סנטים לפי תדר, משקלי H2/H3, perfect עם באס חלש אחד) |
| 2026-08-31 | debug | `build/app/outputs/flutter-apk/app-debug.apk` | `1.0.1+1`: מסך «אתגר האקורדים» (Chord Blitz) — טיימר 30ש׳, ניקוד/רצף, בחירת רמה, סיכום; כניסה ממסך הבית |
| 2026-08-26 | debug | `build/app/outputs/flutter-apk/app-debug.apk` | `1.0.1+1`: השמעת אקורד (סינתזת PCM + `audioplayers`) באימון ובספרייה (כרטיס + BottomSheet) |
| 2026-08-26 | debug | `build/app/outputs/flutter-apk/app-debug.apk` | `1.0.1+1`: דיאגרמה — תיקון חפיפות (הסרת עבה/דק; מרווח למספרי סריג; «סריג N» בעמודת הסריגים מימין) |
| 2026-08-26 | debug | `build/app/outputs/flutter-apk/app-debug.apk` | `1.0.1+1`: דיאגרמה — אצבעות 1–4 על הסריג, מספרי סריג בצד, חלון סריגים גבוה, תוויות מיתר |
| 2026-08-25 | debug | `build/app/outputs/flutter-apk/app-debug.apk` | `1.0.1+1`: הקפאת מעברים מהניווט; קטלוג 5 רמות + difficulty/category; סינון בספרייה ובאימון |
| 2026-08-18 | debug | `build/app/outputs/flutter-apk/app-debug.apk` | `1.0.1+1`: טיונר ללא גלילה — Column + Expanded (תו flex:2, מד flex:5, תחתית flex:2) + Wrap מיתרים קומפקטי |
| 2026-08-18 | debug | `build/app/outputs/flutter-apk/app-debug.apk` | `1.0.1+1`: טיונר — פריסה עם Scroll+גובה מד ~190–260; מעברים — ביטול blanking/grace על הטיק, תזמון לפי טיק קרוב ±250ms |
| 2026-08-04 | debug | `build/app/outputs/flutter-apk/app-debug.apk` | `1.0.1+1`: תיקון תזמון מעברים — grace 120ms, חלון ±~180ms עם קיזוז latency 150ms, blank בלי ניקוי באפר בכל דגימה, לוגים `[Acords Timing/Audio]` |
| 2026-08-02 | debug | `build/app/outputs/flutter-apk/app-debug.apk` | `1.0.1+1`: פריסת טיונר ללא גלילה (Column + Expanded), כמו אימון/מעברים |
| 2026-08-02 | debug | `build/app/outputs/flutter-apk/app-debug.apk` | `1.0.1+1`: מעברים — "בזמן!" והאצת BPM רק כשתזמון+אקורד נכונים; blanking 70ms לקליק מטרונום ב-FFT; פריסת אימון/מעברים ללא גלילה |
| 2026-07-28 | debug | `build/app/outputs/flutter-apk/app-debug.apk` | `1.0.1+1`: תיקון "הצלחה מיידית" במעברים (reset Buffer/FFT + grace 350ms + סף RMS + H1/H2/H3 למיתרים נמוכים) |
| 2026-07-17 | debug | `build/app/outputs/flutter-apk/app-debug.apk` | `1.0.1+1`: קטלוג 16 אקורדים + הצגת האקורדים החדשים בכרטיסיות הספרייה |
| 2026-07-17 | **release Windows** | `releases/windows.zip` (~12.5MB) | חבילת אפליקציית שולחן עבודה ל-v1.0.0+8 — **נעול ב-HANDOFF_2** |
| 2026-07-17 | **release v1.0.0** | `releases/acords_v1.0.0.apk` (~47MB) | buildCode +8: תיקון deadlock ב-stop; מעבר טאב = לחיצת עצור; MicCaptureGuard ברמת מסך — **נעול ב-HANDOFF_2** |
| 2026-07-17 | **release v1.0.0** | `releases/acords_v1.0.0.apk` (~47MB) | buildCode +5: rebuild מלא (כולל הורדת BPM רק עם האצה הדרגתית) |
| 2026-07-17 | **release v1.0.0** | `releases/acords_v1.0.0.apk` (~47MB) | buildCode +4: הורדת BPM רק כשהאצה הדרגתית פעילה |
| 2026-07-16 | **release v1.0.0** | `releases/acords_v1.0.0.apk` (~47MB) | buildCode +3: מטרונום mediaPlayer+seek (לא lowLatency); mic session/dispose; זיהוי מעברים (FFT clear + audioFocus none); WAV קליק |
| 2026-07-15 | debug | `build/app/outputs/flutter-apk/app-debug.apk` | טיונר: אוטו = מיתרים פתוחים בלבד; isActive חיזוק; מטרונום קולי; עזרת 1-2-3-4 |
| 2026-07-14 | debug | `build/app/outputs/flutter-apk/app-debug.apk` | טיונר עם בחירת מיתר (נעילה ליעד פתוח) |

---

---

## 1. מה זו האפליקציה

| שדה | ערך |
|-----|-----|
| שם | Chord Trainer (Acords) |
| package | `chord_trainer` |
| Android id | `com.chordtrainer.chord_trainer` |
| גרסה | `1.0.2+1` (פיתוח) |
| UI | עברית, RTL (`he_IL`); ערכת נושא כהה אינדיגו/סגול |
| ניהול מצב | **אין** Riverpod / Bloc / Provider — רק `StatefulWidget` + streams + `ChangeNotifier` (`ProgressService`) |

---

## 2. Tech stack

- Dart `^3.12.0`, Flutter 3.4x
- `record` — PCM16 מונו 44.1kHz מהמיקרופון (בלי AGC / echo cancel / noise suppress)
- `fftea` — FFT
- `permission_handler` — הרשאת מיקרופון
- `audioplayers` — SFX, השמעת אקורדים, צלילי משחק (mediaPlayer + WAV זמני + seek/resume)
- `path_provider` — WAV זמניים, שמירת קבצי אבחון
- `shared_preferences` — שיאים, התקדמות, כיול
- `wakelock_plus` — מסך דולק במשחקים

---

## 3. מבנה הקוד

```
lib/
  main.dart                       טעינת קטלוג + ProgressService.load() → MainShell
  models/
    chord_definition.dart         ChordDefinition / ChordNote / ChordCatalog, pitchClasses, soundsLike
    feedback_result.dart          ChordFeedback / StringFeedback / NoteStatus (+ extraNote, tuningShift)
    song_definition.dart          SongDefinition (language, genre), SongLine (section), SongGenres
    strumming_pattern.dart        StrummingPattern / PatternEvent (↓ ↑ ✕ - p i m a), exampleSongId
  audio/
    audio_analyzer.dart           מיקרופון → מנוע; feedbackStream / hitStream / onsetStream / strumCaptureStream; הקלטה לאבחון
    chord_detection_engine.dart   מנוע זיהוי על שעון דגימות; ChordHit; StrumCapture לכל התקפה
    onset_detector.dart           זיהוי פריטה (flux + שער רעש); preset forRhythmGame; OnsetHopRecord לאבחון
    spectrum_frame.dart           ספקטרום + bandPeak + noiseFloor + peaks
    fft_processor.dart            FFT, computeMagnitudesOfTail (חלון חלקי)
    pitch_tuner.dart, yin_pitch.dart   טיונר
    detection_diagnostics.dart    לוגים [Acords Diag] + שמירת WAV/JSON/log
    game_sound_service.dart       צלילי משחק (Karplus–Strong לכל אקורד, טיק, השתקה)
    strum_preview_service.dart, chord_audio_service.dart, blitz_sfx_service.dart, mic_capture_guard.dart
  chord/
    chord_matcher.dart            התאמת ספקטרום לאקורד; ChordMatchRecord לאבחון
  game/
    rhythm_chart.dart             תווים + תיבות לסיבוב (דפוס או שיר)
    rhythm_judge.dart             שיפוט תזמון, קומבו, ניקוד, כוכבים
    stroke_verifier.dart          בדיקת *מה* נוגן בכל פריטה (מצב גיטרה)
    guitar_stroke_referee.dart    שיפוט מצב גיטרה ללא UI (משותף לאפליקציה ולספסל)
    latency_calibration.dart      LatencyCalibrator (מסך כיול) + LatencyTrim (תיקון קטן תוך משחק)
    rhythm_game_painter.dart      ציור מסלול המשחק
  services/
    progress_service.dart         התקדמות, כוכבי משחק, כיול מיקרופון (SharedPreferences)
    chord_catalog_service.dart, song_catalog_service.dart, strum_pattern_catalog_service.dart, blitz_prefs.dart
  ui/
    main_shell.dart               5 טאבים
    home_screen.dart              כרטיס התקדמות + כניסה לאימון / אתגר / פריטות
    practice_screen.dart, chord_blitz_screen.dart, free_play_screen.dart, chord_library_screen.dart, tuner_screen.dart
    song_practice_screen.dart     ספריית שירים (חיפוש/שפה/ז׳אנר/רמה)
    song_player_screen.dart       נגן שיר + כפתור «משחק קצב»
    strumming_learning_screen.dart  רשימת דפוסים
    strum_lesson_screen.dart      שיעור: אנימציה → 3 מהירויות → שיר לדוגמה
    rhythm_game_screen.dart       משחק הקצב (מסך / גיטרה, כיול, אבחון)
    mic_calibration_screen.dart   כיול השהיית מיקרופון
    widgets/                      guitar_strum_animation, chord_fretboard_chart, progress_card, mastery_badge, …
    chord_transitions_screen.dart, song_guided_path_screen.dart   — לא מחוברים לניווט (קוד ישן)
```

---

## 4. ניווט

| # | טאב | מיקרופון |
|---|-----|----------|
| 0 | בית | לא |
| 1 | זיהוי חופשי | כן (`isActive`) |
| 2 | אקורדים (ספרייה) | לא |
| 3 | שירים | בתוך הנגן |
| 4 | טיונר | כן (`isActive`) |

**מהבית (push):** אימון אקורד בודד · אתגר האקורדים · לימוד פריטות → שיעור → משחק קצב / כיול.
**מהשירים:** נגן שיר → «משחק קצב».
**לא מחוברים:** `ChordTransitionsScreen`, `SongGuidedPathScreen` (הקבצים קיימים).

---

## 5. פיצ'רים לפי מסך

- **בית** — כרטיס «ההתקדמות שלך» (רצף ימים, אקורדים שנוגנו/בשליטה, רמה מומלצת, «המשך מאיפה שהפסקת»), 3 כרטיסי מצב.
- **אימון אקורד בודד** — בחירת רמה + אקורד (נזכר באחרון), משוב חי לכל מיתר, הודעת צליל זר («המיתר השישי מצלצל…»), חגיגה + רישום התקדמות רק על פגיעה אמיתית (`hitStream`).
- **אתגר האקורדים** — 30ש׳, +100 לאקורד, בונוס זמן ברצף 5, שיא + Grade לכל מאגר, זמן לכל אקורד נרשם בהתקדמות.
- **זיהוי חופשי** — כל 52 האקורדים; בין שני אקורדים שנשמעים אותו דבר מדווח הקל.
- **ספרייה** — 5 טאבים לפי רמה, כוכבי שליטה, ספירת «נוגנו X/Y», גיליון עם דיאגרמה גדולה + שורת התקדמות.
- **שירים** — חיפוש (שם/אמן/מילים), הכל/עברית/אנגלית, צ׳יפים לז׳אנר ולרמה, קיבוץ לפי ז׳אנר עם צבע/אייקון, תגיות («מילים מלאות», «✓ נוגן», כוכבי משחק). בנגן: תוויות «בית/פזמון», כפתור «משחק קצב».
- **לימוד פריטות** — 11 דפוסים עם כוכבים (מתוך 9). שיעור: (1) אנימציית גיטרה — מתחילה מכל הגיטרה ועושה זום לאזור הפריטה, יד+מפרט בקצב, מיתרים רוטטים, 3 מהירויות, הסבר לכל תנועה; (2) משחק ב-3 מהירויות (60%/80%/100%) שנפתחות בכוכב; (3) שיר לדוגמה במשחק.
- **משחק קצב** — סעיף 9.
- **טיונר** — סעיף 12.

---

## 6. נתונים — אקורדים (`assets/chords.json`)

**52 אקורדים** (EADGBE), כל אחד עם `difficulty` (1–5), `category`, ו־`finger` (1–4) על תווים לחוצים. אקורדים חדשים נוצרו מסקריפט שמחשב `midi`/`noteName` מהאצבוע; `test/content_test.dart` מוודא עקביות לכל הקטלוג.

| רמה | קטגוריה | אקורדים |
|-----|---------|---------|
| 1 | אקורדים פתוחים בסיסיים | C, G, D, E, A, Am, Em, Dm |
| 2 | פתוחים מתקדמים ושביעיות | C7, G7, D7, E7, A7, Cmaj7, Am7, Dsus4, Aadd9 |
| 3 | אקורדי בארה בסיסיים | F, Bm, F#m, B |
| 4 | אקורדי בארה מתקדמים | Fm, B7, C#m, F#7 |
| 5 | פאוור צ'ורדס | E5, A5, D5, G5, F5 |
| 2 (+) | חדשים | Em7, Dm7, Fmaj7, Cadd9, Asus2, Asus4, Dsus2, Esus4 |
| 3 (+) | חדשים | Gm, Cm, B♭, A · בארה, Am · בארה, G · בארה, C · בארה |
| 4 (+) | חדשים | Bm7, F#m7, G#m, C#m7, Dm · בארה |
| 5 (+) | חדשים | B5, C5 |

**זיהוי חופשי:** כל הקטלוג; כשני אקורדים מושלמים ונשמעים אותו דבר (`soundsLike`: אותם צלילים + אותו בס) מדווח הקל מביניהם (A פתוח ולא A · בארה).

מודל: `ChordDefinition` + `ChordDifficultyLevels` + `ChordNote.finger` + `diagramBaseFret`.

---

### 6א. שירים ודפוסים

**שירים (`assets/songs.json`, 17):** לכל שיר `language` (`he`/`en`), `genre` (`jewish`, `kids`, `folk`, `spiritual`, `holiday`, `pop_rock`), שורות עם `section` («בית 1», «פזמון»).

- **מילים מלאות (נחלת הכלל):** Amazing Grace (4 בתים), Oh! Susanna, When the Saints, Twinkle Twinkle, Red River Valley, Jingle Bells, Clementine (4 בתים + פזמון), Scarborough Fair, «שלום עליכם» (4 בתים); וגם Happy Birthday, «הנה מה טוב», «דוד מלך ישראל».
- **לא הורחבו בכוונה:** «התקווה» (אין אקורדים מאומתים לבית 2), House of the Rising Sun (הנוסח המקובל מהמאה ה-20), «יונתן הקטן» (©), Knockin' on Heaven's Door / Let It Be (© — אקורדים בלבד).

**דפוסים (`assets/strum_patterns.json`, 11):** basic_44, pop_rock_8, waltz_34, island_mute, ballad_soft, arpeggio_pima, boom_chick_44, waltz_bass_34, offbeat_reggae, ballad_68, folk_arpeggio — לכל אחד `practiceChordIds` ו-`exampleSongId`.

---

## 7. מעקב התקדמות (`ProgressService`)

SharedPreferences, מפתח `acords_progress_v1` (מסמך JSON אחד), נטען ב-`main.dart`.

- **לכל אקורד:** פגיעות, ימי תרגול, זמן הכי מהיר → שליטה: התחלה (≥1) / בתרגול (≥5) / בשליטה (≥15 ב-2 ימים לפחות).
- **בחירה אחרונה:** רמה + אקורד באימון.
- **שירים:** שלב מסלול מודרך + מספר השלמות.
- **פריטות:** שלב לכל דפוס (מספר מהירויות שעברו).
- **משחק:** כוכבים ושיא לכל מפתח (`pattern:<id>:<speed>`, `song:<id>`).
- **כיול:** `mic_v2` = השהיית מיקרופון מהמסך (ms). מפתחות ישנים (`mic`, `touch`) לא בשימוש.
- **רצף ימים.**

---

## 8. מנוע הזיהוי (Audio pipeline)

```
Mic PCM16 44.1k → AudioAnalyzer → ChordDetectionEngine (שעון דגימות, בלי DateTime)
   ├─ OnsetDetector: FFT 1024 / hop 512, spectral flux לוגריתמי מול חציון + פיק־פיקינג; refractory 140ms
   ├─ כל 2048 דגימות (~46ms): ספקטרום רק מהאודיו שאחרי הפריטה האחרונה (חלון גדל, מינ׳ 3072, עד 8192)
   ├─ ChordMatcher.evaluateFrame (SpectrumFrame): ספים יחסיים ל־bandPeak + רצפת רעש; היסט כיוון כללי (חציון);
   │    בס <170Hz גם דרך H2/H3 רק אם ההרמוניה לא "שייכת" לתו אחר באקורד; דחיית צליל זר ≥ −18dB
   │    שלא מוסבר ע״י הרמוניות התווים — אלא אם צלצל כבר לפני הפריטה ולא התחזק (residual)
   └─ ChordHit: ≥2 פריימים perfect רצופים, פריטה אחרי setTarget, גיל פריטה ≤1.5s, פגיעה אחת לפריטה
→ feedbackStream (UI חי) + hitStream (התקדמות)
```

- `MicCaptureGuard` — מיקרופון יחיד; מעבר טאב = עצירה מלאה (ללא שינוי)
- `blankInput` / `gracePeriod` עדיין קיימים (מדכאים ניתוח), אבל המסכים כבר לא צריכים grace בין אקורדים
- **ספסל בדיקה סינתטי** (`test/bench`, מדולג כברירת מחדל): `flutter test test/bench --run-skipped`. סינתיסייזר גיטרה (`test/support/guitar_synth.dart`): הרמוניות + אי־הרמוניות, דעיכה, פיזור מיתרים בפריטה, HPF של מיקרופון טלפון, רעש. המנוע הישן שמור ב־`test/support/legacy_*` להשוואה.

**תוצאות ספסל (סינתטי, 2026-10-12)** — ישן → חדש:

| מדד | ישן | חדש |
|-----|-----|-----|
| אקורד נכון מאושר | 97% | 100% |
| אקורד שגוי מאושר | 3.28% | 0% |
| מיתר חסר ועדיין "מושלם" | 62.6% | 38.9% |
| מיתר מושתק מצלצל ועדיין "מושלם" | 96.7% | 12.5% |
| זיהוי פריטות בפריטה מהירה | 32% | 91% |
| מעבר — פריטה אחת לאקורד | 160/186, 14 התקדמויות בלי לנגן | 185/186, 0 |
| זיהוי חופשי (52 אקורדים) | — | 100% |
| טיונר ±3¢ (כולל מיקרופון חלש בבס) | 91%, 18 טעויות מיתר/אוקטבה | 96%, 0 |

---

## 9. משחק הקצב

**מסך:** `RhythmGameScreen`. **נתונים:** `RhythmChart` (תיבה לכל אקורד; דפוס קצר חוזר למילוי התיבה; בשיר — תיבה לכל קטע עם מילים).

- **מסלול בפרספקטיבה** — התווים מתקרבים מהאופק ומתגדלים; קו פגיעה = 6 מיתרים שרוטטים; ↓ בנתיב שמאל (טורקיז), ↑ בימין (ענבר), ✕/אצבעות במרכז (סגול); פגיעה עפה בכיוון שלה + ניצוצות.
- **שיפוט (`RhythmJudge`):** מסך — מושלם ±70ms / טוב ±140ms; גיטרה — ±80 / ±170ms. קומבו → מכפיל ×1–×4; כוכבים לפי דיוק (≥60% / 78% / 92%).
- **מצב מסך:** נגיעה = שיפוט מיידי + צליל אקורד (Karplus–Strong); החלקה בכיוון הלא נכון → «כיוון!» (מורד ל«טוב»).
- **מצב גיטרה:** כל פריטה נבדקת גם בתוכן (9א); מד עוצמה + «🎸 נשמע!»; אזהרה אחרי 3ש׳ שקט; מטרונום כבוי (המיקרופון היה שומע אותו).
- **ספירה לאחור:** רק «מתחילים בעוד…» — אין כיול בספירה.
- **תוצאות:** כוכבים, ניקוד, דיוק, מושלם/טוב/פספוס, קומבו, «אקורד/צליל שגוי», אקורדים ✓, איחור מיקרופון, כפתור «כיילו מחדש» כשהדיוק נמוך, נתיב קבצי אבחון.

### כיול המיקרופון

- **מסך `MicCalibrationScreen`** — עיגול מהבהב ב-70BPM, 2 הבהובי הכנה + עד 10 פריטות. נפתח אוטומטית לפני משחק הגיטרה הראשון; זמין גם מהגדרות הסיבוב ומהתוצאות.
- **חישוב (`LatencyCalibrator`)** — רק התקפות שעברו `StrokeVerifier.attackStrength ≥ 0.3`; לכל הבהוב — המוקדמת מבין החזקות (≥70% מהחזקה ביותר); חציון + MAD; נשמר רק אם אמין (≥6 פריטות, פיזור ≤75ms).
- **תוך משחק (`LatencyTrim`)** — תיקון של עד ±100ms מהערך המכויל, לא נשמר.
- **חותמות זמן** — מיפוי שעון-אודיו → שעון קיר לפי המינימום של (זמן הגעה − זמן אודיו), בלי ג׳יטר עיבוד/מסירה.
- **עיכוב שיפוט** — במצב גיטרה תו מוכרז כפספוס רק אחרי כיול + 260ms (`GuitarStrokeReferee.judgeDelayMs`), כי האודיו מגיע באיחור.

### 9א. מצב גיטרה — איך נשפטת פריטה (2026-11-09)

```
OnsetDetector.forRhythmGame → כל התקפה = מועמד (refractory 58ms)
  → ChordDetectionEngine: StrumCapture לכל מועמד בנפרד
       frame    = ספקטרום 116ms שאחרי ההתקפה (+10ms דילוג)
       residual = ספקטרום 93ms שלפני *תחילת הפריטה* (התקפות עד 120ms זו מזו = פריטה אחת, מבט לאחור ≤200ms)
  → GuitarStrokeReferee.onCapture: התו הלא-שפוט הקרוב (±170ms אחרי כיול) → StrokeVerifier.check
       wrongNotes  → התו נשאר פתוח; אם לא הגיעה פריטה נכונה עד סוף החלון → ״אקורד/צליל לא נכון״
       noFreshSound→ מתעלמים (רעש / אקורד מצלצל)
       ok + strong → פגיעה, ומסמן ״מנגנים״ ל-2.25 פעמות
       ok + weak   → פגיעה רק אם ״מנגנים״ (אחרת unanchored)
```

**כללי `StrokeVerifier`** (כולם יחסיים; נקבעו מול הסימולציה):
- ↓: אין צליל זר; כל שמות התו של האקורד נשמעים; חסרים לכל היותר 2 מיתרים; freshness ממוצע ≥0.26; מיתרים ״שנפרטו״ משני שמות תו לפחות. תמיד strong.
- ↑: אין צליל זר; כל שמות התו נשמעים (מצלצלים מה-↓); לפחות מיתר דק אחד ״נפרט״ עם freshness ≥0.15 (strong ≥0.45).
- תו אצבע: המיתר הצפוי ״נפרט״ (מתחת ל-170Hz גם תדר אי-זוגי), בטווח ±55 סנט או שרוב סדרת ההרמוניות שלו הופיעה (≥4 מ-6); freshness ≥0.15 (strong ≥0.30).
- ״מיתר נפרט״ = לפחות 2 מ-6 התדרים הראשונים שלו עלו ב-≥30% (תדר משותף בודד עם מיתר אחר לא מספיק).
- לא נדרש: מיתר הבס (לא ניתן לאימות דרך מיקרופון טלפון); שקט במיתר פתוח ששייך לאקורד (מי נמוך מתחת ל-C/Am, לה מתחת ל-D).

**מגבלות ידועות (מהסימולציה):** פריטה אקראית על מיתר פתוח בודד עדיין מקבלת ~6–10% (בעיקר כשהמיתר שייך באמת לאקורד, למשל רה/סול/סי פתוחים באקורד G); דיבור/זמזום ליד הטלפון בארפג׳ו ~12% כשהקול עובר על התו הנכון; כ-20% מפריטות ה-↑ הרכות עדיין לא נספרות; ↑ שנספר מוקדם מדי (סטיית תזמון עד −95ms ב-5% מהמקרים). כל המספרים מסימולציה — לאמת בהקלטות אמיתיות דרך ״מצב אבחון״.

---

## 10. מצב אבחון (debug בלבד)

מתג «מצב אבחון (לוגים + הקלטה)» במסך הפתיחה של משחק הגיטרה.

**לוגים ל-logcat** (`adb logcat -s flutter | findstr "Acords Diag"`):
- `LEVEL` — כל 250ms: RMS ו-Flux (מינ׳/חציון/מקס׳), סף ה-Flux, רמת הרקע.
- `PEAK` — כל שיא Flux עם כל המספרים ו-`ONSET` או סיבות הדחייה (`flux`, `level`, `gate`, `rise`, `cover`, `attack`, `refractory`).
- `STROKE` — כל פריטה שנשפטה: תוצאה, סיבה, וניתוח `ChordMatcher` לכל מיתר (dB יחסית, סנטים, סטטוס, צליל זר).

**קבצים בסוף סיבוב** — `/sdcard/Android/data/com.chordtrainer.chord_trainer/files/diagnostics/`:
`NAME.log`, `NAME.wav` (האודיו הגולמי), `NAME.json` (דפוס, אקורדים, BPM, כיול, היסטים בזמן, תוצאה).

```
adb pull /sdcard/Android/data/com.chordtrainer.chord_trainer/files/diagnostics
```

מעתיקים זוגות `.json`+`.wav` ל-`test/fixtures/recordings/` (אפשר להוסיף `"label": "idle" | "random" | "correct"`), והספסל `false_positive_bench` משחזר אותם דרך אותו קוד בדיוק ומציג את התוצאה ליד מה שהאפליקציה הראתה.

---

## 11. הסימולציה (מה יודעים ומה לא)

**`test/support/realistic_sim.dart`:**
- **נגן (`PlayerModel`)** — הטיה וג׳יטר בתזמון, משך פריטה 25–80ms, דילוג על בס/מיתר עליון, ↑ שמגיע ל-2–4 מיתרים, מיתר פתוח מיותר מתחת לאקורד, גיטרה לא מכוונת (±15¢ + פיזור), אצבעות/מפרט, עוצמה. מיתרים שמשתנים באקורד הבא נעצרים, פתוחים ממשיכים לצלצל.
- **טלפון (`PhoneMic`)** — השהיה 80–320ms, HPF 70–260Hz (12/24dB לאוקטבה), EQ, הד חדר, AGC, רעש, עוצמה.
- **סינתיסייזר מיתר (`guitar_synth.dart`)** — הרמוניות עם אי-הרמוניות, דעיכה שונה לכל הרמוניה, רעש מפרט.

**תוצאות אחרונות (16 תנאים אקראיים, 2026-11-09):**

| | לפני הסבב | אחרי |
|---|---|---|
| כיול אמין | 3/8 | **16/16** |
| טעות כיול | עד −128ms | **19±16ms** |
| נגינה נכונה — פריטה (pop_rock_8) | 58% | **83%** |
| נגינה נכונה — בס+פריטה (boom_chick) | 76% | **87%** |
| נגינה נכונה — ארפג׳ו (pima) | 91% | **92.5%** |
| פריטה על מיתרים פתוחים בלי אקורד | 0% | 0.5% (פריטה) / 4.5% (ארפג׳ו) |
| אקורד שגוי | 0% | 0–1% |
| אקורד מצלצל בלי לנגן | 2–5% | 3–4% |
| מיתר פתוח בודד אקראי | 0% | 6–10% |

**ספסל זיהויי שווא עם מיקרופון נקי** (`false_positive_bench`): ביקורת נכונה 91–97%; שקט/רעש/דפיקות/השתקות 0%; דיבור ליד הטלפון — 0% בפריטה, ~12% בארפג׳ו.

**חשוב:** זו הערכה של איך טלפון שומע גיטרה, לא מדידה של מכשיר אמיתי. השלב הבא הוא הקלטות אמיתיות (סעיף 10).

---

## 12. טיונר

**מנוע:** `TunerPitchEstimator` — YIN מחליט איזה תו (עמיד לאוקטבות כשהבסיס חלש), ואז חידוד התדר על ספקטרום 8192 (H1, או H2/2, H3/3). חציון 3 קריאות. במיתר נעול: חיפוש ±8 חצאי טון סביבו.

1. **בחירת מיתר** — `אוטו` + מיתרים 6→1 (`Wrap` קומפקטי)
2. **אוטו = מיתרים פתוחים בלבד** — ±2 חצאי־טון מ־`openMidi`; אחרת `awaitingOpenString`
3. **מיתר נעול** — חיפוש H1/H2/H3, cents מול יעד פתוח
4. **פריסה** — `Column` ללא `SingleChildScrollView`; מד `flex: 5`
5. **isActive** — יציאה מטאב → עצירה מלאה; `MicCaptureGuard`

In-tune: ±5 סנט (לוגיקה). מחוג: צביעה ירוקה ~±25.

---

---

## 13. דיאגרמות אקורדים

`ChordFretboardFrame` / `ChordFretboardChart`:

- נקודות עם **מספר אצבע** (1 מורה · 2 אמה · 3 קמיצה · 4 זרת)
- **מספרי סריג** בעמודה ימנית (מרווח מהעיגולים)
- **חלון סריגים** — אם `maxFret > 4` מתחיל מ־`maxFret - 3` (סריג 2/3…); תווית «סריג N» בעמודת הסריגים (לא נדרסת ע״י X במיתר 1)
- תוויות מיתר מתחת: `6·E` … `1·e`
- `LayoutBuilder` + `FittedBox`; ב־grid: `Expanded` סביב הדיאגרמה

---

---

## 14. Build, התקנה וסביבה

- **בנייה:** `flutter build apk --debug` → `build/app/outputs/flutter-apk/app-debug.apk` (לוקח 1–10 דקות). מעתיקים ל-`Downloads` בשם תיאורי.
- **הרשאות:** Android `RECORD_AUDIO`; iOS `NSMicrophoneUsageDescription`.
- **חתימת release:** עדיין מפתחות debug — לפני חנות צריך keystore.
- **SSL / Gradle:** Avast מיירט HTTPS. `android/gradle.properties` מפנה ל-`C:/Users/noam1/.gradle/windows-truststore.jks`; תעודת השורש של Avast יובאה אליו (גיבוי: `windows-truststore.jks.bak-20261012`). אם Avast יחליף תעודה — לייבא שוב.
- **קבצים שמשתנים מ-`flutter pub get`:** `linux/`, `macos/`, `windows/` (plugin registrants) ו-`pubspec.lock` — מחזירים עם `git checkout -- linux macos windows pubspec.lock` לפני commit.
- **`.gitignore`:** הכלל `/chord_trainer/` מעוגן לשורש — אחרת הוא מסתיר את `MainActivity.kt` והאפליקציה קורסת בפתיחה.
- **Push:** מנהל האישורים של Windows שומר משתמש ישן (`roeif`) בלי הרשאה → 403. פתרון לפקודה אחת:
  `git -c credential.helper= -c credential.helper='!gh auth git-credential' push`
  (`gh` מחובר כ-`roee-design`). לתיקון קבוע: למחוק את `git:https://github.com` ב-Credential Manager, או `gh auth setup-git`.
- **Git author:** אין זהות גלובלית; קומיטים עם `git -c user.name=noam1 -c user.email=...`.
- **BlueStacks:** המופע הראשי (`Pie64`) שבור — חסר `C:\ProgramData\BlueStacks_nxt\Engine\Pie64\Data.vhdx`. המופע «Brawl Stars» (`Pie64_1`, adb `127.0.0.1:5565`) עובד:
  `"C:\Program Files\BlueStacks_nxt\HD-Player.exe" --instance Pie64_1`, ואז `adb connect 127.0.0.1:5565` ו-`adb install -r <apk>`. BlueStacks נסגר לפעמים באמצע; המיקרופון של המחשב באמולטור לא מייצג טלפון.
- **adb:** `C:\Users\noam1\platform-tools\adb.exe`.

---

## 15. בדיקות וספסלים

**`flutter test`** (35 בדיקות, ~30ש׳): content, detection_regression, stroke_verification, guitar_mode_simulation, latency_calibration, rhythm_game, progress_service, widget.

**ספסלים** (`test/bench`, מדולגים כברירת מחדל — `flutter test <file> --run-skipped`):

| ספסל | מה מודד |
|---|---|
| `mic_deviation_bench_test.dart` | **הראשי למצב גיטרה:** כיול, נגינה נכונה, סיבות לתווים שלא נספרו, סטיות תזמון/רמה/גובה לכל מיתר, זיהויי שווא — דרך טלפונים מדומים. `--dart-define=CONDITIONS=16`, `--dart-define=FP=false` |
| `false_positive_bench_test.dart` | 10 מקרי שווא + 2 ביקורת דרך הצינור של האפליקציה; משחזר הקלטות מ-`test/fixtures/recordings`. פלט: `build/false_positive_bench/` |
| `stroke_verify_bench_test.dart` | אימות פריטות: אקורד נכון / פתוח אקראי / ארפג׳ו / מצב סרק |
| `matcher_bench_test.dart` | `ChordMatcher` ישן מול חדש |
| `onset_bench_test.dart`, `onset_game_bench_test.dart` | זיהוי פריטות (רגיל / משחק) |
| `transition_bench_test.dart` | מעברי אקורדים בשירים |
| `robustness_bench_test.dart` | כיוון, רעש, עוצמה, זיהוי חופשי |
| `tuner_bench_test.dart` | טיונר ישן מול YIN |

**תמיכה:** `game_replay.dart` (משחזר סיבוב בדיוק כמו האפליקציה), `realistic_sim.dart`, `sim_session.dart` (סימולציית מסך כיול), `fp_scenarios.dart`, `stroke_scenarios.dart`, `guitar_synth.dart`, `legacy_*` (מנוע ישן להשוואה).

---

## 16. פערים ידועים ומה הלאה

**הכי חשוב:**
1. **אין אימות על מכשיר אמיתי.** כל מספרי הזיהוי מסימולציה. הצעד הבא: כמה סיבובים עם «מצב אבחון» (סרק / אקראי / נכון) → `test/fixtures/recordings` → ספסל → כיוון לפי מה שהמספרים מראים.
2. **פריטות ↑ רכות** — כ-20% עדיין לא נספרות בסימולציה; ↑ נשפט לפעמים מוקדם מדי (עד −95ms ב-5%).
3. **מיתר פתוח בודד אקראי** — 6–10% מתקבלים (בעיקר כשהמיתר באמת שייך לאקורד).
4. **דיבור/זמזום ליד הטלפון בארפג׳ו** — ~12%.

**נוספים:**
5. README מיושן.
6. **אוקטבות מוכפלות** — מיתר שהתו שלו הוא הרמוניה של מיתר נמוך יותר (E4 מעל E3) לא ניתן להבחנה; "מיתר חסר" כזה עלול להיחשב מושלם באימון רגיל.
7. **מיתר הבס לא נבדק במצב גיטרה** — מיקרופון טלפון לא שומע אותו מספיק.
8. **שינוי אקורד לגאטו** נספר לפעמים כפריטה.
9. **בארה בצוואר גבוה** — A פתוח מאושר גם כ-«A · בארה».
10. **צלילי האפליקציה** (תצוגת פריטה, מטרונום) נקלטים במיקרופון — לכן מטרונום כבוי במצב גיטרה.
11. **«יונתן הקטן»** מסומן `publicDomain: true` אבל המילים מוגנות (קיפניס נפטר 1990) — להחליט: instrumental או הסרת מילים.
12. **קוד לא מחובר:** `chord_transitions_screen.dart`, `song_guided_path_screen.dart`.
13. חוסר עקביות 5¢ / 25¢ במחוג הטיונר.

**תוקן בעבר:** overflow דיאגרמות, deadlock מעברים, MainActivity חסר, פספוס לפני שהאודיו הגיע, כיול שהצטבר, פריטה אקראית שקיבלה 72%, ועוד — ראו Build history.

---

## 17. סטטוס מוצר

| אזור | מצב |
|------|-----|
| שלד + ניווט (5 טאבים) | ✅ |
| אימון אקורד + אתגר + זיהוי חופשי | ✅ |
| ספרייה + דיאגרמות (52 אקורדים) | ✅ |
| מנוע זיהוי מבוסס פריטה + מעברים | ✅ (סימולציה) |
| טיונר YIN | ✅ |
| מעקב התקדמות | ✅ |
| ספריית שירים (חיפוש, שפה, ז׳אנר, מילים) | ✅ |
| שיעורי פריטה + אנימציה | ✅ |
| משחק קצב — מצב מסך | ✅ (אושר על ידי המשתמש) |
| משחק קצב — מצב גיטרה | 🟡 כויל בסימולציה, לאמת על מכשיר |
| מצב אבחון + ספסלים | ✅ |
| store release | 🔜 |

---

## 18. קבצים חשובים

1. **זיהוי:** `lib/audio/chord_detection_engine.dart`, `lib/audio/onset_detector.dart`, `lib/chord/chord_matcher.dart`
2. **מצב גיטרה:** `lib/game/stroke_verifier.dart`, `lib/game/guitar_stroke_referee.dart`, `lib/game/latency_calibration.dart`
3. **משחק:** `lib/ui/rhythm_game_screen.dart`, `lib/game/rhythm_judge.dart`, `lib/game/rhythm_chart.dart`, `lib/game/rhythm_game_painter.dart`
4. **שיעורים:** `lib/ui/strum_lesson_screen.dart`, `lib/ui/widgets/guitar_strum_animation.dart`
5. **שירים:** `assets/songs.json`, `lib/ui/song_practice_screen.dart`, `lib/ui/song_player_screen.dart`
6. **התקדמות:** `lib/services/progress_service.dart`, `lib/ui/widgets/progress_card.dart`
7. **אבחון:** `lib/audio/detection_diagnostics.dart`, `test/fixtures/recordings/README.md`
8. **סימולציה:** `test/support/realistic_sim.dart`, `test/bench/mic_deviation_bench_test.dart`
9. **קטלוג:** `assets/chords.json`, `lib/models/chord_definition.dart`

---

## הוראות עדכון (לסוכן)

- **`HANDOFF_2.md` — אסור לערוך.** ארכיון Release **v1.0.1 (+1)** בלבד.
- **`HANDOFF.md` — מסמך העבודה היחיד** לתיעוד באגים, פיצ'רים ובנייות דיבאג.

אחרי `flutter build apk` (debug או release):

1. הוסף שורה לטבלת **Build history**.
2. עדכן את הסעיפים הרלוונטיים (מצב נוכחי, פיצ'רים, סטטוס, פערים).
3. **Release:** העתק ל-`releases/` רק אחרי `flutter build apk --release` מכוון במפורש — לא בדיבאג.
4. כל שינוי בזיהוי: להריץ קודם את `mic_deviation_bench` ו-`false_positive_bench` ולתעד את המספרים לפני/אחרי.
