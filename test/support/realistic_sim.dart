import 'dart:math';
import 'dart:typed_data';

import 'package:chord_trainer/game/rhythm_chart.dart';
import 'package:chord_trainer/models/chord_definition.dart';
import 'package:chord_trainer/models/strumming_pattern.dart';

import 'guitar_synth.dart';

/// Open-string MIDI notes (6 = low E).
const simOpenMidi = {6: 40, 5: 45, 4: 50, 3: 55, 2: 59, 1: 64};

/// A human playing a real guitar: imperfect timing, partial strums, a guitar
/// that is not perfectly in tune.
class PlayerModel {
  const PlayerModel({
    this.timingBiasMs = 0,
    this.timingJitterMs = 0,
    this.strumSpanMs = 45,
    this.skipBassProb = 0,
    this.skipTopProb = 0,
    this.upStrings = 4,
    this.extraStringProb = 0,
    this.tuningOffsetCents = 0,
    this.stringDetuneSd = 0,
    this.soft = false,
    this.level = 0.22,
    this.seed = 0,
  });

  /// Habitual early (−) / late (+) playing, and stroke-to-stroke jitter (sd).
  final double timingBiasMs;
  final double timingJitterMs;

  /// Time for the pick to cross all six strings.
  final double strumSpanMs;

  /// A ↓ strum misses the chord's lowest / highest string.
  final double skipBassProb;
  final double skipTopProb;

  /// Strings an ↑ strum usually reaches (±1 per stroke).
  final int upStrings;

  /// A ↓ strum also catches the open muted string below the chord's bass
  /// (low E under C or Am, A under D …).
  final double extraStringProb;

  /// Whole-guitar tuning offset and per-string spread (sd, fixed per guitar).
  final double tuningOffsetCents;
  final double stringDetuneSd;

  /// Fingers / nylon strings: no pick noise, slower attack.
  final bool soft;
  final double level;
  final int seed;

  static const ideal = PlayerModel();

  factory PlayerModel.random(int seed) {
    final r = Random(seed * 7919 + 13);
    double u(double a, double b) => a + (b - a) * r.nextDouble();
    return PlayerModel(
      timingBiasMs: u(-25, 25),
      timingJitterMs: u(10, 30),
      strumSpanMs: u(25, 80),
      skipBassProb: u(0, 0.35),
      skipTopProb: u(0, 0.3),
      upStrings: 2 + r.nextInt(3),
      extraStringProb: u(0, 0.3),
      tuningOffsetCents: u(-15, 15),
      stringDetuneSd: u(2, 7),
      soft: r.nextBool(),
      level: u(0.12, 0.26),
      seed: seed,
    );
  }

  /// Detune of each string in cents (index = string number 1–6), including
  /// the whole-guitar offset.
  List<double> stringDetunes() {
    final r = Random(seed * 31 + 7);
    double gauss() {
      final u1 = max(1e-12, r.nextDouble());
      return sqrt(-2 * log(u1)) * cos(2 * pi * r.nextDouble());
    }

    return [
      0,
      for (var s = 1; s <= 6; s++) tuningOffsetCents + stringDetuneSd * gauss(),
    ];
  }

  @override
  String toString() =>
      'bias=${timingBiasMs.round()}ms jitter=${timingJitterMs.round()}ms '
      'span=${strumSpanMs.round()}ms skipBass=${skipBassProb.toStringAsFixed(2)} '
      'skipTop=${skipTopProb.toStringAsFixed(2)} up=$upStrings '
      'extra=${extraStringProb.toStringAsFixed(2)} '
      'tune=${tuningOffsetCents.round()}c±${stringDetuneSd.round()} '
      '${soft ? 'fingers' : 'pick'} level=${level.toStringAsFixed(2)}';
}

/// A phone microphone in a room: latency, weak bass, uneven response,
/// reverb, optional automatic gain, noise.
class PhoneMic {
  const PhoneMic({
    this.latencyMs = 0,
    this.highPassHz = 100,
    this.highPassOrder = 2,
    this.eq = const [],
    this.roomRt60 = 0,
    this.roomMix = 0,
    this.agc = false,
    this.noiseLevel = 0.001,
    this.gain = 1,
  });

