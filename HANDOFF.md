# מסמך מסירה — Chord Trainer (Acords)

מסמך עבודה שוטף למפתח / AI. **כל שינוי, באג או פיצ'ר מעתה מתועדים כאן בלבד.**

**נתיב הפרויקט:** `c:\Users\Fisher-home\Desktop\chords`

> **Release נעול:** `HANDOFF_2.md` + `releases/acords_v1.0.1.apk` = snapshot רשמי של **v1.0.1 (+1)**. **אין לערוך את `HANDOFF_2.md`.**

### חוקי עבודה (חובה אחרי כל פעולה)

1. בונים **APK דיבאג** → `build/app/outputs/flutter-apk/app-debug.apk` (לא מעתיקים ל־`releases/`).
2. מעדכנים את **`HANDOFF.md`** בלבד (מצב נוכחי + Build history).

---

## מצב נוכחי — סבב פיתוח

| שדה | ערך |
|-----|-----|
| גרסת פיתוח (`pubspec.yaml`) | `1.0.2+1` |
| Release יציב (נעול) | `1.0.1+1` → `releases/acords_v1.0.1.apk` (~48.9MB) — ראו `HANDOFF_2.md` |
| APK דיבאג | `build/app/outputs/flutter-apk/app-debug.apk` |
| סביבת עבודה | Flutter 3.47.5 + JDK 17 + Android SDK ב־`Fisher-home\Desktop\chords` (2026-09-25) |
| סבב נוכחי | ארכיטקטורת שירים/פריטות: טאב «שירים», לימוד פריטות מרכזי, תיקון שמע, ארפג׳ו, תיבות ריקות ל־© |

### כיוון ארכיטקטורה נוכחי (`1.0.2+1`)

1. **מעברי אקורדים מוקפאים** — הוסרו ממסך הבית ומהניווט; `lib/ui/chord_transitions_screen.dart` נשאר בקוד אך לא נטען (אין טיימרים ברקע).
2. **קטלוג לפי רמת קושי** — `difficulty` (1–5) + `category` לכל אקורד; **30 אקורדים** ב־`assets/chords.json`.
3. **ספרייה + אימון** — סינון/טאבים לפי 5 רמות; באימון FilterChips לרמה + דרופדאון מסונן.
4. **דיאגרמת אקורדים** — מספר אצבע על הסריג (1–4), מספרי סריג בצד, חלון מתחיל מסריג 2/3 כשצריך, תוויות מיתר `6·E`…`1·e` מתחת.
5. **טיונר** — פריסה ללא גלילה: `Column` + `Expanded` (תו flex:2, מד flex:5, תחתית flex:2).
6. **אתגר האקורדים** — שיא עם ציון שליטה; SFX; grace 350ms; 2 פריימי perfect + onset.
7. **מנוע זיהוי** — אינטרפולציה פרבולית + onset tracker.
8. **שירים ופריטות** — טאב «שירים» בניווט התחתון (נגן חופשי: אקורדים/BPM/פריטה/מילים PD); מסך בית → **לימוד פריטות** (6 דפוסים ב־`strum_patterns.json`, מסלול 3 שלבים); `StrumPreviewService` = mediaPlayer + WAV זמני + seek/resume + ארפג׳ו pitched; instrumental = תיבות `| C | G |` בלי מילים מזויפות.

---

## Build history

| תאריך | סוג | נתיב APK | מה נכנס לבנייה |
|--------|-----|----------|----------------|
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

## 1. מה זו האפליקציה

אפליקציית Flutter לאימון אקורדים בגיטרה. מאזינה למיקרופון, מריצה FFT, ומשווה את הצליל לאקורדים מ־`assets/chords.json`.

| שדה | ערך |
|-----|-----|
| שם | Chord Trainer |
| package | `chord_trainer` |
| Android id | `com.chordtrainer.chord_trainer` |
| גרסה | `1.0.2+1` (פיתוח) |
| UI | עברית, RTL (`he_IL`) |
| מצב | **פיתוח** — Release נעול: `releases/acords_v1.0.1.apk` (v1.0.1+1) — ראו `HANDOFF_2.md` |

**אין** Riverpod / Bloc / Provider — רק `StatefulWidget` + streams.

---

## 2. Tech stack

