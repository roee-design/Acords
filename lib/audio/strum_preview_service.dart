import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

import '../models/strumming_pattern.dart';

/// Reliable rhythmic preview of a [StrummingPattern].
///
/// Same proven approach as the transitions metronome:
/// mediaPlayer + preloaded sources + stop/seek/resume (not lowLatency BytesSource).
///
/// ↓ low click, ↑ high click, ✕ soft noise, finger events = pitched plucks.
class StrumPreviewService {
  StrumPreviewService._();

  static final StrumPreviewService instance = StrumPreviewService._();

  static const int _sampleRate = 44100;
  static const int _poolSize = 4;

  final List<AudioPlayer> _pool = [];
  final Map<String, String> _filePaths = {};
  var _poolIndex = 0;
  var _ready = false;
  var _playing = false;
  Timer? _tickTimer;
  void Function(int strokeIndex)? _onStroke;

  bool get isPlaying => _playing;

  AudioContext get _ctx => AudioContext(
        android: const AudioContextAndroid(
          isSpeakerphoneOn: false,
          stayAwake: false,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.none,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: const {AVAudioSessionOptions.mixWithOthers},
        ),
      );

  Future<void> ensureReady() => _ensureReady();

  Future<void> _ensureReady() async {
    if (_ready) return;

    final dir = await getTemporaryDirectory();
    final cache = Directory('${dir.path}/strum_preview');
    if (!cache.existsSync()) {
      cache.createSync(recursive: true);
    }

    Future<String> writeWav(String name, Uint8List bytes) async {
      final path = '${cache.path}/$name.wav';
      final file = File(path);
      await file.writeAsBytes(bytes, flush: true);
      _filePaths[name] = path;
      return path;
    }

    await writeWav('down', _synthClick(freq: 180, gain: 0.7, durationMs: 90));
    await writeWav('up', _synthClick(freq: 520, gain: 0.55, durationMs: 70));
    await writeWav('mute', _synthNoise(gain: 0.5, durationMs: 60));
    // Open-string arpeggio plucks.
    for (final entry in const {
      's6': 82.41,
      's5': 110.0,
      's4': 146.83,
      's3': 196.0,
      's2': 246.94,
      's1': 329.63,
    }.entries) {
      await writeWav(
        entry.key,
        _synthPluck(freq: entry.value, gain: 0.45, durationMs: 160),
      );
    }

    // Also keep metronome asset as fallback down-click.
    for (var i = 0; i < _poolSize; i++) {
      final p = AudioPlayer();
      await p.setPlayerMode(PlayerMode.mediaPlayer);
      await p.setReleaseMode(ReleaseMode.stop);
      await p.setAudioContext(_ctx);
      await p.setVolume(1);
      _pool.add(p);
    }

    _ready = true;
  }

  /// Starts a looping tick sequence for [pattern] at [bpm].
  Future<void> play({
    required StrummingPattern pattern,
    required int bpm,
    void Function(int strokeIndex)? onStroke,
  }) async {
    await stop();
    if (pattern.events.isEmpty || bpm <= 0) return;

    try {
      await _ensureReady();
      _onStroke = onStroke;
      _playing = true;

      final msPerSlot =
          ((60000.0 / bpm) / pattern.subdivision).round().clamp(50, 2000);
      var index = 0;

      await _fireEvent(pattern.events[0]);
      _onStroke?.call(0);

      _tickTimer = Timer.periodic(Duration(milliseconds: msPerSlot), (_) {
        if (!_playing) return;
        index = (index + 1) % pattern.events.length;
        unawaited(_fireEvent(pattern.events[index]));
        _onStroke?.call(index);
      });
    } catch (_) {
      await stop();
    }
  }

  Future<void> _fireEvent(PatternEvent event) async {
    final key = switch (event.kind) {
      PatternEventKind.pause => null,
      PatternEventKind.down => 'down',
      PatternEventKind.up => 'up',
      PatternEventKind.mute => 'mute',
      PatternEventKind.finger => 's${event.stringNumber ?? 3}',
    };
    if (key == null) return;
    await _playKey(key);
  }

