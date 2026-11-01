import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../chord/chord_matcher.dart';
import '../game/guitar_stroke_referee.dart';
import 'audio_analyzer.dart';
import 'onset_detector.dart';

/// Detection diagnostics for a listening session (debug builds).
///
/// Logs to `adb logcat` with the tag `[Acords Diag]`:
/// * `LEVEL` — every 250 ms: min / median / max of hop RMS and spectral
///   flux, the flux threshold and the background level (what the detector
///   sees while you do nothing);
/// * `PEAK` — every local flux maximum with all its numbers and either
///   `ONSET` or the rules that rejected it;
/// * `STROKE` — every strum the game judged: the referee's outcome and the
///   matcher's per-string analysis of that strum.
///
/// [save] writes the log, the raw audio (WAV) and a JSON description of the
/// session so the false-positive bench can replay it exactly.
class DetectionDiagnostics {
  DetectionDiagnostics({this.levelIntervalMs = 250, this.echo = true});

  final int levelIntervalMs;

  /// Also print each line (logcat); benches keep the lines only.
  final bool echo;
  final List<String> lines = [];

  OnsetDetector? _detector;
  ChordMatcher? _matcher;
  ChordMatchRecord? _lastMatch;
  final List<double> _rms = [];
  final List<double> _flux = [];
  double _lastThreshold = 0;
  double _lastFloor = 0;
  double _windowStartSec = 0;

  void attach(AudioAnalyzer analyzer) =>
      attachTo(analyzer.onsetDetector, analyzer.matcher);

  /// Attaches to a detector + matcher directly (benches use the engine's).
  void attachTo(OnsetDetector detector, ChordMatcher matcher) {
    _detector = detector;
    _matcher = matcher;
    detector.onHop = _onHop;
    matcher.onEvaluate = (r) => _lastMatch = r;
    log('SESSION start');
  }

  void detach() {
    _detector?.onHop = null;
    _matcher?.onEvaluate = null;
    _detector = null;
    _matcher = null;
  }

  void log(String line) {
    lines.add(line);
    if (echo) debugPrint('[Acords Diag] $line');
  }

  void _onHop(OnsetHopRecord r) {
    if (_rms.isEmpty) _windowStartSec = r.timeSec;
    _rms.add(r.rms);
    _flux.add(r.flux);
    _lastThreshold = r.threshold;
    _lastFloor = r.noiseFloor;
    if (r.isPeak) log('PEAK ${r.toLogLine()}');
    if ((r.timeSec - _windowStartSec) * 1000 >= levelIntervalMs) {
      String stats(List<double> v, int digits) {
        final s = [...v]..sort();
        return '${s.first.toStringAsFixed(digits)}/'
            '${s[s.length ~/ 2].toStringAsFixed(digits)}/'
            '${s.last.toStringAsFixed(digits)}';
      }

      log('LEVEL t=${r.timeSec.toStringAsFixed(2)} '
          'rms(min/med/max)=${stats(_rms, 4)} '
          'flux(min/med/max)=${stats(_flux, 3)} '
          'thr=${_lastThreshold.toStringAsFixed(3)} '
          'floor=${_lastFloor.toStringAsFixed(4)}');
      _rms.clear();
      _flux.clear();
    }
  }

  /// Logs a judged strum together with the matcher's analysis of it.
  void decision(CaptureDecision d) {
    log('STROKE ${d.toLogLine()} || ${_lastMatch?.toLogLine() ?? '-'}');
  }

  /// Writes `NAME.log`, `NAME.wav` and `NAME.json` to the app's external
  /// files folder (`adb pull
  /// /sdcard/Android/data/com.chordtrainer.chord_trainer/files/diagnostics`).
  /// Returns the folder path.
  Future<String> save({
    required String name,
    required Uint8List? pcm16,
    required int sampleRate,
    required Map<String, Object?> session,
  }) async {
    final base = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/diagnostics');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    await File('${dir.path}/$name.log').writeAsString(lines.join('\n'));
    await File('${dir.path}/$name.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert(session),
    );
    if (pcm16 != null) {
      await File('${dir.path}/$name.wav').writeAsBytes(wavBytes(pcm16, sampleRate));
    }
    log('SESSION saved to ${dir.path}/$name.*');
    return dir.path;
  }

  /// PCM16 mono → WAV file bytes.
  static Uint8List wavBytes(Uint8List pcm16, int sampleRate) {
    final header = ByteData(44);
    void str(int o, String s) {
      for (var i = 0; i < s.length; i++) {
        header.setUint8(o + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    header.setUint32(4, 36 + pcm16.length, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * 2, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    str(36, 'data');
    header.setUint32(40, pcm16.length, Endian.little);
    return Uint8List.fromList([...header.buffer.asUint8List(), ...pcm16]);
  }
}