- Dart `^3.12.0`, Flutter 3.12+
- `record` — PCM16 מהמיקרופון
- `fftea` — FFT
- `permission_handler` — הרשאת מיקרופון
- `audioplayers` — נשאר בפרויקט (מטרונום למסך מעברים המוקפא); לא בשימוש בניווט הנוכחי

---

## 3. מבנה `lib/`

```
lib/
  main.dart
  models/          chord_definition.dart (difficulty/category/finger), feedback_result.dart
  services/        chord_catalog_service.dart
  audio/           audio_analyzer, pitch_tuner, fft_processor, ring_buffer, frequency_utils
  chord/           chord_matcher.dart
  ui/              מסכים + widgets (fretboard, tuner gauge, help, confetti…)
                   chord_transitions_screen.dart — מוקפא, לא מנווטים אליו
```

---

## 4. ניווט

| # | מסך | mic | isActive |
|---|-----|-----|----------|
| 0 | Home | לא | — |
| 1 | FreePlay | כן | `_selectedIndex == 1` |
| 2 | Library | לא | — |
| 3 | Tuner | כן | `_selectedIndex == 3` |

**Push מבית:** `PracticeScreen` בלבד.

**מוקפא (לא ב־UI):** `ChordTransitionsScreen` — הקובץ קיים; אין כניסה מהבית/טאבים.

---

## 5. נתונים — `assets/chords.json`

**30 אקורדים** (EADGBE), כל אחד עם `difficulty` (1–5), `category`, ו־`finger` (1–4) על תווים לחוצים.

| רמה | קטגוריה | אקורדים |
|-----|---------|---------|
| 1 | אקורדים פתוחים בסיסיים | C, G, D, E, A, Am, Em, Dm |
| 2 | פתוחים מתקדמים ושביעיות | C7, G7, D7, E7, A7, Cmaj7, Am7, Dsus4, Aadd9 |
| 3 | אקורדי בארה בסיסיים | F, Bm, F#m, B |
| 4 | אקורדי בארה מתקדמים | Fm, B7, C#m, F#7 |
| 5 | פאוור צ'ורדס | E5, A5, D5, G5, F5 |

מודל: `ChordDefinition` + `ChordDifficultyLevels` + `ChordNote.finger` + `diagramBaseFret`.

---

## 6. Audio pipeline

```
Mic (PCM16, 44100) → RingBuffer(8192) → Hann+FFT → Matcher / PitchTuner → Stream → UI
```

- `AudioAnalyzer` — אקורדים (~80ms); `blankInput` / grace קיימים לשימוש עתידי; במעברים המוקפאים אין קריאה פעילה מה־UI
- `PitchTuner` — טיונר (~60ms, 70–700 Hz)
- **try-catch** סביב `startStream` — לא קורס על כשל mic/הרשאות
- `MicCaptureGuard` — מיקרופון יחיד; מעבר טאב = עצירה מלאה

---

## 7. פיצ'רים לפי מסך

- **Home** — כניסה לאימון אקורד בודד (+ טיפ על 5 רמות)
- **Practice** — בחירת רמה (FilterChips) + אקורד; משוב חי; דיאגרמה חיה; tip + confetti
- **Free play** — זיהוי אקורד מהקטלוג המורחב
- **Library** — `TabBar` ל־5 רמות; grid קומפקטי; sheet עם דיאגרמה מוגדלת + רמה/קטגוריה
- **Tuner** — פריסה ללא גלילה (flex 2/5/2); בחירת מיתר; מד סנטים
- **Transitions** — **מוקפא** (לא בניווט)

---

## 8. טיונר

1. **בחירת מיתר** — `אוטו` + מיתרים 6→1 (`Wrap` קומפקטי)
2. **אוטו = מיתרים פתוחים בלבד** — ±2 חצאי־טון מ־`openMidi`; אחרת `awaitingOpenString`
3. **מיתר נעול** — חיפוש H1/H2/H3, cents מול יעד פתוח
4. **פריסה** — `Column` ללא `SingleChildScrollView`; מד `flex: 5`
5. **isActive** — יציאה מטאב → עצירה מלאה; `MicCaptureGuard`

In-tune: ±5 סנט (לוגיקה). מחוג: צביעה ירוקה ~±25.

---

## 9. UI — דיאגרמות אקורדים

`ChordFretboardFrame` / `ChordFretboardChart`:

