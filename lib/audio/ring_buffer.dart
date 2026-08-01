import 'dart:typed_data';

/// Fixed-size circular buffer for PCM samples (avoids O(n) removeAt(0)).
class AudioRingBuffer {
  AudioRingBuffer(this.capacity) : _data = Float64List(capacity);

  final int capacity;
  final Float64List _data;

  int _writeIndex = 0;
  int _filled = 0;

  void clear() {
    _data.fillRange(0, _data.length, 0);
    _writeIndex = 0;
    _filled = 0;
  }

  void writeSample(double sample) {
    _data[_writeIndex] = sample;
    _writeIndex = (_writeIndex + 1) % capacity;
    if (_filled < capacity) {
      _filled++;
    }
  }

  void writePcm16LeBytes(List<int> bytes) {
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      final unsigned = bytes[i] | (bytes[i + 1] << 8);
      final signed = unsigned >= 0x8000 ? unsigned - 0x10000 : unsigned;
      writeSample(signed / 32768.0);
    }
  }

  bool get isFull => _filled >= capacity;

  /// Oldest-to-newest frame of exactly [capacity] samples for FFT input.
  Float32List toOrderedFrame() {
    final frame = Float32List(capacity);
    if (_filled < capacity) {
      return frame;
    }

    final start = _writeIndex;
    for (var i = 0; i < capacity; i++) {
      frame[i] = _data[(start + i) % capacity];
    }
    return frame;
  }
}
