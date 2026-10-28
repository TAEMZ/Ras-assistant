import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';

import 'intent_engine.dart';

class SemanticIntentService {
  OrtSession? _session;
  final Map<String, int> _vocab = {};
  final Map<String, List<double>> _actionAnchors = {};
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  static const int clsTokenId = 101;
  static const int sepTokenId = 102;
  static const int unkTokenId = 100;
  static const int padTokenId = 0;
  static const int maxSeqLen = 64;

  Future<void> init() async {
    if (_isInitialized) return;

    try {
      debugPrint('[SemanticIntentService] Initializing on-device neural embedding engine...');
      OrtEnv.instance.init();

      // 1. Load WordPiece Vocabulary
      final vocabStr = await rootBundle.loadString('assets/model/intent_vocab.txt');
      final lines = const LineSplitter().convert(vocabStr);
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isNotEmpty) {
          _vocab[line] = i;
        }
      }
      debugPrint('[SemanticIntentService] Loaded ${_vocab.length} vocabulary tokens.');

      // 2. Load Precomputed Action Anchors
      final anchorsJsonStr = await rootBundle.loadString('assets/model/action_anchors.json');
      final Map<String, dynamic> rawAnchors = jsonDecode(anchorsJsonStr);
      rawAnchors.forEach((key, val) {
        _actionAnchors[key] = (val as List).map((e) => (e as num).toDouble()).toList();
      });
      debugPrint('[SemanticIntentService] Loaded action anchors: ${_actionAnchors.keys.toList()}');

