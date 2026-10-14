import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

import '../models/chord_definition.dart';

/// Sounds for the rhythm game and the strumming tutorial.
///
/// Strums are synthesised per chord with Karplus–Strong plucked strings
/// (much closer to a real guitar than sine tones): ↓ runs from the bass
/// string up with ~12 ms between strings, ↑ hits only the top 3–4 strings in
/// reverse and softer, ✕ is a short damped thump. Files are written once to
/// the temp folder and played through a small pool of media players (the
/// same seek/resume approach that proved reliable for the strum preview).
class GameSoundService {
  GameSoundService._();

  static final GameSoundService instance = GameSoundService._();

  static const int _sampleRate = 22050;
  static const int _poolSize = 6;

  final List<AudioPlayer> _pool = [];
  final Map<String, String> _paths = {};
  var _poolIndex = 0;
  Directory? _dir;
  Future<void>? _init;

  AudioContext get _ctx => AudioContext(
        android: const AudioContextAndroid(
          isSpeakerphoneOn: false,
          stayAwake: false,
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.game,
          audioFocus: AndroidAudioFocus.none,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: const {AVAudioSessionOptions.mixWithOthers},
        ),
      );

  Future<void> _ensurePool() => _init ??= () async {
        final tmp = await getTemporaryDirectory();
        final dir = Directory('${tmp.path}/game_sounds');
        if (!dir.existsSync()) dir.createSync(recursive: true);
        _dir = dir;
        for (var i = 0; i < _poolSize; i++) {
          final p = AudioPlayer();
          await p.setPlayerMode(PlayerMode.mediaPlayer);
          await p.setReleaseMode(ReleaseMode.stop);
          await p.setAudioContext(_ctx);
          _pool.add(p);
        }
        await _write('tick', _tick(accent: false));
        await _write('tick_accent', _tick(accent: true));
        await _write('mute', _mute());
      }();

  /// Prepares strum sounds for [chords] (call before the game starts).
  Future<void> prepare(Iterable<ChordDefinition> chords) async {
    await _ensurePool();
    for (final chord in chords) {
      final midis = [
        for (var s = 6; s >= 1; s--)
          if (!chord.isStringMuted(s) && chord.noteForString(s) != null)
            chord.noteForString(s)!.midi,
      ];
      if (!_paths.containsKey('${chord.id}_down')) {
        await _write('${chord.id}_down', _strum(midis, down: true));
      }
      if (!_paths.containsKey('${chord.id}_up')) {
        await _write('${chord.id}_up', _strum(midis, down: false));
      }
      for (final m in midis) {
        if (!_paths.containsKey('note_$m')) {
          await _write('note_$m', _strum([m], down: true, gain: 0.8));
        }
      }
    }
  }

  Future<void> playStrum(ChordDefinition chord, {required bool down}) =>
      _play('${chord.id}_${down ? 'down' : 'up'}');

  Future<void> playMute() => _play('mute');

  /// Single string of [chord] (fingerstyle notes). Falls back to a down strum.
  Future<void> playString(ChordDefinition chord, int stringNumber) {
    final note = chord.isStringMuted(stringNumber)
        ? null
        : chord.noteForString(stringNumber);
    if (note == null) {
      // p on a muted bass string → play the chord's lowest note instead.
      final lowest = chord.notes.isEmpty ? null : chord.notes.first;
      if (lowest == null) return Future.value();
      return _play('note_${lowest.midi}');
    }
    return _play('note_${note.midi}');
  }

  Future<void> playTick({bool accent = false}) =>
      _play(accent ? 'tick_accent' : 'tick');

  Future<void> stopAll() async {
    for (final p in _pool) {
      try {
        await p.stop();
      } catch (_) {}
    }
  }

  Future<void> _play(String key) async {
    final path = _paths[key];
    if (path == null || _pool.isEmpty) return;
    final player = _pool[_poolIndex % _pool.length];
    _poolIndex++;
    try {
      if (player.state == PlayerState.playing ||
          player.state == PlayerState.paused) {
        await player.stop();
      }
      await player.setSource(DeviceFileSource(path));
      await player.seek(Duration.zero);
      await player.resume();
    } catch (_) {}
  }

