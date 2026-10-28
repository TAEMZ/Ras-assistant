import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:path_provider/path_provider.dart';

import 'mel_spectrogram.dart';

class AmharicAsrService {
  OrtSession? _session;
  final Map<int, String> _idToChar = {};
  final MelSpectrogram _melExtractor = MelSpectrogram();
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  static const int padTokenId = 408;
  static const int wordDelimiterId = 0;

  Future<void> init() async {
    if (_isInitialized) return;

    try {
      // 1. Initialize ONNX runtime environment
      OrtEnv.instance.init();

      // 2. Initialize Mel Spectrogram feature extractor
      await _melExtractor.init();

      // 3. Load and parse vocabulary
      final vocabJsonStr = await rootBundle.loadString('assets/model/vocab.json');
      final Map<String, dynamic> vocabMap = jsonDecode(vocabJsonStr);
      vocabMap.forEach((char, id) {
        _idToChar[id as int] = char;
      });

      // 4. Load model directly from assets buffer (zero storage duplication)
      debugPrint('Loading model_int8.onnx directly from asset buffer...');
      final byteData = await rootBundle.load('assets/model/model_int8.onnx');
      final modelBytes = byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );

      // Clean up legacy 585MB file from internal app storage to reclaim space
      try {
        final appDir = await getApplicationDocumentsDirectory();
        final legacyModelFile = File('${appDir.path}/model_int8.onnx');
        if (await legacyModelFile.exists()) {
          await legacyModelFile.delete();
          debugPrint('Purged legacy duplicate model_int8.onnx from device storage (freed ~585MB).');
        }
      } catch (e) {
        debugPrint('Storage cleanup note: $e');
      }

      // 5. Create ONNX inference session directly from buffer
      final sessionOptions = OrtSessionOptions();
      sessionOptions.setIntraOpNumThreads(2);
      _session = OrtSession.fromBuffer(modelBytes, sessionOptions);
      _isInitialized = true;
      debugPrint('Amharic ASR Engine successfully initialized.');
    } catch (e) {
      debugPrint('Failed to initialize Amharic ASR: $e');
      rethrow;
    }
  }

  Future<String> transcribe(Float32List audio) async {
    if (!_isInitialized || _session == null) {
      throw StateError('ASR engine is not initialized');
    }

    // 1. Extract 160-dim stacked features directly [num_stacked_frames * 160]
    final flattened = _melExtractor.extractStacked(audio);
    if (flattened == null || flattened.isEmpty) return '';

    final numStackedFrames = flattened.length ~/ 160;
    if (numStackedFrames < 1) return '';

    // 2. Create input tensor [1, num_stacked_frames, 160]
    final shape = [1, numStackedFrames, 160];
    final inputOrtValue = OrtValueTensor.createTensorWithDataList(flattened, shape);
    final inputs = {'input_features': inputOrtValue};
    final runOptions = OrtRunOptions();

    try {
      // 3. Run model inference
      final outputs = _session!.run(runOptions, inputs);
      inputOrtValue.release();
      runOptions.release();

      if (outputs.isEmpty || outputs[0] == null) return '';

      final rawValue = outputs[0]!.value;
      outputs[0]!.release();

      // 4. Decode CTC output
      final text = _ctcGreedyDecode(rawValue);
      debugPrint('Transcribed ASR Output: "$text"');
      return text;
    } catch (e) {
      debugPrint('Inference error: $e');
      return '';
    }
  }

  String _ctcGreedyDecode(dynamic outputData) {
    if (outputData is! List) return '';

    // output is typically [1, time_steps, vocab_size]
    final batch = outputData[0] as List;
    final timeSteps = batch.length;
    final tokenIds = <int>[];

    for (int t = 0; t < timeSteps; t++) {
      final logits = batch[t] as List;
      int maxIdx = 0;
      double maxVal = -1e9;
      for (int i = 0; i < logits.length; i++) {
        final val = (logits[i] as num).toDouble();
        if (val > maxVal) {
          maxVal = val;
          maxIdx = i;
        }
      }
      tokenIds.add(maxIdx);
    }

    // Diagnostic log of non-pad tokens
    final nonPadTokens = tokenIds.where((id) => id != padTokenId).toList();
    if (nonPadTokens.isNotEmpty) {
      debugPrint('Non-pad tokens emitted (${nonPadTokens.length}): $nonPadTokens');
    }

    // CTC collapse repeated and filter blanks
    final decoded = StringBuffer();
    int prevToken = -1;

    for (final tokenId in tokenIds) {
      if (tokenId == padTokenId) {
        prevToken = tokenId;
        continue;
      }

      if (tokenId != prevToken) {
        if (tokenId == wordDelimiterId) {
          decoded.write(' ');
        } else if (_idToChar.containsKey(tokenId)) {
          final char = _idToChar[tokenId]!;
          if (!char.startsWith('[') && !char.startsWith('<')) {
            decoded.write(char);
          }
        }
      }
      prevToken = tokenId;
    }

    return decoded.toString().trim();
  }

  void dispose() {
    _session?.release();
    _session = null;
    _isInitialized = false;
  }
}
