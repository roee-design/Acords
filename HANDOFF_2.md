# מסמך מסירה — Chord Trainer v1.0.0 (Release Snapshot)

מסמך ארכיון לגרסת **Release v1.0.0** הנוכחית (`1.0.0+8`).  
לתיעוד שוטף של פיתוח — ראו `HANDOFF.md`.

**נתיב הפרויקט:** `c:\Users\noam1\OneDrive\שולחן העבודה\רועי\Acords`

---

## Build history (v1.0.0)

| תאריך | buildCode | נתיב | מה נכנס לבנייה |
|--------|-----------|------|----------------|
| 2026-07-17 | **+8** | `releases/acords_v1.0.0.apk` (~47MB) | **Release נוכחי (Android):** תיקון deadlock ב-stop; מעבר טאב = לחיצת עצור; `MicCaptureGuard` ברמת מסך; הסרת `PopScope` שקפא; מיקרופון יחיד |
| 2026-07-17 | **+8** | `releases/windows.zip` (~12MB) | **Release נוכחי (Windows):** חבילת אפליקציית שולחן עבודה — אותו קוד v1.0.0+8 |
| 2026-07-17 | +5 | `releases/acords_v1.0.0.apk` | rebuild מלא; הורדת BPM רק כש„האצה הדרגתית” פעילה |
| 2026-07-17 | +4 | `releases/acords_v1.0.0.apk` | הורדת BPM רק עם האצה הדרגתית |
| 2026-07-16 | +3 | `releases/acords_v1.0.0.apk` | מטרונום `mediaPlayer`+seek (לא `lowLatency`); mic session/dispose; זיהוי מעברים (FFT clear + audioFocus none); `metronome_click.wav` |
| 2026-07-16 | +1 | `releases/acords_v1.0.0.apk` | Release ראשון: overflow דיאגרמות; isActive mic; מטרונום קולי; טיונר (אוטו=פתוחים); try-catch mic |

**ארטיפקטים רשמיים נוכחיים:**
- Android: `releases/acords_v1.0.0.apk` (~47.3MB)
- Windows: `releases/windows.zip` (~12.5MB)

---

## גרסה רשמית

| שדה | ערך |
|-----|-----|
| `pubspec.yaml` (בזמן הנעילה) | `version: 1.0.0+8` |
| Android APK | `releases/acords_v1.0.0.apk` |
| Windows ZIP | `releases/windows.zip` |
| Android id | `com.chordtrainer.chord_trainer` |
| UI | עברית, RTL (`he_IL`) |

> **הערה:** מספר הגרסה נשאר `1.0.0`; buildCode (`+8`) משתנה בין בנייות Android.

---

## מה כלול ב-v1.0.0

### מסכים וניווט

- **4 טאבים:** בית, זיהוי חופשי, ספריית אקורדים, טיונר
- **Push:** אימון אקורד בודד, מעברי אקורדים (BPM + מטרונום + סאונד)
- **8 אקורדים** ב-`assets/chords.json` (C, D, E, G, A, Am, Dm, Em)

### אודיו וזיהוי

- **FFT + משוב חי** בעברית
- **AudioAnalyzer / PitchTuner** — try-catch סביב `startStream`; session token + תור פעולות
- **`MicCaptureGuard`** — רק מיקרופון אחד פעיל; מעבר טאב / התחלת הקלטה חדשה = עצירה מלאה (כמו כפתור „עצור”)
- **isActive** — יציאה מטאב → `_stopListening()` / `_stop()` / `_stopTraining()`; **ללא resume אוטומטי**; `deactivate` + `dispose` מלאים

### מעברי אקורדים

- BPM 40–120, מטרונום ויזואלי + **סאונד** (טוגל)
- עזרת חוק 1-2-3-4
- **האצה הדרגתית:** עליית BPM אחרי 2 מעברים מושלמים; **ירידת BPM רק כשהאפשרות פעילה**
- מטרונום: pool של 3 `AudioPlayer` ב-`mediaPlayer` mode; `assets/metronome_click.wav`; audio focus none (לא חוסם mic)
- זיהוי: ניקוי FFT buffer במעבר יעד
- יציאה מהמסך: `deactivate` → `_stopTraining()` (מטרונום + click players + mic)

### טיונר

- **אוטו** = 6 מיתרים פתוחים בלבד (±2 חצאי־טון)
- **בחירת מיתר** — נעילה ליעד פתוח
- isActive → עצירה מלאה במעבר טאב (ללא resume)

### UI

- דיאגרמות אקורדים ללא Bottom Overflow (`LayoutBuilder` + `FittedBox`)

---

## Tech stack

- Dart `^3.12.0`, Flutter 3.12+
- `record` — PCM16 מהמיקרופון
- `fftea` — FFT
- `permission_handler` — הרשאת מיקרופון
- `audioplayers` — קליק מטרונום (`assets/metronome_click.wav`)

---

## פערים ידועים (v1.0.0)

1. README מיושן
2. `test/widget_test.dart` לא תואם UI עברי
3. רק 8 אקורדים
4. אין persistence (BPM / אקורד אחרון)
5. Pitch = peak-FFT, לא YIN
6. ספי זיהוי אמפיריים — תלוי מכשיר
7. מטרונום עלול להיקלט ב-mic — כבוי בטוגל / אוזניות
8. חוסר עקביות 5¢ vs 25¢ במחוג טיונר
9. חתימת Android: debug keys (template) — לפני Google Play יש keystore ייעודי

---

## בניית Release והעתקה לארכיון

```powershell
$env:JAVA_HOME = "D:\Program Files\Android\Android Studio\jbr"
$env:Path = "$env:JAVA_HOME\bin;" + $env:Path

# אם הבנייה נכשלת בנתיב OneDrive/עברית — לבנות מ-C:\AcordsBuild (עותק של הפרויקט)
$src = "c:\Users\noam1\OneDrive\שולחן העבודה\רועי\Acords"
$dst = "C:\AcordsBuild"
robocopy $src $dst /MIR /XD .dart_tool build .git chord_trainer android\.gradle android\.kotlin android\build android\app\build /XF "*.apk"

cd C:\AcordsBuild
flutter pub get
flutter build apk --release

Copy-Item "build\app\outputs\flutter-apk\app-release.apk" "$src\releases\acords_v1.0.0.apk" -Force
```

לאימות:

```powershell
Get-Item "releases\acords_v1.0.0.apk" | Select-Object FullName, Length, LastWriteTime
```

---

## קבצים מרכזיים

1. `lib/chord/chord_matcher.dart` + `lib/audio/fft_processor.dart`
2. `lib/audio/audio_analyzer.dart` + `lib/audio/pitch_tuner.dart` + `lib/audio/mic_capture_guard.dart`
3. `lib/ui/chord_transitions_screen.dart` — מעברים + מטרונום
4. `lib/ui/free_play_screen.dart` + `lib/ui/tuner_screen.dart`
5. `assets/chords.json` + `assets/metronome_click.wav`