- נקודות עם **מספר אצבע** (1 מורה · 2 אמה · 3 קמיצה · 4 זרת)
- **מספרי סריג** בעמודה ימנית (מרווח מהעיגולים)
- **חלון סריגים** — אם `maxFret > 4` מתחיל מ־`maxFret - 3` (סריג 2/3…); תווית «סריג N» בעמודת הסריגים (לא נדרסת ע״י X במיתר 1)
- תוויות מיתר מתחת: `6·E` … `1·e`
- `LayoutBuilder` + `FittedBox`; ב־grid: `Expanded` סביב הדיאגרמה

---

## 10. Build / הרשאות

- Android: `RECORD_AUDIO`
- iOS: `NSMicrophoneUsageDescription`
- Release signing: עדיין מפתחות debug (template) — לפני store release
- **Release נעול:** `releases/acords_v1.0.1.apk` (v1.0.1+1) — אל תדרוס בבניית דיבאג; פרטים ב־`HANDOFF_2.md`
- **דיבאג:** `build/app/outputs/flutter-apk/app-debug.apk`
- אם `flutter build` נכשל בנתיב OneDrive/עברית — לבנות מעותק ב-`C:\AcordsBuild`
- **Windows (היסטורי, v1.0.0):** `releases/windows.zip` — לא עודכן בנעילת 1.0.1

---

## 11. פערים ידועים (post-v1)

1. README מיושן
2. `test/widget_test.dart` לא תואם UI עברי
3. אין persistence (רמה / אקורד אחרון)
4. Pitch = peak-FFT, לא YIN
5. ספי זיהוי אמפיריים — תלוי מכשיר
6. חוסר עקביות 5¢ vs 25¢ במחוג טיונר
7. מסך מעברים מוקפא — להחזיר / למחוק סופית בהחלטת מוצר
8. דיאגרמות על סריגים גבוהים (למשל C#m) — 4 סריגים בחלון; ייתכן שיפור ויזואלי נוסף לבארה

**תוקן ב-v1.0.0 (+8):** overflow דיאגרמות; mic ב-IndexedStack; deadlock מעברים; מטרונום; זיהוי במעברים.

**תוקן / השתנה ב-`1.0.1+1`:**
- תיקון "הצלחה מיידית" במעברים (לפני ההקפאה)
- קטלוג → 30 אקורדים + 5 רמות
- הקפאת מעברים מהניווט
- דיאגרמה עם אצבעות + סריג בצד + חלון גבוה
- טיונר ללא גלילה מאוזן

---

## 12. סטטוס מוצר — v1.0.1 (פיתוח)

| אזור | מצב |
|------|-----|
| שלד + ניווט (4 טאבים) | ✅ |
| אימון אקורד + סינון רמה | ✅ |
| זיהוי חופשי | ✅ |
| ספרייה לפי 5 רמות (ללא overflow) | ✅ |
| דיאגרמה: אצבעות + סריג בצד + חלון | ✅ |
| טיונר ללא גלילה (flex) | ✅ |
| isActive / עצירת mic / MicCaptureGuard | ✅ |
| **קטלוג** | ✅ **30 אקורדים**, difficulty + category + finger |
| מעברי אקורדים | ⏸️ **מוקפא** (לא ב־UI) |
| בדיקות אוטומטיות / store release | 🔜 v1.1+ |

---

## 13. קבצים חשובים

1. `assets/chords.json` + `lib/models/chord_definition.dart`
2. `lib/ui/widgets/chord_fretboard_chart.dart`
3. `lib/ui/chord_library_screen.dart` + `lib/ui/practice_screen.dart`
4. `lib/chord/chord_matcher.dart` + `lib/audio/fft_processor.dart`
5. `lib/audio/pitch_tuner.dart` + `lib/ui/tuner_screen.dart`
6. `lib/ui/home_screen.dart` (ללא כניסה למעברים)

---

## הוראות עדכון (לסוכן)

- **`HANDOFF_2.md` — אסור לערוך.** ארכיון Release **v1.0.1 (+1)** בלבד.
- **`HANDOFF.md` — מסמך העבודה היחיד** לתיעוד באגים, פיצ'רים ובנייות דיבאג.

אחרי `flutter build apk` (debug או release):

1. הוסף שורה לטבלת **Build history** ב-`HANDOFF.md`.
2. עדכן סעיפים רלוונטיים ב-`HANDOFF.md` (ניווט, קטלוג, סטטוס, פערים).
3. **Release:** העתק ל-`releases/` רק אחרי `flutter build apk --release` מכוון במפורש — לא בדיבאג.