      // 3. Load ONNX Model Buffer
      final byteData = await rootBundle.load('assets/model/intent_embed.onnx');
      final modelBytes = byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );

      final sessionOptions = OrtSessionOptions();
      sessionOptions.setIntraOpNumThreads(2);
      _session = OrtSession.fromBuffer(modelBytes, sessionOptions);
      _isInitialized = true;
      debugPrint('[SemanticIntentService] Neural Intent Model successfully loaded into memory.');
    } catch (e) {
      debugPrint('[SemanticIntentService] Initialization failed: $e');
      rethrow;
    }
  }

  /// Tokenize text into WordPiece token IDs, attention mask, and token type IDs
  Map<String, List<int>> _tokenize(String text) {
    final words = text.toLowerCase().trim().split(RegExp(r'\s+'));
    final List<int> tokens = [clsTokenId];

    for (final word in words) {
      if (word.isEmpty) continue;
      if (_vocab.containsKey(word)) {
        tokens.add(_vocab[word]!);
      } else {
        // Subword matching
        int start = 0;
        final subTokens = <int>[];
        while (start < word.length) {
          int end = word.length;
          int? curSubstrId;
          while (start < end) {
            String substr = word.substring(start, end);
            if (start > 0) substr = '##$substr';
            if (_vocab.containsKey(substr)) {
              curSubstrId = _vocab[substr];
              break;
            }
            end--;
          }
          if (curSubstrId == null) {
            subTokens.add(unkTokenId);
            break;
          }
          subTokens.add(curSubstrId);
          start = end;
        }
        tokens.addAll(subTokens);
      }
      if (tokens.length >= maxSeqLen - 1) break;
    }

    tokens.add(sepTokenId);

    // Pre-allocate fixed-size lists of maxSeqLen directly to avoid fixed-length addAll crash
    final inputIds = List<int>.filled(maxSeqLen, padTokenId);
    final attentionMask = List<int>.filled(maxSeqLen, 0);
    final tokenTypeIds = List<int>.filled(maxSeqLen, 0);

    final tokenCount = math.min(tokens.length, maxSeqLen);
    for (int i = 0; i < tokenCount; i++) {
      inputIds[i] = tokens[i];
      attentionMask[i] = 1;
    }

    return {
      'input_ids': inputIds,
      'attention_mask': attentionMask,
      'token_type_ids': tokenTypeIds,
    };
  }

  /// Run ONNX embedding inference and mean pooling to produce a 384-dimensional unit vector
  List<double> embed(String text) {
    if (!_isInitialized || _session == null) {
      throw StateError('SemanticIntentService is not initialized');
    }

    final tokenMap = _tokenize(text);
    final inputIds = tokenMap['input_ids']!;
    final attentionMask = tokenMap['attention_mask']!;
    final tokenTypeIds = tokenMap['token_type_ids']!;

    final shape = [1, maxSeqLen];
    final inputIdsTensor = OrtValueTensor.createTensorWithDataList(inputIds, shape);
    final attentionMaskTensor = OrtValueTensor.createTensorWithDataList(attentionMask, shape);
    final tokenTypeIdsTensor = OrtValueTensor.createTensorWithDataList(tokenTypeIds, shape);

    final inputs = {
      'input_ids': inputIdsTensor,
      'attention_mask': attentionMaskTensor,
      'token_type_ids': tokenTypeIdsTensor,
    };

    final runOptions = OrtRunOptions();
    try {
      final outputs = _session!.run(runOptions, inputs);
      inputIdsTensor.release();
      attentionMaskTensor.release();
      tokenTypeIdsTensor.release();
      runOptions.release();

      if (outputs.isEmpty || outputs[0] == null) {
        return List<double>.filled(384, 0.0);
      }

      // last_hidden_state: [1, maxSeqLen, 384]
      final rawData = outputs[0]!.value;
      outputs[0]!.release();

      return _meanPoolAndNormalize(rawData, attentionMask);
    } catch (e) {
      debugPrint('[SemanticIntentService] Inference error: $e');
      return List<double>.filled(384, 0.0);
    }
  }

  List<double> _meanPoolAndNormalize(dynamic rawHiddenState, List<int> attentionMask) {
    if (rawHiddenState == null) {
      return List<double>.filled(384, 0.0);
    }

    final pooled = List<double>.filled(384, 0.0);
    double validCount = 0.0;

    if (rawHiddenState is List && rawHiddenState.isNotEmpty) {
      if (rawHiddenState[0] is List) {
        // Nested: [1, maxSeqLen, 384]
        final seq = rawHiddenState[0] as List;
        for (int i = 0; i < seq.length && i < attentionMask.length; i++) {
          if (attentionMask[i] == 1 && seq[i] is List) {
            final hidden = seq[i] as List;
            for (int d = 0; d < 384 && d < hidden.length; d++) {
              pooled[d] += (hidden[d] as num).toDouble();
            }
            validCount += 1.0;
          }
        }
      } else {
        // Flattened 1D list: [1 * maxSeqLen * 384]
        final flat = rawHiddenState;
        for (int i = 0; i < attentionMask.length; i++) {
          if (attentionMask[i] == 1) {
            final offset = i * 384;
            if (offset + 384 <= flat.length) {
              for (int d = 0; d < 384; d++) {
                pooled[d] += (flat[offset + d] as num).toDouble();
              }
              validCount += 1.0;
            }
          }
        }
      }
    }

    if (validCount > 0) {
      for (int d = 0; d < 384; d++) {
        pooled[d] /= validCount;
      }
    }

    // L2 normalize
    double normSq = 0.0;
    for (int d = 0; d < 384; d++) {
      normSq += pooled[d] * pooled[d];
    }
    final norm = math.sqrt(normSq);
    if (norm > 1e-9) {
      for (int d = 0; d < 384; d++) {
        pooled[d] /= norm;
      }
    }

    return pooled;
  }

  /// Classify query using neural vector cosine similarity against action anchors
  Future<IntentResult> classify(
    String query, {
    List<String> availableContacts = const [],
    List<Map<String, String>> availableApps = const [],
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return IntentResult(
        action: ActionType.none,
        rawQuery: query,
        description: 'No query detected',
      );
    }

    // 1. Compute query embedding vector
    final queryVec = embed(trimmed);

    // 2. Compute cosine similarity (dot product) against all action anchors
    final scores = <String, double>{};
    _actionAnchors.forEach((actionKey, anchorVec) {
      double dot = 0.0;
      for (int d = 0; d < 384; d++) {
        dot += queryVec[d] * anchorVec[d];
      }
      scores[actionKey] = dot;
    });

    final sortedEntries = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final bestMatch = sortedEntries.first;

    debugPrint('[SemanticIntentService] Query: "$query" -> Top: ${bestMatch.key} (${bestMatch.value.toStringAsFixed(4)})');
    for (final e in sortedEntries) {
      debugPrint('   • ${e.key}: ${e.value.toStringAsFixed(4)}');
    }

    // 3. Route to Action based on Neural Match
    switch (bestMatch.key) {
      case 'search_files':
        return _resolveFileSearch(trimmed, query);

      case 'launch_app':
        return _resolveAppLaunch(trimmed, query, availableApps);

      case 'call_contact':
        return _resolveCallContact(trimmed, query, availableContacts);

      case 'device_status':
        if (trimmed.toLowerCase().contains('storage') || trimmed.contains('ማከማቻ') || trimmed.contains('ቦታ')) {
          return IntentResult(
            action: ActionType.getStorage,
            rawQuery: query,
            description: 'Checking device storage space',
          );
        }
        return IntentResult(
          action: ActionType.getBattery,
          rawQuery: query,
          description: 'Checking battery level',
        );

      case 'joke_and_banter':
      default:
        final isAmharic = RegExp(r'[\u1200-\u137F]').hasMatch(trimmed);
        final lower = trimmed.toLowerCase();
        final isGreeting = lower == 'hi' || lower == 'hello' || lower == 'hey' ||
            lower.startsWith('hi ') || lower.startsWith('hello ') || lower.startsWith('hey ') ||
            trimmed.contains('ሰላም');

        if (isGreeting) {
          return IntentResult(
            action: ActionType.greeting,
            rawQuery: query,
            conversationalResponse: isAmharic ? 'ሰላም! ምን ልርዳዎት?' : 'Hello! How can I help you today?',
            description: 'Greeting response',
          );
        }

        if (lower.contains('joke') || trimmed.contains('ቀልድ') || trimmed.contains('አስቀኝ')) {
          return IntentResult(
            action: ActionType.joke,
            rawQuery: query,
            conversationalResponse: isAmharic
                ? 'አንድ ሰውዬ ሱቅ ገብቶ "ስኳር አለ?" አለ። ሱቅ ነጋሪው "አዎ አለ" አለው። "እንግዲያው ሻይ ስራና ጠጣ" ብሎት እርፍ! 😆'
                : 'Why was the math book sad? Because it had too many problems! 😆',
            description: 'Telling a joke',
          );
        }
        return IntentResult(
          action: ActionType.banter,
          rawQuery: query,
          conversationalResponse: isAmharic ? 'ሰላም ነው! ምን ልርዳዎት?' : 'Hello! How can I assist you with your device today?',
          description: 'Conversational response',
        );
    }
  }

  IntentResult _resolveFileSearch(String clean, String rawQuery) {
    final lower = clean.toLowerCase();

    // Dynamically deduce category from standard media types and extensions
    String category = 'all';
    if (lower.contains('pdf') || lower.contains('ፒዲኤፍ')) {
      category = 'pdf';
    } else if (lower.contains('mp3') || lower.contains('audio') || lower.contains('music') || lower.contains('song') || lower.contains('ሙዚቃ') || lower.contains('ድምጽ')) {
      category = 'audio';
    } else if (lower.contains('photo') || lower.contains('image') || lower.contains('picture') || lower.contains('pic') || lower.contains('ፎቶ') || lower.contains('ምስል')) {
      category = 'image';
    } else if (lower.contains('video') || lower.contains('mp4') || lower.contains('mkv') || lower.contains('movie') || lower.contains('ቪዲዮ')) {
      category = 'video';
    } else if (lower.contains('doc') || lower.contains('docx') || lower.contains('excel') || lower.contains('word') || lower.contains('ሰነድ') || lower.contains('ዶክመንት')) {
      category = 'document';
    }

    // Extract specific keyword (if any) by removing standard verb and category words
    final stopTokens = {
      'find', 'search', 'show', 'get', 'list', 'check', 'how', 'many', 'count',
      'in', 'on', 'at', 'my', 'the', 'device', 'phone', 'storage', 'files', 'file',
      'pdf', 'mp3', 'photos', 'photo', 'images', 'image', 'videos', 'video', 'music', 'audio',
      'downloaded', 'downloads', 'stored', 'saved', 'are', 'is',
      'ስንት', 'አለ', 'አሉ', 'ያሉ', 'ፋይሎች', 'ፋይል', 'ፈልግ', 'አሳየኝ', 'በስልኬ', 'ውስጥ'
    };

    final words = lower.split(RegExp(r'\s+')).where((w) => w.isNotEmpty && !stopTokens.contains(w)).toList();
    final specificQuery = words.isNotEmpty ? words.join(' ') : null;

    return IntentResult(
      action: ActionType.searchFiles,
      rawQuery: rawQuery,
      targetFileCategory: category,
      targetFileQuery: specificQuery,
      description: 'Searching device files (Category: $category, Query: $specificQuery)',
    );
  }

  IntentResult _resolveAppLaunch(String clean, String rawQuery, List<Map<String, String>> availableApps) {
    final lower = clean.toLowerCase();

    // Check if the user is inquiring about app count or listing all apps
    final isAppMention = lower.contains('app') || lower.contains('application') || lower.contains('አፕ') || lower.contains('መተግበሪያ');
    final isCountOrList = lower.contains('how many') || lower.contains('count') || lower.contains('list') ||
        lower.contains('all') || lower.contains('number') || lower.contains('ስንት') || lower.contains('ምን ያህል') || lower.contains('ዝርዝር');

    if (isAppMention && isCountOrList) {
      return IntentResult(
        action: ActionType.listApps,
        rawQuery: rawQuery,
        description: 'Listing and counting installed applications',
      );
    }

    String? matchedPackage;
    String? matchedName;

    for (final app in availableApps) {
      final name = (app['name'] ?? '').toLowerCase();
      if (name.isNotEmpty && lower.contains(name)) {
        matchedName = app['name'];
        matchedPackage = app['packageName'];
        break;
      }
    }

    return IntentResult(
      action: ActionType.openApp,
      rawQuery: rawQuery,
      targetAppName: matchedName,
      targetAppPackage: matchedPackage,
      description: 'Launching app ${matchedName ?? "requested"}',
    );
  }

  IntentResult _resolveCallContact(String clean, String rawQuery, List<String> availableContacts) {
    String? matchedContact;
    final lower = clean.toLowerCase();

    for (final c in availableContacts) {
      final cLower = c.toLowerCase();
      if (cLower.isNotEmpty && lower.contains(cLower)) {
        matchedContact = c;
        break;
      }
    }

    return IntentResult(
      action: ActionType.call,
      rawQuery: rawQuery,
      targetContact: matchedContact,
      description: 'Calling contact ${matchedContact ?? "requested"}',
    );
  }
}