  /// Delay between a sound and the app receiving it.
  final double latencyMs;
  final double highPassHz;

  /// 2 = −12 dB/octave, 4 = −24 dB/octave below [highPassHz].
  final int highPassOrder;

  /// Peaking filters (centre Hz, gain dB, Q): the mic / case colouration.
  final List<(double, double, double)> eq;

  /// Room reverb time (s) and wet level (0–1).
  final double roomRt60;
  final double roomMix;

  /// Automatic gain control (some phones apply it even when asked not to).
  final bool agc;
  final double noiseLevel;
  final double gain;

  static const clean = PhoneMic();

  factory PhoneMic.random(int seed) {
    final r = Random(seed * 104729 + 3);
    double u(double a, double b) => a + (b - a) * r.nextDouble();
    return PhoneMic(
      latencyMs: u(80, 320),
      highPassHz: u(70, 260),
      highPassOrder: r.nextBool() ? 2 : 4,
      eq: [
        (u(200, 500), u(-6, 6), u(1, 2)),
        (u(1000, 4000), u(-4, 8), u(0.7, 2)),
      ],
      roomRt60: u(0.15, 0.6),
      roomMix: u(0.05, 0.35),
      agc: r.nextDouble() < 0.4,
      noiseLevel: u(0.001, 0.006),
      gain: u(0.3, 1.2),
    );
  }

  @override
  String toString() =>
      'latency=${latencyMs.round()}ms hpf=${highPassHz.round()}Hz/o$highPassOrder '
      'eq=${eq.map((e) => '${e.$1.round()}Hz${e.$2 >= 0 ? '+' : ''}${e.$2.toStringAsFixed(0)}dB').join(',')} '
      'room=${roomRt60.toStringAsFixed(2)}s×${roomMix.toStringAsFixed(2)} '
      '${agc ? 'AGC ' : ''}noise=${noiseLevel.toStringAsFixed(4)} gain=${gain.toStringAsFixed(2)}';
}

/// A rendered performance of a chart.
class Performance {
  Performance(this.dry, this.playedMs);

  /// Sound at the guitar (no room, no mic).
  final Float32List dry;

  /// Chart time at which each note (by index) was actually played.
  final List<double> playedMs;
}

