import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

/// Synthesized SFX for Chord Blitz — countdown, hits, combos, urgency, records.
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
        frequencies: const [988],
        durationMs: 85,
        gain: 0.3,
      ));

  Future<void> playGo() => _play(_beep(
        frequencies: const [392, 523.25, 659.25, 783.99],
        durationMs: 360,
        gain: 0.36,
        arpeggioMs: 35,
      ));

  Future<void> playSuccess() => _play(_beep(
        frequencies: const [523.25, 659.25, 783.99],
        durationMs: 200,
        gain: 0.32,
        arpeggioMs: 28,
      ));

  /// Rising blip as the streak grows (2–4 before the milestone bonus).
  Future<void> playComboStep(int streak) {
    final base = 440.0 * pow(2, (streak.clamp(1, 8) - 1) / 12);
    return _play(_beep(
      frequencies: [base, base * 1.25],
      durationMs: 140,
      gain: 0.28,
      arpeggioMs: 25,
    ));
  }

  Future<void> playStreakBonus() => _play(_beep(
        frequencies: const [523.25, 659.25, 783.99, 1046.5, 1318.5],
        durationMs: 520,
        gain: 0.38,
        arpeggioMs: 48,
      ));

  /// Soft tick in the last seconds of the round.
  Future<void> playUrgencyTick({required bool critical}) => _play(_beep(
        frequencies: critical ? const [1244.5] : const [932.3],
        durationMs: critical ? 70 : 55,
        gain: critical ? 0.34 : 0.22,
      ));

  Future<void> playNewHighScore() => _play(_beep(
        frequencies: const [523.25, 659.25, 783.99, 1046.5, 1318.5, 1568],
        durationMs: 900,
        gain: 0.4,
        arpeggioMs: 70,
      ));

  Future<void> playGameOver() => _play(_beep(
        frequencies: const [349.23, 293.66, 220],
        durationMs: 580,
        gain: 0.3,
        arpeggioMs: 100,
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
        // Light 2nd harmonic for a less "thin beep" character.
        final sample = (sin(phase) + 0.28 * sin(phase * 2)) *
            envelope *
            voiceGain *
            0.82;
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
