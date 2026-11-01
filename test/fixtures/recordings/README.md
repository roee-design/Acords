# Real recordings for the false-positive bench

`test/bench/false_positive_bench_test.dart` replays every `NAME.json` +
`NAME.wav` pair in this folder through the exact guitar-mode pipeline of the
app and prints the accuracy it gets next to the accuracy the app showed.

## Recording a round (debug APK)

1. Open a strumming lesson → a game level → **«עם גיטרה»**.
2. Turn on **«מצב אבחון (לוגים + הקלטה)»** (only in debug builds).
3. Play the round the way you want to test, for example:
   - do nothing for the whole round (`idle`),
   - pluck random open middle strings without holding a chord (`random`),
   - play correctly (`correct`).
4. At the end the results screen shows where the files were saved.

## Getting the files

```
adb pull /sdcard/Android/data/com.chordtrainer.chord_trainer/files/diagnostics
```

Copy the `.json` + `.wav` pair(s) here. Optionally add a `"label"` field to
the JSON (e.g. `"label": "idle"`) so the bench output says what was played.

The matching `.log` file holds the same `LEVEL` / `PEAK` / `STROKE` lines
that were printed to logcat during the round:

```
adb logcat -s flutter | findstr "Acords Diag"
```

## Running

```
flutter test test/bench/false_positive_bench_test.dart --run-skipped
```

Results: `build/false_positive_bench/report.txt` and one log per case /
recording.
