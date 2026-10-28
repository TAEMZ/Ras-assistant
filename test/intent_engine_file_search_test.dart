import 'package:flutter_test/flutter_test.dart';
import 'package:amharic_assistant/services/intent_engine.dart';

void main() {
  group('File Search & Category Query Tests', () {
    test('"how many pdf files are in device" -> searchFiles, pdf, targetFileQuery null', () {
      final res = IntentEngine.parse('how many pdf files are in device');
      expect(res.action, ActionType.searchFiles);
      expect(res.targetFileCategory, 'pdf');
      expect(res.targetFileQuery, isNull);
    });

    test('"how many pdf files in my phone" -> searchFiles, pdf, targetFileQuery null', () {
      final res = IntentEngine.parse('how many pdf files in my phone');
      expect(res.action, ActionType.searchFiles);
      expect(res.targetFileCategory, 'pdf');
      expect(res.targetFileQuery, isNull);
    });

    test('"find downloaded receipt pdf" -> searchFiles, pdf, targetFileQuery "receipt"', () {
      final res = IntentEngine.parse('find downloaded receipt pdf');
      expect(res.action, ActionType.searchFiles);
      expect(res.targetFileCategory, 'pdf');
      expect(res.targetFileQuery, 'receipt');
    });

    test('"show photos on my phone" -> searchFiles, image, targetFileQuery null', () {
      final res = IntentEngine.parse('show photos on my phone');
      expect(res.action, ActionType.searchFiles);
      expect(res.targetFileCategory, 'image');
      expect(res.targetFileQuery, isNull);
    });

    test('Amharic: "በስልኬ ውስጥ ስንት የፒዲኤፍ ፋይሎች አሉ" -> searchFiles, pdf, targetFileQuery null', () {
      final res = IntentEngine.parse('በስልኬ ውስጥ ስንት የፒዲኤፍ ፋይሎች አሉ');
      expect(res.action, ActionType.searchFiles);
      expect(res.targetFileCategory, 'pdf');
      expect(res.targetFileQuery, isNull);
    });
  });
}
