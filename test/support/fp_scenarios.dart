import 'dart:math';
import 'dart:typed_data';

import 'package:chord_trainer/game/rhythm_chart.dart';
import 'package:chord_trainer/models/chord_definition.dart';
import 'package:chord_trainer/models/strumming_pattern.dart';

import 'guitar_synth.dart';
import 'stroke_scenarios.dart' show openMidi;

/// Chart time 0 is at this point of every scenario's audio (1 s lead-in).
const double fpChartStartSec = 1.0;

/// One reproducible false-positive (or control) case.
class FpCase {
  const FpCase(this.id, this.description, this.build, {this.isControl = false});

  final String id;
  final String description;

  /// Renders the audio for [chart] (chart time 0 at [fpChartStartSec]).
  final Float32List Function(RhythmChart chart, ChordCatalog catalog, int seed) build;

  /// Control = the player plays correctly (accuracy should be high).
  final bool isControl;
}

double _audioSec(RhythmChart chart, double chartMs) =>
    fpChartStartSec + chartMs / 1000;

double _durationSec(RhythmChart chart) =>
    fpChartStartSec + chart.durationMs / 1000 + 1.5;

/// Room tone: broadband noise plus mains hum (fans, fridges, PC).
void _addHum(Float32List out, double level) {
  for (var i = 0; i < out.length; i++) {
    final t = i / 44100;
    out[i] += level * (sin(2 * pi * 50 * t) + 0.5 * sin(2 * pi * 100 * t) +
        0.25 * sin(2 * pi * 150 * t));
  }
}

/// Knocks / phone handling: short broadband bursts with a low thump.
void _addKnocks(Float32List out, Random rng, {double everySec = 0.7}) {
  var t = 0.4 + rng.nextDouble() * 0.3;
  while (t < out.length / 44100 - 0.2) {
    final start = (t * 44100).round();
    final amp = 0.03 + 0.05 * rng.nextDouble();
    for (var i = 0; i < 2200 && start + i < out.length; i++) {
      final env = exp(-i / 180);
      out[start + i] += amp * env * ((rng.nextDouble() * 2 - 1) + 0.8 * sin(2 * pi * 90 * i / 44100));
    }
    t += everySec * (0.6 + 0.8 * rng.nextDouble());
  }
}

/// Someone talking / humming nearby: voiced syllables, gliding pitch.
void _addVoice(Float32List out, Random rng, {double level = 0.04}) {
  var t = 0.3;
  var phase = 0.0;
  while (t < out.length / 44100 - 0.3) {
    final syllable = 0.12 + 0.2 * rng.nextDouble();
    final f0 = 110 + 110 * rng.nextDouble();
    final glide = 0.85 + 0.3 * rng.nextDouble();
    final start = (t * 44100).round();
    final n = (syllable * 44100).round();
    for (var i = 0; i < n && start + i < out.length; i++) {
      final x = i / n;
      final env = sin(pi * x);
      final f = f0 * (1 + (glide - 1) * x) * (1 + 0.02 * sin(2 * pi * 5.5 * i / 44100));
      phase += 2 * pi * f / 44100;
      var v = 0.0;
      for (var k = 1; k <= 10; k++) {
        v += sin(k * phase) / k;
      }
      out[start + i] += level * env * v;
    }
    t += syllable + 0.04 + 0.15 * rng.nextDouble();
  }
}

/// Strings sounded by a stroke of [chord] for [note] when played correctly.
List<StringEvent> _correctStroke(
  GuitarSynth synth,
  ChordDefinition chord,
  RhythmNote note,
  double at,
  double stopAt, {
  bool soft = false,
}) {
  switch (note.kind) {
    case PatternEventKind.down:
    case PatternEventKind.up:
      final down = note.kind == PatternEventKind.down;
      return synth.strum(
        chord,
        startSec: at,
        stopSec: stopAt,
        down: down,
        soft: soft,
        level: down ? 0.22 : 0.13,
        onlyStrings: down ? null : {1, 2, 3, 4},
      );
    case PatternEventKind.finger:
      final s = note.stringNumber ?? 6;
      var n = chord.isStringMuted(s) ? null : chord.noteForString(s);
      n ??= chord.notes.first;
      return [
        StringEvent(midi: n.midi, startSec: at, amplitude: 0.2, stringNumber: n.string),
      ];
    case PatternEventKind.mute:
      return _mutedStrum(at);
    case PatternEventKind.pause:
      return const [];
  }
}

/// Fretting hand resting on all strings: a pitch-less "chk".
List<StringEvent> _mutedStrum(double at) => [
      for (var s = 6; s >= 1; s--)
        StringEvent(
          midi: openMidi[s]!,
          startSec: at + (6 - s) * 0.008,
          amplitude: 0.18,
          stopSec: at + (6 - s) * 0.008 + 0.02,
          stringNumber: s,
        ),
    ];

Float32List _render(
  RhythmChart chart,
  int seed,
  List<StringEvent> Function(GuitarSynth synth, RhythmNote note, double at, double stopAt) stroke, {
  MicConditions mic = const MicConditions(highPassHz: 140, noiseLevel: 0.002),
}) {
  final synth = GuitarSynth(seed: seed);
  final events = <StringEvent>[];
  for (final note in chart.notes) {
    final at = _audioSec(chart, note.timeMs);
    final stopAt = at + chart.slotMs * 2.2 / 1000;
    events.addAll(stroke(synth, note, at, stopAt));
  }
  return synth.render(events, durationSec: _durationSec(chart), mic: mic);
}