  Future<void> _write(String key, Int16List pcm) async {
    final dir = _dir;
    if (dir == null) return;
    final path = '${dir.path}/$key.wav';
    await File(path).writeAsBytes(_wav(pcm), flush: true);
    _paths[key] = path;
  }

  // --- Synthesis ------------------------------------------------------------

  Int16List _strum(List<int> midis, {required bool down, double gain = 1}) {
    const duration = 1.4;
    final n = (_sampleRate * duration).round();
    final out = Float64List(n);
    final rng = Random(midis.fold<int>(7, (a, b) => a * 31 + b));
    final strings = down
        ? midis
        : midis.reversed.take(min(4, midis.length)).toList();
    final level = down ? 1.0 : 0.65;
    for (var k = 0; k < strings.length; k++) {
      final f = 440.0 * pow(2, (strings[k] - 69) / 12).toDouble();
      final start = (k * 0.012 * _sampleRate).round();
      _pluck(out, start, f, level * (0.75 + 0.25 * rng.nextDouble()), rng);
    }
    // Pick attack.
    for (var i = 0; i < (0.006 * _sampleRate).round() && i < n; i++) {
      out[i] += (rng.nextDouble() * 2 - 1) * 0.15 * exp(-i / 40.0);
    }
    return _normalize(out, 0.8 * gain);
  }

  /// Karplus–Strong string into [out] from sample [start].
  void _pluck(Float64List out, int start, double freq, double amp, Random rng) {
    final period = max(2, (_sampleRate / freq).round());
    final buf = Float64List(period);
    for (var i = 0; i < period; i++) {
      buf[i] = (rng.nextDouble() * 2 - 1) * amp;
    }
    // Brighter strings decay a little faster.
    final damping = freq < 150 ? 0.997 : (freq < 300 ? 0.995 : 0.993);
    var idx = 0;
    var prev = 0.0;
    for (var i = start; i < out.length; i++) {
      final cur = buf[idx];
      final next = damping * 0.5 * (cur + prev);
      prev = cur;
      buf[idx] = next;
      out[i] += cur;
      idx = (idx + 1) % period;
    }
  }

  Int16List _mute() {
    final n = (_sampleRate * 0.09).round();
    final out = Float64List(n);
    final rng = Random(3);
    for (var i = 0; i < n; i++) {
      final t = i / _sampleRate;
      out[i] = ((rng.nextDouble() * 2 - 1) * 0.6 + sin(2 * pi * 110 * t)) *
          exp(-t * 55);
    }
    return _normalize(out, 0.6);
  }

  Int16List _tick({required bool accent}) {
    final n = (_sampleRate * 0.05).round();
    final out = Float64List(n);
    final f = accent ? 1600.0 : 1100.0;
    for (var i = 0; i < n; i++) {
      final t = i / _sampleRate;
      out[i] = sin(2 * pi * f * t) * exp(-t * 90);
    }
    return _normalize(out, accent ? 0.5 : 0.35);
  }

  Int16List _normalize(Float64List x, double peak) {
    var m = 1e-9;
    for (final v in x) {
      m = max(m, v.abs());
    }
    final g = peak / m;
    final pcm = Int16List(x.length);
    for (var i = 0; i < x.length; i++) {
      pcm[i] = (x[i] * g * 32767).round().clamp(-32768, 32767);
    }
    return pcm;
  }

  Uint8List _wav(Int16List pcm) {
    final dataSize = pcm.length * 2;
    final b = ByteData(44 + dataSize);
    void str(int o, String s) {
      for (var i = 0; i < s.length; i++) {
        b.setUint8(o + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    b.setUint32(4, 36 + dataSize, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    b.setUint32(16, 16, Endian.little);
    b.setUint16(20, 1, Endian.little);
    b.setUint16(22, 1, Endian.little);
    b.setUint32(24, _sampleRate, Endian.little);
    b.setUint32(28, _sampleRate * 2, Endian.little);
    b.setUint16(32, 2, Endian.little);
    b.setUint16(34, 16, Endian.little);
    str(36, 'data');
    b.setUint32(40, dataSize, Endian.little);
    for (var i = 0; i < pcm.length; i++) {
      b.setInt16(44 + i * 2, pcm[i], Endian.little);
    }
    return b.buffer.asUint8List();
  }
}
