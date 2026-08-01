# מסמך מסירה — Chord Trainer (Acords)

מסמך עבודה שוטף למפתח / AI. **כל שינוי, באג או פיצ'ר מעתה מתועדים כאן בלבד.**

**נתיב הפרויקט:** `c:\Users\noam1\OneDrive\שולחן העבודה\רועי\Acords`

> **Release נעול:** `HANDOFF_2.md` + `releases/acords_v1.0.0.apk` + `releases/windows.zip` = snapshot רשמי של v1.0.0 (+8). **אין לערוך את `HANDOFF_2.md`.**

---

## מצב נוכחי — סבב פיתוח

| שדה | ערך |
|-----|-----|
| גרסת פיתוח (`pubspec.yaml`) | `1.0.1+1` |
| Release יציב (נעול) | `1.0.0+8` → `releases/acords_v1.0.0.apk` + `releases/windows.zip` |
| APK דיבאג | `build/app/outputs/flutter-apk/app-debug.apk` (לא נוגע ב-`releases/`) |

### תיקון `1.0.1+1` — באג "ההצלחה המיידית" במעברי אקורדים

תוקן גם כשהמטרונום כבוי (שאריות אודיו/FFT מהאקורד הקודם, לא רק קליק):

1. **איפוס Buffer מלא במעבר אקורד** — `AudioAnalyzer.resetAnalysisState()` מנקה `RingBuffer` + `FftProcessor.reset()`; במעבר יעד ב-`ChordTransitionsScreen` קוראים ל-`setTargetChord(..., gracePeriod: 350ms)`.
2. **Grace Period / Debounce** — 350ms אחרי החלפת אקורד היעד ה-Matcher מתעלם מזיהוי; האודיו נזרק עד תום החלון, ואז מתחילה האזנה מחדש.
3. **סף אנרגיה מינימלי** — `ChordMatcher.minimumDetectionInputLevel` (RMS ≥ 0.012) מסרב לזהות על שקט / רעש רקע עדין.
4. **מיתרים נמוכים 4/5/6** — בתדרים `<160Hz` חיפוש/שקלול H1+H2+H3 ב-`TargetFrequencyProfile` וב-`PitchTuner` (כולל שחזור fundamental מהרמוניות למיקרופון חלש).

---

## Build history

| תאריך | סוג | נתיב APK | מה נכנס לבנייה |
|--------|-----|----------|----------------|
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
| גרסה | `1.0.1+1` (פיתוח) |
| UI | עברית, RTL (`he_IL`) |
| מצב | **פיתוח** — Release נעול: `releases/acords_v1.0.0.apk` + `releases/windows.zip` (v1.0.0+8) |

**אין** Riverpod / Bloc / Provider — רק `StatefulWidget` + streams.

---

## 2. Tech stack

- Dart `^3.12.0`, Flutter 3.12+
- `record` — PCM16 מהמיקרופון
- `fftea` — FFT
- `permission_handler` — הרשאת מיקרופון
- `audioplayers` — קליק מטרונום (`assets/metronome_click.wav`)

---

## 3. מבנה `lib/` (25 קבצים)

```
lib/
  main.dart
  models/          chord_definition.dart, feedback_result.dart
  services/        chord_catalog_service.dart
  audio/           audio_analyzer, pitch_tuner, fft_processor, ring_buffer, frequency_utils
  chord/           chord_matcher.dart
  ui/              מסכים + widgets (fretboard, tuner gauge, help, confetti…)
```

---

## 4. ניווט

| # | מסך | mic | isActive |
|---|-----|-----|----------|
| 0 | Home | לא | — |
| 1 | FreePlay | כן | `_selectedIndex == 1` |
| 2 | Library | לא | — |
| 3 | Tuner | כן | `_selectedIndex == 3` |

**Push:** `PracticeScreen`, `ChordTransitionsScreen` (גם `isActive`, ברירת מחדל `true`).

---

## 5. נתונים — `assets/chords.json`

**16 אקורדים** (EADGBE): C, D, E, G, A, Am, Dm, Em, **F, B, Bm, C7, G7, D7, E7, A7**.

---

## 6. Audio pipeline

```
Mic (PCM16, 44100) → RingBuffer(8192) → Hann+FFT → Matcher / PitchTuner → Stream → UI
```

- `AudioAnalyzer` — אקורדים (~80ms)
- `PitchTuner` — טיונר (~60ms, 70–700 Hz)
- **try-catch** סביב `startStream` בשני המנועים — לא קורס על כשל mic/הרשאות
- הערות קוד בנקודות מפתח: FFT, peak-pick, open-string matching

---

## 7. פיצ'רים לפי מסך

- **Practice** — אימון אקורד + משוב חי + confetti
- **Free play** — זיהוי אקורד מהקטלוג
- **Library** — grid דיאגרמות (ללא overflow), sheet מפורט
- **Transitions** — מעברים, BPM, מטרונום ויזואלי + **סאונד** (טוגל), עזרת חוק 1-2-3-4
- **Tuner** — ראו סעיף 8

---

## 8. טיונר

