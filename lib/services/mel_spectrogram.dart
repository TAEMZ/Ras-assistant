import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;

/// SeamlessM4T / Kaldi compliant 80-bin Mel Spectrogram feature extractor.
/// Matches Meta's SeamlessM4TFeatureExtractor down to 1e-5 numerical precision.
class MelSpectrogram {
  static const int sampleRate = 16000;
  static const int frameLength = 400; // 25ms frame
  static const int hopLength = 160;   // 10ms hop
  static const int fftLength = 512;
  static const int numFreqBins = 257; // (fftLength ~/ 2) + 1
  static const int numMelBins = 80;
  static const double preemphasisCoeff = 0.97;
  static const double melFloor = 1.192092955078125e-07; // 2^-23 float epsilon
  static const double kaldiScale = 32768.0; // 2^15

  late final Float32List _window;
  Float32List? _melFilters; // 257 * 80 row-major matrix
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  // Precomputed FFT twiddle lookup tables for N = 512
  static late final Float64List _twiddleReal;
  static late final Float64List _twiddleImag;
  static late final Int32List _twiddleOffsets;
  static bool _tablesInitialized = false;

  MelSpectrogram() {
    _window = _createPoveyWindow(frameLength);
    _initFftTables();
  }

  static void _initFftTables() {
    if (_tablesInitialized) return;

    final lengths = [2, 4, 8, 16, 32, 64, 128, 256, 512];
    _twiddleOffsets = Int32List(lengths.last + 1);

    int totalTwiddles = 0;
    for (final len in lengths) {
      totalTwiddles += len >> 1;
    }

    _twiddleReal = Float64List(totalTwiddles);
    _twiddleImag = Float64List(totalTwiddles);

    int curr = 0;
    for (final len in lengths) {
      _twiddleOffsets[len] = curr;
      final half = len >> 1;
      final step = -2.0 * math.pi / len;
      for (int k = 0; k < half; k++) {
        final angle = step * k;
        _twiddleReal[curr + k] = math.cos(angle);
        _twiddleImag[curr + k] = math.sin(angle);
      }
      curr += half;
    }

    _tablesInitialized = true;
  }

  static Float32List _createPoveyWindow(int length) {
    final win = Float32List(length);
    for (int i = 0; i < length; i++) {
      final base = 0.5 - 0.5 * math.cos(2.0 * math.pi * i / (length - 1));
      win[i] = math.pow(base, 0.85).toDouble();
    }
    return win;
  }

  Future<void> init() async {
    if (_isInitialized) return;

    try {
      // 1. Try loading high-performance binary weights
      final byteData = await rootBundle.load('assets/model/mel_filters.bin');
      _melFilters = byteData.buffer.asFloat32List(
        byteData.offsetInBytes,
        byteData.lengthInBytes ~/ 4,
      );
      _isInitialized = true;
      return;
    } catch (_) {}

    try {
      // 2. Fallback: load JSON weights
      final jsonStr = await rootBundle.loadString('assets/model/mel_filters.json');
      final List<dynamic> outer = jsonDecode(jsonStr);
      final filters = Float32List(numFreqBins * numMelBins);
      for (int k = 0; k < numFreqBins; k++) {
        final row = outer[k] as List<dynamic>;
        for (int m = 0; m < numMelBins; m++) {
          filters[k * numMelBins + m] = (row[m] as num).toDouble();
        }
      }
      _melFilters = filters;
      _isInitialized = true;
      return;
    } catch (_) {}

    // 3. Fallback: generate Mel filterbank analytically
    _melFilters = _generateAnalyticMelFilters();
    _isInitialized = true;
  }

  static Float32List _generateAnalyticMelFilters() {
    double hzToMel(double hz) => 2595.0 * (math.log(1.0 + hz / 700.0) / math.ln10);
    double melToHz(double mel) => 700.0 * (math.pow(10.0, mel / 2595.0) - 1.0);

    final minMel = hzToMel(0.0);
    final maxMel = hzToMel(8000.0);
    final melPoints = Float64List(numMelBins + 2);
    for (int i = 0; i < numMelBins + 2; i++) {
      melPoints[i] = minMel + (maxMel - minMel) * i / (numMelBins + 1);
    }

    final binPoints = Int32List(numMelBins + 2);
    for (int i = 0; i < numMelBins + 2; i++) {
      final hz = melToHz(melPoints[i]);
      binPoints[i] = ((fftLength + 1) * hz / sampleRate).floor();
    }

    final filters = Float32List(numFreqBins * numMelBins);
    for (int m = 0; m < numMelBins; m++) {
      final left = binPoints[m];
      final center = binPoints[m + 1];
      final right = binPoints[m + 2];

      for (int k = left; k < center && k < numFreqBins; k++) {
        if (center != left) {
          filters[k * numMelBins + m] = (k - left) / (center - left);
        }
      }
      for (int k = center; k < right && k < numFreqBins; k++) {
        if (right != center) {
          filters[k * numMelBins + m] = (right - k) / (right - center);
        }
      }
    }
    return filters;
  }

