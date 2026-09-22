import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

import '../models/chord_definition.dart';
import 'frequency_utils.dart';

/// Synthesizes and plays a short chord preview from [ChordDefinition] MIDI notes.
///
/// Uses summed sine tones (with a light 2nd harmonic), gentle strum stagger,
/// and fade in/out so playback is pleasant (~1.7s) without clicks.
class ChordAudioService {
  ChordAudioService._();

  static final ChordAudioService instance = ChordAudioService._();

  static const int _sampleRate = 44100;
  static const double _durationSeconds = 1.7;
  static const int _fadeInSamples = 350; // ~8ms
  static const int _fadeOutSamples = 11025; // ~250ms
  static const double _strumDelaySeconds = 0.014;
  static const double _masterGain = 0.42;

  final AudioPlayer _player = AudioPlayer();
  var _ready = false;

  Future<void> _ensureReady() async {
    if (_ready) return;
    await _player.setPlayerMode(PlayerMode.mediaPlayer);
    await _player.setReleaseMode(ReleaseMode.stop);
    await _player.setAudioContext(
      AudioContext(
        android: const AudioContextAndroid(
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: const {AVAudioSessionOptions.mixWithOthers},
        ),
      ),
    );
    _ready = true;
  }

  /// Plays [chord] as a soft synthesized strum. Stops any previous preview first.
  Future<void> playChord(
    ChordDefinition chord, {
    double referenceA4Hz = 440.0,
  }) async {
    if (chord.notes.isEmpty) return;

    await _ensureReady();
    await _player.stop();

    final wav = _buildWav(
      frequencies: chord.notes
          .map((n) => midiToHz(n.midi, a4Hz: referenceA4Hz))
          .toList(),
    );
    await _player.play(BytesSource(wav, mimeType: 'audio/wav'));
  }

  Future<void> stop() async {
    await _player.stop();
  }

  Future<void> dispose() async {
    await _player.dispose();
    _ready = false;
  }

  Uint8List _buildWav({required List<double> frequencies}) {
    final totalSamples = (_sampleRate * _durationSeconds).round();
    final pcm = Int16List(totalSamples);
    final voiceGain = _masterGain / sqrt(frequencies.length.toDouble());
    final twoPi = 2 * pi;

    for (var v = 0; v < frequencies.length; v++) {
      final freq = frequencies[v];
      if (freq <= 0) continue;
      final start = min(
        totalSamples - 1,
        (v * _strumDelaySeconds * _sampleRate).round(),
      );
      final phaseInc = twoPi * freq / _sampleRate;
      final phaseInc2 = twoPi * (freq * 2) / _sampleRate;
      var phase = 0.0;
      var phase2 = 0.0;

      for (var i = start; i < totalSamples; i++) {
        final t = (i - start) / _sampleRate;
        // Pluck-like decay + soft 2nd harmonic.
        final envelope = exp(-1.55 * t);
        final sample =
            (sin(phase) + 0.28 * sin(phase2)) * envelope * voiceGain;
        final mixed = pcm[i] / 32767.0 + sample;
        pcm[i] = (mixed.clamp(-1.0, 1.0) * 32767).round();
        phase += phaseInc;
        phase2 += phaseInc2;
      }
    }

    // De-click: short fade-in and longer fade-out.
    final fadeIn = min(_fadeInSamples, totalSamples);
    for (var i = 0; i < fadeIn; i++) {
      final g = i / fadeIn;
      pcm[i] = (pcm[i] * g).round();
    }
    final fadeOut = min(_fadeOutSamples, totalSamples);
    final fadeStart = totalSamples - fadeOut;
    for (var i = 0; i < fadeOut; i++) {
      final g = 1.0 - (i / fadeOut);
      final idx = fadeStart + i;
      pcm[idx] = (pcm[idx] * g).round();
    }

    return _pcm16MonoToWav(pcm, _sampleRate);
  }

  Uint8List _pcm16MonoToWav(Int16List pcm, int sampleRate) {
    const channels = 1;
    const bitsPerSample = 16;
    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
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
    writeUint16(1); // PCM
    writeUint16(channels);
    writeUint32(sampleRate);
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