/// Plays [chart] the way [player] would. Chart time 0 is at [chartStartSec].
Performance perform({
  required RhythmChart chart,
  required ChordCatalog catalog,
  required PlayerModel player,
  required int seed,
  double chartStartSec = 1.0,
}) {
  final rng = Random(seed);
  double gauss() {
    final u1 = max(1e-12, rng.nextDouble());
    return sqrt(-2 * log(u1)) * cos(2 * pi * rng.nextDouble());
  }

  final detune = player.stringDetunes();
  final events = <StringEvent>[];
  final ringing = <int, int>{}; // string → index of its latest event
  final played = List<double>.filled(chart.notes.length, 0);

  void pluck(int string, int midi, double at, double amp, {double? stopAfter}) {
    final prev = ringing[string];
    if (prev != null) {
      final e = events[prev];
      if (e.stopSec == null || e.stopSec! > at) {
        events[prev] = e.copyWith(stopSec: at);
      }
    }
    events.add(
      StringEvent(
        midi: midi,
        startSec: at,
        amplitude: amp,
        stopSec: stopAfter == null ? null : at + stopAfter,
        detuneCents: detune[string] + 2 * gauss(),
        pluckPosition: 0.12 + 0.12 * rng.nextDouble(),
        attackNoise: !player.soft,
        attackSec: player.soft ? 0.008 : 0.003,
        stringNumber: string,
      ),
    );
    ringing[string] = events.length - 1;
  }

  var prevBar = -1;
  String? prevChordId;
  for (final note in chart.notes) {
    final chord = catalog.chordById(chart.bars[note.barIndex].chordId)!;
    final playedMs =
        note.timeMs + player.timingBiasMs + player.timingJitterMs * gauss();
    played[note.index] = playedMs;
    final at = chartStartSec + playedMs / 1000;

    if (note.barIndex != prevBar) {
      if (prevChordId != null && prevChordId != chord.id) {
        // Fingers leave the old shape shortly before the new chord: fretted
        // strings stop, open strings that the new chord keeps ring on, and
        // open strings the new chord mutes also ring on (nobody damps them).
        final changeAt = at - (0.03 + 0.08 * rng.nextDouble());
        for (final entry in ringing.entries.toList()) {
          final e = events[entry.value];
          if (e.stopSec != null && e.stopSec! <= changeAt) continue;
          final next = chord.isStringMuted(entry.key)
              ? null
              : chord.noteForString(entry.key);
          final wasOpen = e.midi == simOpenMidi[entry.key];
          final keeps = next != null ? next.midi == e.midi : wasOpen;
          if (!keeps) events[entry.value] = e.copyWith(stopSec: changeAt);
        }
      }
      prevBar = note.barIndex;
      prevChordId = chord.id;
    }

    final strings = [
      for (var s = 6; s >= 1; s--)
        if (!chord.isStringMuted(s) && chord.noteForString(s) != null) s,
    ];
    final step = player.strumSpanMs / 1000 / 5;
    double gap() => step * (0.7 + 0.6 * rng.nextDouble());
    double amp(double scale) =>
        player.level * scale * (0.55 + 0.45 * rng.nextDouble());

    switch (note.kind) {
      case PatternEventKind.down:
        final hit = [...strings];
        if (hit.length > 3 && rng.nextDouble() < player.skipBassProb) {
          hit.removeAt(0);
        }
        if (hit.length > 3 && rng.nextDouble() < player.skipTopProb) {
          hit.removeLast();
        }
        var t = at;
        final below = strings.first + 1;
        if (below <= 6 &&
            chord.isStringMuted(below) &&
            rng.nextDouble() < player.extraStringProb) {
          pluck(below, simOpenMidi[below]!, t, amp(0.45));
          t += gap();
        }
        for (final s in hit) {
          pluck(s, chord.noteForString(s)!.midi, t, amp(1));
          t += gap();
        }
      case PatternEventKind.up:
        final count =
            (player.upStrings + rng.nextInt(3) - 1).clamp(2, strings.length);
        var t = at;
        for (final s in strings.reversed.take(count)) {
          pluck(s, chord.noteForString(s)!.midi, t, amp(0.6));
          t += gap();
        }
      case PatternEventKind.finger:
        final s = note.stringNumber ?? 6;
        var n = chord.isStringMuted(s) ? null : chord.noteForString(s);
        n ??= chord.noteForString(strings.first)!; // thumb → chord bass
        pluck(n.string, n.midi, at, amp(0.9));
      case PatternEventKind.mute:
        for (var s = 6; s >= 1; s--) {
          pluck(s, simOpenMidi[s]!, at + (6 - s) * 0.008, amp(0.8),
              stopAfter: 0.02);
        }
      case PatternEventKind.pause:
        break;
    }
  }

  final synth = GuitarSynth(seed: seed);
  final dry = synth.render(
    events,
    durationSec: chartStartSec + chart.durationMs / 1000 + 1.5,
    mic: const MicConditions(highPassHz: 0, noiseLevel: 0, gain: 1),
  );
  return Performance(dry, played);
}

