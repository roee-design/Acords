# מסמך מסירה — Chord Trainer v1.0.1 (Release Snapshot)

מסמך ארכיון לגרסת **Release v1.0.1** (`1.0.1+1`).  
לתיעוד שוטף של פיתוח אחרי הנעילה — ראו `HANDOFF.md`.

**נתיב הפרויקט:** `c:\Users\Fisher-home\Desktop\chords`

> **נעול.** אין לערוך מסמך זה אחרי נעילת הריליס — שינויי פיתוח רק ב־`HANDOFF.md`.

---

## Build history (v1.0.1)

| תאריך | buildCode | נתיב | מה נכנס לבנייה |
|--------|-----------|------|----------------|
| 2026-09-23 | **+1** | `releases/acords_v1.0.1.apk` (~48.9MB) | **Release נוכחי (Android):** נעילת 1.0.1 — אתגר אקורדים מלא, קטלוג 30 אקורדים / 5 רמות, מנוע זיהוי עם אינטרפולציה פרבולית + onset באתגר, SFX, שיא עם Grade, wakelock |

**ארטיפקט רשמי נוכחי:**
- Android: `releases/acords_v1.0.1.apk` (~48.9MB)

**היסטוריה קודמת (לא נדרסת):** Release v1.0.0 (+8) תועד בעבר; ארטיפקט Windows (`releases/windows.zip`) שייך ל־v1.0.0 ולא עודכן בנעילה זו.

---

## גרסה רשמית

| שדה | ערך |
|-----|-----|
| `pubspec.yaml` (בזמן הנעילה) | `version: 1.0.1+1` |
| Android APK | `releases/acords_v1.0.1.apk` |
| Android id | `com.chordtrainer.chord_trainer` |
| UI | עברית, RTL (`he_IL`) |
| סביבת בנייה | Flutter 3.47.5 + JDK 17 + Android SDK |

---

## מה כלול ב-v1.0.1

### מסכים וניווט

- **4 טאבים:** בית, זיהוי חופשי, ספריית אקורדים, טיונר
- **Push ממסך הבית:** אימון אקורד בודד, **אתגר האקורדים**
- **מעברי אקורדים מוקפאים** — הוסרו מהניווט; `chord_transitions_screen.dart` נשאר בקוד אך לא נטען
- **30 אקורדים** ב־`assets/chords.json` עם `difficulty` (1–5) + `category`

### אתגר האקורדים (Chord Blitz)

- טיימר 30 שניות; ניקוד +100 לאקורד; בונוס זמן **רק ברצף 5** (+5 שניות) — ללא +3 לכל אקורד
- בחירת מאגר: רמה 1–5 / כל הרמות / קבוצה מותאמת
- שיא אישי ב־SharedPreferences לפי מאגר (`blitz_highscore_level_N` / `all` / `custom`) עם **Grade** (S/A/B/C)
- SFX: ספירה לאחור, הצלחה/קומבו, בונוס רצף, דחיפות בסוף, שיא חדש, סיום
- `wakelock_plus` בזמן משחק
- סיום: «התחל מחדש» → countdown; «תפריט האתגר» → setup
- זיהוי פגיעה: **2 פריימי perfect רצופים** + **onset (פריטה חדשה)** תוך 1s מהצבת האקורד; grace 350ms

### אודיו וזיהוי

- **FFT + משוב חי** בעברית (`ChordMatcher` / `AudioAnalyzer`)
- **אינטרפולציה פרבולית** ב־`estimatePitchCentsOffset` (sub-bin) — מתקן קוונטיזציית bin שחסמה E2/A2 וכו׳ מול ±25¢
- **Onset tracker** ב־`AudioAnalyzer` (RMS×1.8 מעל מינימום 80–400ms) — `hasOnsetWithin` / `lastOnsetAt`
- **`MicCaptureGuard`** — מיקרופון יחיד; מעבר טאב = עצירה מלאה
- **isActive** — יציאה מטאב → עצירה; ללא resume אוטומטי

### ספרייה + אימון + טיונר

- סינון לפי 5 רמות קושי
- דיאגרמת אקורדים: אצבעות 1–4, מספרי סריג, חלון סריגים גבוה, תוויות מיתר
- השמעת אקורד (סינתזת PCM + `audioplayers`) באימון ובספרייה
- טיונר ללא גלילה: `Column` + `Expanded`

### תלויות עיקריות (מעבר ל־v1.0.0)

- `shared_preferences` — שיאי אתגר
- `wakelock_plus` — מניעת כיבוי מסך במשחק
- `path_provider` — שירותי אודיו

---

## Tech stack

- Dart `^3.12.0`, Flutter 3.47.x
- `record` — PCM16 מהמיקרופון
- `fftea` — FFT
- `permission_handler` — הרשאת מיקרופון
- `audioplayers` — SFX / השמעת אקורד / מטרונום (בקוד מעברים)
- `shared_preferences`, `wakelock_plus`, `path_provider`

---

## פערים ידועים (v1.0.1)

1. README מיושן
2. `test/widget_test.dart` לא תואם UI עברי
3. Pitch = peak-FFT (+אינטרפולציה), לא YIN
4. ספי זיהוי אמפיריים — תלוי מכשיר / מיקרופון
5. חתימת Android: debug keys (template) — לפני Google Play יש keystore ייעודי
- אין עדיין מנגנון שירים ופריטות (מתוכנן לסבב הבא)

---

## בניית Release והעתקה לארכיון

```powershell
$env:JAVA_HOME = 'C:\Program Files\Microsoft\jdk-17.0.20.101-hotspot'
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
$env:Path = "$env:JAVA_HOME\bin;$env:USERPROFILE\flutter\bin;$env:ANDROID_HOME\platform-tools;$env:Path"

cd "c:\Users\Fisher-home\Desktop\chords"
flutter build apk --release

Copy-Item "build\app\outputs\flutter-apk\app-release.apk" "releases\acords_v1.0.1.apk" -Force
```

לאימות:

```powershell
Get-Item "releases\acords_v1.0.1.apk" | Select-Object FullName, Length, LastWriteTime
```

---

## קבצים מרכזיים

1. `lib/chord/chord_matcher.dart` + `lib/audio/fft_processor.dart`
2. `lib/audio/audio_analyzer.dart` (onset) + `lib/audio/pitch_tuner.dart` + `lib/audio/mic_capture_guard.dart`
3. `lib/ui/chord_blitz_screen.dart` + `lib/audio/blitz_sfx_service.dart` + `lib/services/blitz_prefs.dart`
4. `lib/ui/practice_screen.dart` + `lib/ui/chord_library_screen.dart` + `lib/ui/tuner_screen.dart`
5. `assets/chords.json` (30 אקורדים)
