# Chord Trainer

Real-time classical guitar chord practice. The app listens through the microphone, runs an FFT on each audio frame, and compares detected fundamentals (plus harmonics) against the selected chord from `assets/chords.json`.

## Requirements

- Flutter SDK 3.12+
- Physical device recommended (microphone access)

## Run

```powershell
$env:Path += ";D:\flutter\bin"
cd "c:\Users\noam1\OneDrive\שולחן העבודה\רועי\Acords"
flutter pub get
flutter run
```

## Project layout

```
lib/
  main.dart                      # App bootstrap, loads assets
  models/
    chord_definition.dart        # Chord catalog models
    feedback_result.dart         # Per-string feedback states
  audio/
    audio_analyzer.dart          # Mic stream + FFT pipeline
    fft_processor.dart           # Hann window, FFT, harmonic scoring
    frequency_utils.dart         # MIDI→Hz, bin helpers
    ring_buffer.dart             # Low-latency circular buffer
  chord/
    chord_matcher.dart             # Thresholds + feedback messages
  services/
    chord_catalog_service.dart   # Loads chords.json
  ui/
    practice_screen.dart         # Chord dropdown, listen UI, string list
assets/
  chords.json                    # C, G, Dm, Am, Em voicings
```

## Permissions

- **Android**: `RECORD_AUDIO` in `android/app/src/main/AndroidManifest.xml`
- **iOS**: `NSMicrophoneUsageDescription` in `ios/Runner/Info.plist`
