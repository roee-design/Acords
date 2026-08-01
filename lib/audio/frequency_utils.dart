import 'dart:math';
import 'dart:typed_data';

/// Converts MIDI note number to Hz (equal temperament, A4 = [a4Hz]).
double midiToHz(int midi, {double a4Hz = 440.0}) {
  return a4Hz * pow(2, (midi - 69) / 12).toDouble();
}

/// Human-readable label: 6 = low E, 1 = high E.
String stringLabel(int stringNumber) {
  switch (stringNumber) {
    case 6:
      return 'low E';
    case 5:
      return 'A';
    case 4:
      return 'D';
    case 3:
      return 'G';
    case 2:
      return 'B';
    case 1:
      return 'high E';
    default:
      return 'string $stringNumber';
  }
}

/// FFT bin index for a target frequency.
int hzToBin(double targetHz, int fftSize, double sampleRate) {
  final bin = (targetHz * fftSize / sampleRate).round();
  final nyquist = fftSize ~/ 2;
  return bin.clamp(0, nyquist);
}

/// Sum magnitude in bins [centerBin - halfWidth, centerBin + halfWidth].
double binNeighborhoodEnergy(
  List<double> magnitudes,
  int centerBin, {
  int halfWidthBins = 2,
}) {
  final start = max(0, centerBin - halfWidthBins);
  final end = min(magnitudes.length - 1, centerBin + halfWidthBins);
  var sum = 0.0;
  for (var i = start; i <= end; i++) {
    sum += magnitudes[i];
  }
  return sum;
}

/// Hann window reduces spectral leakage on plucked guitar transients.
List<double> hannWindow(int length) {
  if (length <= 1) {
    return List<double>.filled(length, 1.0);
  }
  return List<double>.generate(
    length,
    (i) => 0.5 * (1 - cos(2 * pi * i / (length - 1))),
  );
}

/// Root-mean-square level of a normalized audio frame.
double frameRms(Float32List samples) {
  if (samples.isEmpty) {
    return 0;
  }
  var sumSquares = 0.0;
  for (final sample in samples) {
    sumSquares += sample * sample;
  }
  return sqrt(sumSquares / samples.length);
}
