import 'dart:math';
import 'dart:typed_data';

/// The pre-rewrite RMS-ratio onset tracker (40 ms blocks, ×1.8 over the
/// quietest block 80–400 ms earlier), on a sample clock, for comparison.
class LegacyOnsetDetector {
  final int sampleRate = 44100;
  late final int _block = (sampleRate * 0.04).round();
  final _history = <double>[];
  var _sum = 0.0;
  var _count = 0;
  int? _last;

  List<int> process(Float32List samples, int startSample) {
    final out = <int>[];
    for (var i = 0; i < samples.length; i++) {
      _sum += samples[i] * samples[i];
      _count++;
      if (_count >= _block) {
        final rms = sqrt(_sum / _count);
        _sum = 0;
        _count = 0;
        final refEnd = _history.length - 2;
        if (refEnd >= 1) {
          var ref = double.infinity;
          for (var j = 0; j < refEnd; j++) {
            ref = min(ref, _history[j]);
          }
          if (rms >= 0.012 && rms >= ref * 1.8) {
            final at = startSample + i - _block;
            if (_last == null || at - _last! > sampleRate * 0.2) out.add(at);
            _last = at;
          }
        }
        _history.add(rms);
        if (_history.length > 10) _history.removeAt(0);
      }
    }
    return out;
  }
}