/// What the app receives when [dry] sound is picked up by [mic].
Float32List applyPhoneMic(
  Float32List dry,
  PhoneMic mic, {
  int seed = 1,
  int sampleRate = 44100,
}) {
  // The sound reaches the app [latencyMs] late; everything the mic adds
  // (noise, gain control) is present during that delay too.
  final delay = (mic.latencyMs * sampleRate / 1000).round();
  final x = Float64List(dry.length + delay);
  for (var i = 0; i < dry.length; i++) {
    x[i + delay] = dry[i];
  }
  if (mic.roomMix > 0 && mic.roomRt60 > 0) {
    _reverb(x, mic.roomRt60, mic.roomMix, sampleRate);
  }
  for (var k = 0; k < mic.highPassOrder ~/ 2; k++) {
    _biquad(x, _highPass(mic.highPassHz, sampleRate));
  }
  for (final (hz, gainDb, q) in mic.eq) {
    _biquad(x, _peaking(hz, gainDb, q, sampleRate));
  }
  final rng = Random(seed * 17 + 5);
  double gauss() {
    final u1 = max(1e-12, rng.nextDouble());
    return sqrt(-2 * log(u1)) * cos(2 * pi * rng.nextDouble());
  }

  for (var i = 0; i < x.length; i++) {
    x[i] = x[i] * mic.gain + gauss() * mic.noiseLevel;
  }
  if (mic.agc) _agc(x, sampleRate);

  final out = Float32List(x.length);
  for (var i = 0; i < x.length; i++) {
    out[i] = x[i].clamp(-1.0, 1.0);
  }
  return out;
}

typedef _Coeffs = (double b0, double b1, double b2, double a1, double a2);

_Coeffs _highPass(double hz, int sr) {
  final w0 = 2 * pi * hz / sr;
  final alpha = sin(w0) / (2 * sqrt1_2);
  final c = cos(w0);
  final a0 = 1 + alpha;
  return ((1 + c) / 2 / a0, -(1 + c) / a0, (1 + c) / 2 / a0, -2 * c / a0,
      (1 - alpha) / a0);
}

_Coeffs _peaking(double hz, double gainDb, double q, int sr) {
  final a = pow(10, gainDb / 40).toDouble();
  final w0 = 2 * pi * hz / sr;
  final alpha = sin(w0) / (2 * q);
  final c = cos(w0);
  final a0 = 1 + alpha / a;
  return ((1 + alpha * a) / a0, -2 * c / a0, (1 - alpha * a) / a0, -2 * c / a0,
      (1 - alpha / a) / a0);
}

void _biquad(Float64List x, _Coeffs k) {
  var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0;
  for (var i = 0; i < x.length; i++) {
    final x0 = x[i];
    final y0 = k.$1 * x0 + k.$2 * x1 + k.$3 * x2 - k.$4 * y1 - k.$5 * y2;
    x2 = x1;
    x1 = x0;
    y2 = y1;
    y1 = y0;
    x[i] = y0;
  }
}

/// Small-room Schroeder reverb: four feedback combs into two all-passes.
void _reverb(Float64List x, double rt60, double mix, int sr) {
  final wet = Float64List(x.length);
  for (final ms in const [29.7, 37.1, 41.1, 43.7]) {
    final d = (ms * sr / 1000).round();
    final g = pow(10, -3 * (ms / 1000) / rt60).toDouble();
    final buf = Float64List(d);
    var p = 0;
    for (var i = 0; i < x.length; i++) {
      final y = buf[p];
      buf[p] = x[i] + g * y;
      p = (p + 1) % d;
      wet[i] += y * 0.25;
    }
  }
  for (final ms in const [5.0, 1.7]) {
    final d = (ms * sr / 1000).round();
    const g = 0.7;
    final buf = Float64List(d);
    var p = 0;
    for (var i = 0; i < wet.length; i++) {
      final delayed = buf[p];
      final input = wet[i] + g * delayed;
      buf[p] = input;
      p = (p + 1) % d;
      wet[i] = delayed - g * input;
    }
  }
  for (var i = 0; i < x.length; i++) {
    x[i] = x[i] + mix * wet[i];
  }
}

/// Automatic gain: fast when the signal gets loud, slow to recover.
void _agc(Float64List x, int sr) {
  const target = 0.35;
  final release = exp(-1 / (0.4 * sr));
  final gainUp = 1 - exp(-1 / (0.6 * sr));
  final gainDown = 1 - exp(-1 / (0.006 * sr));
  var env = 0.0;
  var gain = 1.0;
  for (var i = 0; i < x.length; i++) {
    final a = x[i].abs();
    env = a > env ? a : env * release;
    final wanted = (target / max(env, 1e-4)).clamp(0.3, 6.0);
    gain += (wanted - gain) * (wanted < gain ? gainDown : gainUp);
    x[i] *= gain;
  }
}
