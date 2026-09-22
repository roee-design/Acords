import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

/// Short synthesized SFX for Chord Blitz (countdown, success, streak, game over).
class BlitzSfxService {
  BlitzSfxService._();

  static final BlitzSfxService instance = BlitzSfxService._();

  static const int _sampleRate = 44100;

  final AudioPlayer _player = AudioPlayer();
  var _ready = false;

  Future<void> _ensureReady() async {
    if (_ready) return;
    await _player.setPlayerMode(PlayerMode.lowLatency);
    await _player.setReleaseMode(ReleaseMode.stop);
    await _player.setAudioContext(
      AudioContext(
        android: const AudioContextAndroid(
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.game,
          audioFocus: AndroidAudioFocus.none,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.ambient,
          options: const {AVAudioSessionOptions.mixWithOthers},
        ),
      ),
    );
    _ready = true;
  }

  Future<void> playCountdownTick() => _play(_beep(
        frequencies: const [880],
        durationMs: 90,
        gain: 0.28,
      ));

  Future<void> playGo() => _play(_beep(
        frequencies: const [523.25, 659.25, 783.99],
        durationMs: 280,
        gain: 0.32,
        arpeggioMs: 40,
      ));

  Future<void> playSuccess() => _play(_beep(
        frequencies: const [659.25, 830.61],
        durationMs: 180,
        gain: 0.3,
        arpeggioMs: 45,
      ));

  Future<void> playStreakBonus() => _play(_beep(
        frequencies: const [523.25, 659.25, 783.99, 1046.5],
        durationMs: 420,
        gain: 0.34,
        arpeggioMs: 55,
      ));

  Future<void> playGameOver() => _play(_beep(
        frequencies: const [392, 311.13, 246.94],
        durationMs: 520,
        gain: 0.3,
        arpeggioMs: 90,
      ));

  Future<void> _play(Uint8List wav) async {
    try {
      await _ensureReady();
      await _player.stop();
      await _player.play(BytesSource(wav, mimeType: 'audio/wav'));
    } catch (_) {
      // SFX must never break gameplay.
    }
  }

  Future<void> dispose() async {
    await _player.dispose();
    _ready = false;
  }

  Uint8List _beep({
    required List<double> frequencies,
    required int durationMs,
    required double gain,
    int arpeggioMs = 0,
  }) {
    final totalSamples = (_sampleRate * durationMs / 1000).round();
    final pcm = Int16List(totalSamples);
    final twoPi = 2 * pi;
    final fadeIn = min(400, totalSamples ~/ 8);
    final fadeOut = min(1200, totalSamples ~/ 3);

    for (var v = 0; v < frequencies.length; v++) {
      final freq = frequencies[v];
      final start = min(
        totalSamples - 1,
        ((v * arpeggioMs) * _sampleRate / 1000).round(),
      );
      var phase = 0.0;
      final phaseInc = twoPi * freq / _sampleRate;
      final voiceGain = gain / sqrt(frequencies.length.toDouble());

      for (var i = start; i < totalSamples; i++) {
        final t = (i - start) / _sampleRate;
        final envelope = exp(-3.2 * t);
        final sample = sin(phase) * envelope * voiceGain;
        final mixed = pcm[i] / 32767.0 + sample;
        pcm[i] = (mixed.clamp(-1.0, 1.0) * 32767).round();
        phase += phaseInc;
      }
    }

    for (var i = 0; i < fadeIn; i++) {
      pcm[i] = (pcm[i] * (i / fadeIn)).round();
    }
    final fadeStart = totalSamples - fadeOut;
    for (var i = 0; i < fadeOut; i++) {
      final g = 1.0 - (i / fadeOut);
      pcm[fadeStart + i] = (pcm[fadeStart + i] * g).round();
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