  Future<void> _playKey(String key) async {
    if (_pool.isEmpty) return;
    final path = _filePaths[key];
    final player = _pool[_poolIndex % _pool.length];
    _poolIndex++;

    try {
      if (path != null) {
        // Prefer seek/resume when the same file is already loaded.
        final state = player.state;
        if (state == PlayerState.playing || state == PlayerState.paused) {
          await player.stop();
        }
        await player.setSource(DeviceFileSource(path));
        await player.setVolume(1);
        await player.seek(Duration.zero);
        await player.resume();
        return;
      }
    } catch (_) {
      // Fall through to asset click.
    }

    try {
      await player.stop();
      await player.play(
        AssetSource('metronome_click.wav'),
        volume: key == 'up' ? 0.55 : (key == 'mute' ? 0.35 : 1.0),
        ctx: _ctx,
      );
    } catch (_) {}
  }

  Future<void> stop() async {
    _tickTimer?.cancel();
    _tickTimer = null;
    _onStroke = null;
    _playing = false;
    for (final p in _pool) {
      try {
        await p.stop();
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    await stop();
    for (final p in _pool) {
      try {
        await p.dispose();
      } catch (_) {}
    }
    _pool.clear();
    _filePaths.clear();
    _ready = false;
  }

  Uint8List _synthClick({
    required double freq,
    required double gain,
    required int durationMs,
  }) {
    final n = max(1, (_sampleRate * durationMs / 1000).round());
    final pcm = Int16List(n);
    final twoPi = 2 * pi;
    var phase = 0.0;
    final phaseInc = twoPi * freq / _sampleRate;
    for (var i = 0; i < n; i++) {
      final t = i / _sampleRate;
      final env = exp(-18 * t);
      final sample = (sin(phase) + 0.4 * sin(phase * 2)) * env * gain;
      pcm[i] = (sample.clamp(-1.0, 1.0) * 32767).round();
      phase += phaseInc;
    }
    return _pcm16MonoToWav(pcm);
  }

  Uint8List _synthPluck({
    required double freq,
    required double gain,
    required int durationMs,
  }) {
    final n = max(1, (_sampleRate * durationMs / 1000).round());
    final pcm = Int16List(n);
    final twoPi = 2 * pi;
    var phase = 0.0;
    final phaseInc = twoPi * freq / _sampleRate;
    for (var i = 0; i < n; i++) {
      final t = i / _sampleRate;
      final env = exp(-6 * t);
      final sample = (sin(phase) +
              0.45 * sin(phase * 2) +
              0.2 * sin(phase * 3)) *
          env *
          gain;
      pcm[i] = (sample.clamp(-1.0, 1.0) * 32767).round();
      phase += phaseInc;
    }
    return _pcm16MonoToWav(pcm);
  }

  Uint8List _synthNoise({required double gain, required int durationMs}) {
    final n = max(1, (_sampleRate * durationMs / 1000).round());
    final pcm = Int16List(n);
    final rng = Random(11);
    for (var i = 0; i < n; i++) {
      final t = i / _sampleRate;
      final env = exp(-35 * t);
      final sample = (rng.nextDouble() * 2 - 1) * env * gain;
      pcm[i] = (sample.clamp(-1.0, 1.0) * 32767).round();
    }
    return _pcm16MonoToWav(pcm);
  }

  Uint8List _pcm16MonoToWav(Int16List pcm) {
    const channels = 1;
    const bitsPerSample = 16;
    final byteRate = _sampleRate * channels * bitsPerSample ~/ 8;
    final blockAlign = channels * bitsPerSample ~/ 8;
    final dataSize = pcm.length * 2;
    final fileSize = 36 + dataSize;

    final buffer = BytesBuilder(copy: false);
    void writeString(String s) => buffer.add(s.codeUnits);
    void writeUint32(int v) {
      final b = ByteData(4)..setUint32(0, v, Endian.little);
      buffer.add(b.buffer.asUint8List());
    }

    void writeUint16(int v) {
      final b = ByteData(2)..setUint16(0, v, Endian.little);
      buffer.add(b.buffer.asUint8List());
    }

    writeString('RIFF');
    writeUint32(fileSize);
    writeString('WAVE');
    writeString('fmt ');
    writeUint32(16);
    writeUint16(1);
    writeUint16(channels);
    writeUint32(_sampleRate);
    writeUint32(byteRate);
    writeUint16(blockAlign);
    writeUint16(bitsPerSample);
    writeString('data');
    writeUint32(dataSize);

    final pcmBytes = ByteData(dataSize);
    for (var i = 0; i < pcm.length; i++) {
      pcmBytes.setInt16(i * 2, pcm[i], Endian.little);
    }
    buffer.add(pcmBytes.buffer.asUint8List());
    return buffer.toBytes();
  }
}