/// The reproducible cases. Every non-control case is a false positive: any
/// accuracy the game gives there is wrong.
final List<FpCase> fpCases = [
  FpCase('idle-quiet', 'לא עושים כלום, חדר שקט', (chart, catalog, seed) {
    final synth = GuitarSynth(seed: seed);
    return synth.render([], durationSec: _durationSec(chart),
        mic: const MicConditions(highPassHz: 140, noiseLevel: 0.002));
  }),
  FpCase('idle-noisy-room', 'לא עושים כלום, רעש רקע + זמזום חשמלי', (chart, catalog, seed) {
    final synth = GuitarSynth(seed: seed);
    final out = synth.render([], durationSec: _durationSec(chart),
        mic: const MicConditions(highPassHz: 140, noiseLevel: 0.008));
    _addHum(out, 0.01);
    return out;
  }),
  FpCase('idle-knocks', 'לא עושים כלום, דפיקות/נגיעות בטלפון', (chart, catalog, seed) {
    final synth = GuitarSynth(seed: seed);
    final out = synth.render([], durationSec: _durationSec(chart),
        mic: const MicConditions(highPassHz: 140, noiseLevel: 0.003));
    _addKnocks(out, Random(seed));
    return out;
  }),
  FpCase('idle-voice', 'לא עושים כלום, מישהו מדבר/מזמזם ליד', (chart, catalog, seed) {
    final synth = GuitarSynth(seed: seed);
    final out = synth.render([], durationSec: _durationSec(chart),
        mic: const MicConditions(highPassHz: 140, noiseLevel: 0.002));
    _addVoice(out, Random(seed));
    return out;
  }),
  FpCase('idle-ringing', 'פריטה נכונה אחת ואז האקורד מצלצל בלי לנגן', (chart, catalog, seed) {
    final synth = GuitarSynth(seed: seed);
    final chord = catalog.chordById(chart.bars.first.chordId)!;
    return synth.render(synth.strum(chord, startSec: fpChartStartSec),
        durationSec: _durationSec(chart),
        mic: const MicConditions(highPassHz: 140, noiseLevel: 0.002));
  }),
  FpCase('random-strum-open', 'פריטה בזמן על מיתרים 5–2 פתוחים, בלי אקורד', (chart, catalog, seed) {
    return _render(chart, seed, (synth, note, at, stopAt) {
      final down = note.kind != PatternEventKind.up;
      final order = down ? [5, 4, 3, 2] : [2, 3, 4, 5];
      return [
        for (var k = 0; k < order.length; k++)
          StringEvent(
            midi: openMidi[order[k]]!,
            startSec: at + k * 0.012,
            amplitude: (down ? 0.2 : 0.13) * (0.7 + 0.3 * synth.rand()),
            stopSec: stopAt,
            stringNumber: order[k],
          ),
      ];
    });
  }),
  FpCase('random-pluck-middle', 'פריטה בזמן על מיתר אקראי מ-5–2, בלי אקורד (המקרה של 72%)', (chart, catalog, seed) {
    final rng = Random(seed);
    return _render(chart, seed, (synth, note, at, stopAt) {
      final s = 2 + rng.nextInt(4);
      return [StringEvent(midi: openMidi[s]!, startSec: at, amplitude: 0.2, stringNumber: s)];
    });
  }),
  FpCase('random-brush-middle', 'נגיעה בזמן ב-2–3 מיתרים אמצעיים אקראיים, בלי אקורד', (chart, catalog, seed) {
    final rng = Random(seed);
    return _render(chart, seed, (synth, note, at, stopAt) {
      final first = 2 + rng.nextInt(3);
      final count = 2 + rng.nextInt(2);
      return [
        for (var k = 0; k < count && first + k <= 5; k++)
          StringEvent(
            midi: openMidi[first + k]!,
            startSec: at + k * 0.015,
            amplitude: 0.16,
            stopSec: stopAt,
            stringNumber: first + k,
          ),
      ];
    });
  }),
  FpCase('muted-strums', 'פריטות מושתקות ("צ׳ק") בזמן, בלי צליל', (chart, catalog, seed) {
    return _render(chart, seed, (synth, note, at, stopAt) => _mutedStrum(at));
  }),
  FpCase('wrong-chord', 'פריטה בזמן של אקורד אחר (קרוב) במקום הנכון', (chart, catalog, seed) {
    const swap = {
      'c_major': 'a_minor', 'a_minor': 'c_major', 'g_major': 'e_minor',
      'e_minor': 'g_major', 'd_major': 'b_minor', 'f_major': 'd_minor',
      'd_minor': 'f_major', 'b_minor': 'd_major',
    };
    return _render(chart, seed, (synth, note, at, stopAt) {
      final expected = chart.bars[note.barIndex].chordId;
      final wrong = catalog.chordById(swap[expected] ?? 'e_major')!;
      return _correctStroke(synth, wrong, note, at, stopAt);
    });
  }),
  FpCase('control-correct', 'ביקורת: נגינה נכונה של הדפוס', (chart, catalog, seed) {
    return _render(chart, seed, (synth, note, at, stopAt) =>
        _correctStroke(synth, catalog.chordById(chart.bars[note.barIndex].chordId)!, note, at, stopAt));
  }, isControl: true),
  FpCase('control-correct-soft', 'ביקורת: נגינה נכונה ורכה (באצבעות)', (chart, catalog, seed) {
    return _render(chart, seed, (synth, note, at, stopAt) => _correctStroke(
        synth, catalog.chordById(chart.bars[note.barIndex].chordId)!, note, at, stopAt,
        soft: true));
  }, isControl: true),
];