1. **בחירת מיתר** — `אוטו` + מיתרים 6→1
2. **אוטו = מיתרים פתוחים בלבד** — ±2 חצאי־טון מ־`openMidi`; אחרת `awaitingOpenString` / "נא לנגן מיתר פתוח"
3. **מיתר נעול** — חיפוש H1/H2/H3, cents מול יעד פתוח
4. **isActive** — יציאה מטאב → עצירה מלאה (כמו כפתור „עצור”); **ללא resume**; `MicCaptureGuard` — מיקרופון יחיד; `dispose` מלא

In-tune: ±5 סנט (לוגיקה). מחוג: צביעה ירוקה ~±25.

---

## 9. UI — דיאגרמות אקורדים (v1.0.0)

`ChordFretboardFrame` — **ללא גובה קבוע חובה**:
- `LayoutBuilder` + `FittedBox` — הדיאגרמה מתכווצת לגודל הזמין
- `AspectRatio` (1.35) כשאין גובה מפורש
- בכרטיסיות grid: `Expanded` סביב הדיאגרמה
- תיקון Bottom Overflow בכרטיסיות ספריית האקורדים

---

## 10. Build / הרשאות

- Android: `RECORD_AUDIO`
- iOS: `NSMicrophoneUsageDescription`
- Release signing: עדיין מפתחות debug (template) — לפני store release
- **Release נעול:** `releases/acords_v1.0.0.apk` + `releases/windows.zip` (v1.0.0+8) — אל תדרוס בבניית דיבאג
- **דיבאג:** `build/app/outputs/flutter-apk/app-debug.apk`
- אם `flutter build` נכשל בנתיב OneDrive/עברית — לבנות מעותק ב-`C:\AcordsBuild`
- **Windows release:** `releases/windows.zip` — חבילת שולחן עבודה ל-v1.0.0+8 (נוסף 2026-07-17)

---

## 11. פערים ידועים (post-v1)

1. README מיושן
2. `test/widget_test.dart` לא תואם UI עברי
3. ~~רק 8 אקורדים~~ → הורחב ל-16 ב-`1.0.1+1`
4. אין persistence (BPM / אקורד אחרון)
5. Pitch = peak-FFT, לא YIN
6. ספי זיהוי אמפיריים — תלוי מכשיר
7. מטרונום עלול להיקלט ב-mic — כבוי בטוגל / אוזניות
8. חוסר עקביות 5¢ vs 25¢ במחוג טיונר

**תוקן ב-v1.0.0 (+8):**
- ~~overflow דיאגרמות~~
- ~~mic זולג ב-IndexedStack~~ (`isActive` + `MicCaptureGuard` + עצירה מלאה במעבר טאב)
- ~~deadlock / קיפאון במעברי אקורדים~~ (תיקון `release`; הסרת `PopScope`)
- ~~מטרונום בלי סאונד / לא בכל טיק~~ (`mediaPlayer` + seek, לא `lowLatency`; WAV; pool)
- ~~זיהוי נכשל במעברי אקורדים~~ (audio focus none + ניקוי FFT)

**תוקן ב-`1.0.1+1`:**
- ~~"הצלחה מיידית" במעברי אקורדים~~ (גם עם מטרונום כבוי: reset RingBuffer/FFT + grace 350ms + סף RMS + H1/H2/H3 למיתרים נמוכים)

---

## 12. סטטוס מוצר — v1.0.1 (פיתוח)

| אזור | מצב |
|------|-----|
| שלד + ניווט | ✅ |
| אימון אקורד | ✅ |
| זיהוי חופשי | ✅ |
| ספריית אקורדים (ללא overflow) | ✅ |
| מעברים + BPM + סאונד + עזרה 1-2-3-4 | ✅ |
| תיקון "הצלחה מיידית" במעברים (reset+grace+RMS) | ✅ `1.0.1+1` |
| טיונר חכם (אוטו=פתוחים, בחירת מיתר) | ✅ |
| isActive / עצירת mic / session dispose | ✅ |
| מטרונום אמין (mediaPlayer pool + WAV + mix focus) | ✅ |
| ניקוי production (try-catch, הערות) | ✅ |
| **קטלוג אקורדים** | ✅ **הורחב ל-16 אקורדים** (F, B, Bm, C7, G7, D7, E7, A7) |
| בדיקות אוטומטיות / store release | 🔜 v1.1+ |

---

## 13. קבצים חשובים

1. `lib/chord/chord_matcher.dart` + `lib/audio/fft_processor.dart`
2. `lib/audio/pitch_tuner.dart` + `lib/ui/tuner_screen.dart`
3. `lib/ui/widgets/chord_fretboard_chart.dart`
4. `assets/chords.json`

---

## הוראות עדכון (לסוכן)

- **`HANDOFF_2.md` — אסור לערוך.** ארכיון v1.0.0 (+8) בלבד.
- **`HANDOFF.md` — מסמך העבודה היחיד** לתיעוד באגים, פיצ'רים ובנייות דיבאג.

אחרי `flutter build apk` (debug או release):

1. הוסף שורה לטבלת **Build history** ב-`HANDOFF.md` בלבד.
2. עדכן סעיפים רלוונטיים ב-`HANDOFF.md`.
3. **Release:** העתק ל-`releases/` רק אחרי `flutter build apk --release` מכוון במפורש — לא בדיבאג.
