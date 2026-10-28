import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';

/// Offline Neural Amharic Text-To-Speech (TTS) Service
/// Powered by Meta MMS-TTS VITS model running via ONNX Runtime.
class AmharicTtsService {
  static const MethodChannel _channel =
      MethodChannel('com.voice.amharic.assistant/native_actions');

  OrtSession? _session;
  final Map<String, String> _charMap = {};
  final Map<String, int> _tokenToId = {};
  bool _isInitialized = false;
  bool _isSpeaking = false;
  Future<void>? _initFuture;

  bool get isInitialized => _isInitialized;
  bool get isSpeaking => _isSpeaking;

  Future<void> init() {
    if (_isInitialized) return Future.value();
    _initFuture ??= _doInit();
    return _initFuture!;
  }

  Future<void> _doInit() async {
    if (_isInitialized) return;

    try {
      // 1. Initialize ONNX runtime environment
      OrtEnv.instance.init();

      // 2. Load uroman Amharic transliteration table
      debugPrint('[TTS] Loading uroman_amharic.json...');
      final mapStr = await rootBundle.loadString('assets/model/uroman_amharic.json');
      final Map<String, dynamic> rawMap = jsonDecode(mapStr);
      rawMap.forEach((k, v) {
        _charMap[k] = v.toString();
      });

      // 3. Load MMS-TTS Amharic token dictionary
      debugPrint('[TTS] Loading tts_tokens.txt...');
      final tokensStr = await rootBundle.loadString('assets/model/tts_tokens.txt');
      final lines = const LineSplitter().convert(tokensStr);
      for (final line in lines) {
        if (line.isEmpty) continue;
        if (line.startsWith(' ') && line.trim().isNotEmpty) {
          final id = int.tryParse(line.trim());
          if (id != null) _tokenToId[' '] = id;
        } else {
          final parts = line.trim().split(RegExp(r'\s+'));
          if (parts.length >= 2) {
            final id = int.tryParse(parts[1]);
            if (id != null) _tokenToId[parts[0]] = id;
          }
        }
      }

      // 4. Load VITS neural model directly from asset buffer
      debugPrint('[TTS] Loading tts_model.onnx directly from asset buffer...');
      final byteData = await rootBundle.load('assets/model/tts_model.onnx');
      final modelBytes = byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );

      final sessionOptions = OrtSessionOptions();
      sessionOptions.setIntraOpNumThreads(2);
      _session = OrtSession.fromBuffer(modelBytes, sessionOptions);

      _isInitialized = true;
      debugPrint('[TTS] Amharic Neural TTS Engine initialized successfully (${_tokenToId.length} tokens, ${_charMap.length} transliterations).');
    } catch (e) {
      debugPrint('[TTS] Initialization error: $e');
      rethrow;
    }
  }

  /// Transliterates Amharic text to Latin phonetic representation matching Meta MMS-TTS.
  String romanize(String text) {
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      if (_charMap.containsKey(char)) {
        buffer.write(_charMap[char]);
      } else {
        buffer.write(char);
      }
    }
    return buffer.toString().trim();
  }

  /// Converts romanized string to exact verified VITS token sequence:
  /// [bos_id=0, blank_id=0, char1, 0, char2, 0, ..., charN, 0, eos_id=0]
  List<int> tokenize(String romanizedText) {
    const int bosId = 0;
    const int blankId = 0;
    const int eosId = 0;

    final cleanText = romanizedText.toLowerCase();
    final tokens = <int>[bosId, blankId];

    for (int i = 0; i < cleanText.length; i++) {
      final ch = cleanText[i];
      final id = _tokenToId[ch];
      if (id != null) {
        tokens.add(id);
        tokens.add(blankId);
      }
    }

    tokens.add(eosId);
    return tokens;
  }

  /// Synthesizes Amharic text into raw 16 kHz 16-bit PCM bytes.
  Uint8List? synthesize(String amharicText) {
    if (!_isInitialized || _session == null) {
      debugPrint('[TTS] Synthesize called before initialization.');
      return null;
    }

    final cleanText = amharicText.replaceAll(RegExp(r'[!?\.,፣።]'), '').trim();
    if (cleanText.isEmpty) return null;

    final romanized = romanize(cleanText);
    if (romanized.isEmpty) return null;

    final tokens = tokenize(romanized);
    if (tokens.isEmpty) return null;

    final seqLen = tokens.length;
    final xShape = [1, seqLen];
    final xOrtValue = OrtValueTensor.createTensorWithDataList(tokens, xShape);

    final xLengthShape = [1];
    final xLengthOrtValue = OrtValueTensor.createTensorWithDataList([seqLen], xLengthShape);

    final noiseScaleOrtValue = OrtValueTensor.createTensorWithDataList(
      Float32List.fromList([0.667]),
      [1],
    );
    final lengthScaleOrtValue = OrtValueTensor.createTensorWithDataList(
      Float32List.fromList([1.0]),
      [1],
    );
    final noiseScaleWOrtValue = OrtValueTensor.createTensorWithDataList(
      Float32List.fromList([0.8]),
      [1],
    );

    final inputs = {
      'x': xOrtValue,
      'x_length': xLengthOrtValue,
      'noise_scale': noiseScaleOrtValue,
      'length_scale': lengthScaleOrtValue,
      'noise_scale_w': noiseScaleWOrtValue,
    };

    final runOptions = OrtRunOptions();

    try {
      final outputs = _session!.run(runOptions, inputs);

      xOrtValue.release();
      xLengthOrtValue.release();
      noiseScaleOrtValue.release();
      lengthScaleOrtValue.release();
      noiseScaleWOrtValue.release();
      runOptions.release();

      if (outputs.isEmpty || outputs[0] == null) return null;

      final dynamic rawValue = outputs[0]!.value;
      outputs[0]!.release();

      if (rawValue is! List || rawValue.isEmpty) return null;
      final batch0 = rawValue[0];
      if (batch0 is! List || batch0.isEmpty) return null;
      final channel0 = batch0[0];
      if (channel0 is! List) return null;

      final sampleCount = channel0.length;
      if (sampleCount == 0) return null;

      final rawSamples = List<double>.generate(
        sampleCount,
        (i) => (channel0[i] as num).toDouble(),
      );

      // Apply verified silence scaling (scale: 0.2, 16kHz)
      final processedSamples = _scaleSilence(rawSamples, scale: 0.2, sampleRate: 16000);

      // Convert to 16-bit linear PCM
      final int16List = Int16List(processedSamples.length);
      for (int i = 0; i < processedSamples.length; i++) {
        final sampleVal = processedSamples[i].clamp(-1.0, 1.0);
        int16List[i] = (sampleVal * 32767.0).round();
      }

      debugPrint('[TTS-DIAG] Verified output: ${int16List.length} samples (${(int16List.length / 16000.0).toStringAsFixed(2)}s at 16kHz)');
      return Uint8List.view(int16List.buffer);
    } catch (e) {
      debugPrint('[TTS] Inference error: $e');
      return null;
    }
  }

  /// Exact implementation of Sherpa's ScaleSilence (scale = 0.2)
  List<double> _scaleSilence(List<double> samples, {double scale = 0.2, int sampleRate = 16000}) {
    final int threshold = (sampleRate * 0.2).toInt(); // 3200 samples = 200ms
    final intervals = <_SilenceInterval>[];
    final numSamples = samples.length;
    int last = -1;

    for (int i = 0; i < numSamples; i++) {
      if (samples[i].abs() <= 0.01) {
        if (last == -1) {
          last = i;
        }
        continue;
      }
      if (last != -1 && (i - last) < threshold) {
        last = -1;
        continue;
      }
      if (last != -1) {
        intervals.add(_SilenceInterval(last, i));
        last = -1;
      }
    }

    if (last != -1 && (numSamples - last) > threshold) {
      intervals.add(_SilenceInterval(last, numSamples));
    }

    if (intervals.isEmpty) {
      return samples;
    }

    final result = <double>[];
    int current = 0;

    for (final interval in intervals) {
      result.addAll(samples.sublist(current, interval.start));
      current = interval.end;
      final length = interval.end - interval.start;
      final int scaledLength = (length * scale).toInt();
      result.addAll(samples.sublist(interval.start, interval.start + scaledLength));
    }

    if (current < numSamples) {
      result.addAll(samples.sublist(current));
    }

    return result;
  }

  /// Synthesizes and plays the Amharic speech natively, awaiting playback completion.
  Future<void> speak(String amharicText) async {
    try {
      if (!_isInitialized) {
        await init();
      }
      await stop();

      final pcmBytes = synthesize(amharicText);
      if (pcmBytes == null || pcmBytes.isEmpty) return;

      _isSpeaking = true;
      final sampleCount = pcmBytes.lengthInBytes ~/ 2;
      final durationMs = (sampleCount * 1000 / 16000).round();

      await _channel.invokeMethod('playPcmAudio', {'pcmData': pcmBytes});

      // Wait for playback to finish
      await Future.delayed(Duration(milliseconds: durationMs + 100));
    } catch (e) {
      debugPrint('[TTS] Speak error: $e');
    } finally {
      _isSpeaking = false;
    }
  }

  /// Immediately interrupts and halts any active audio playback.
  Future<void> stop() async {
    try {
      _isSpeaking = false;
      await _channel.invokeMethod('stopPcmAudio');
    } catch (e) {
      debugPrint('[TTS] Stop error: $e');
    }
  }

  void release() {
    _session?.release();
    _session = null;
    _isInitialized = false;
    _initFuture = null;
  }
}

class _SilenceInterval {
  final int start;
  final int end;
  const _SilenceInterval(this.start, this.end);
}