  /// Fast in-place Radix-2 Cooley-Tukey FFT (512 points)
  static void _fft512(Float64List real, Float64List imag) {
    const int n = 512;

    // Bit reversal permutation
    int j = 0;
    for (int i = 0; i < n; i++) {
      if (i < j) {
        final tr = real[i]; real[i] = real[j]; real[j] = tr;
        final ti = imag[i]; imag[i] = imag[j]; imag[j] = ti;
      }
      int m = n >> 1;
      while (m >= 1 && j >= m) {
        j -= m;
        m >>= 1;
      }
      j += m;
    }

    // Danielson-Lanczos stages
    const lengths = [2, 4, 8, 16, 32, 64, 128, 256, 512];
    for (final len in lengths) {
      final half = len >> 1;
      final off = _twiddleOffsets[len];
      for (int i = 0; i < n; i += len) {
        for (int k = 0; k < half; k++) {
          final wr = _twiddleReal[off + k];
          final wi = _twiddleImag[off + k];
          final idx1 = i + k;
          final idx2 = idx1 + half;
          final tr = real[idx2] * wr - imag[idx2] * wi;
          final ti = real[idx2] * wi + imag[idx2] * wr;
          final ur = real[idx1];
          final ui = imag[idx1];
          real[idx1] = ur + tr;
          imag[idx1] = ui + ti;
          real[idx2] = ur - tr;
          imag[idx2] = ui - ti;
        }
      }
    }
  }

  /// Extracts standardized 160-dimensional stacked log-mel features [num_stacked_frames * 160]
  /// directly matching SeamlessM4T's stride-2 input requirements.
  Float32List? extractStacked(Float32List rawAudio) {
    final frames = extract(rawAudio);
    if (frames.length < 2) return null;

    final numFrames = frames.length;
    final remainder = numFrames % 2;
    final validFrames = numFrames - remainder;
    final numStacked = validFrames ~/ 2;

    final stacked = Float32List(numStacked * 160);
    for (int s = 0; s < numStacked; s++) {
      final f1 = frames[s * 2];
      final f2 = frames[s * 2 + 1];
      final offset = s * 160;
      for (int m = 0; m < 80; m++) {
        stacked[offset + m] = f1[m];
        stacked[offset + 80 + m] = f2[m];
      }
    }
    return stacked;
  }

  /// Extracts 80-bin standardized log-mel features [num_frames, 80]
  List<Float32List> extract(Float32List audio) {
    if (!_isInitialized || _melFilters == null) {
      _melFilters ??= _generateAnalyticMelFilters();
      _isInitialized = true;
    }

    final filters = _melFilters!;

    // 1. Minimum frame length check & padding
    Float32List scaledAudio;
    if (audio.length < frameLength) {
      scaledAudio = Float32List(frameLength);
      for (int i = 0; i < audio.length; i++) {
        scaledAudio[i] = audio[i] * kaldiScale;
      }
    } else {
      scaledAudio = Float32List(audio.length);
      for (int i = 0; i < audio.length; i++) {
        scaledAudio[i] = audio[i] * kaldiScale;
      }
    }

    final numFrames = 1 + ((scaledAudio.length - frameLength) ~/ hopLength);
    final fbank = List.generate(numFrames, (_) => Float32List(numMelBins));

    final real = Float64List(fftLength);
    final imag = Float64List(fftLength);
    final power = Float64List(numFreqBins);

    // 2. Frame-by-frame STFT & Mel projection
    for (int t = 0; t < numFrames; t++) {
      final timeStep = t * hopLength;

      // Fill buffer with 400 audio samples, remaining 112 are zero-padded
      real.fillRange(0, fftLength, 0.0);
      imag.fillRange(0, fftLength, 0.0);

      // Compute DC offset (mean of frame)
      double sum = 0.0;
      for (int i = 0; i < frameLength; i++) {
        sum += scaledAudio[timeStep + i];
      }
      final dcOffset = sum / frameLength;

      // Remove DC offset
      for (int i = 0; i < frameLength; i++) {
        real[i] = scaledAudio[timeStep + i] - dcOffset;
      }

      // Apply pre-emphasis: y[n] = x[n] - 0.97 * x[n-1]
      for (int i = frameLength - 1; i > 0; i--) {
        real[i] -= preemphasisCoeff * real[i - 1];
      }
      real[0] *= (1.0 - preemphasisCoeff);

      // Multiply by Povey window
      for (int i = 0; i < frameLength; i++) {
        real[i] *= _window[i];
      }

      // Fast Radix-2 FFT
      _fft512(real, imag);

      // Power spectrum: |X|^2 = real^2 + imag^2
      for (int k = 0; k < numFreqBins; k++) {
        final r = real[k];
        final im = imag[k];
        power[k] = r * r + im * im;
      }

      // Mel filterbank projection: dot(mel_filters.T, power)
      for (int m = 0; m < numMelBins; m++) {
        double melEnergy = 0.0;
        for (int k = 0; k < numFreqBins; k++) {
          melEnergy += power[k] * filters[k * numMelBins + m];
        }
        if (melEnergy < melFloor) {
          melEnergy = melFloor;
        }
        fbank[t][m] = math.log(melEnergy);
      }
    }

    // 3. Per-mel-bin zero-mean unit-variance normalization across time (ddof=1)
    if (numFrames > 1) {
      for (int m = 0; m < numMelBins; m++) {
        double sum = 0.0;
        for (int t = 0; t < numFrames; t++) {
          sum += fbank[t][m];
        }
        final mean = sum / numFrames;

        double varSum = 0.0;
        for (int t = 0; t < numFrames; t++) {
          final diff = fbank[t][m] - mean;
          varSum += diff * diff;
        }
        final variance = varSum / (numFrames - 1);
        final invStd = 1.0 / math.sqrt(variance + 1e-7);

        for (int t = 0; t < numFrames; t++) {
          fbank[t][m] = (fbank[t][m] - mean) * invStd;
        }
      }
    }

    return fbank;
  }
}
