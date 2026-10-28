import 'package:flutter_test/flutter_test.dart';
import 'package:amharic_assistant/services/intent_engine.dart';

void main() {
  final testApps = [
    {'name': 'WhatsApp', 'packageName': 'com.whatsapp'},
    {'name': 'Telegram', 'packageName': 'org.telegram.messenger'},
    {'name': 'telebirr', 'packageName': 'cn.tydic.ethiopay'},
    {'name': 'Spotify', 'packageName': 'com.spotify.music'},
    {'name': 'Claude', 'packageName': 'com.anthropic.claude'},
    {'name': 'X', 'packageName': 'com.twitter.android'},
    {'name': 'LinkedIn', 'packageName': 'com.linkedin.android'},
    {'name': 'Gmail', 'packageName': 'com.google.android.gm'},
    {'name': 'YouTube', 'packageName': 'com.google.android.youtube'},
  ];

  final testContacts = ['Mom', 'Hali2', 'ሕጻናት', 'A', 'John'];

  group('IntentEngine Real-World Log Tests', () {
    test('English name with silent letters (ለጆን ደውል -> John)', () {
      final res = IntentEngine.parse(
        'ለጆን ደውል',
        availableApps: testApps,
        availableContacts: testContacts,
      );
      expect(res.action, ActionType.call);
      expect(res.targetContact, 'John');
    });

    test('English name with conversational preposition (ጆን ጋር ደውል -> John)', () {
      final res = IntentEngine.parse(
        'ጆን ጋር ደውል',
        availableApps: testApps,
        availableContacts: testContacts,
      );
      expect(res.action, ActionType.call);
      expect(res.targetContact, 'John');
    });

    test('Casual WhatsApp command in compound sentence', () {
      final res = IntentEngine.parse(
        'ሰላም ነው ራስ እንዴት ነህ እኔ ደህናነኝ እስቲ ዋትስፕ ክፈት አንዴ',
        availableApps: testApps,
        availableContacts: testContacts,
      );
      expect(res.action, ActionType.openApp);
      expect(res.targetAppName, 'WhatsApp');
    });

    test('Spotify launch command', () {
      final res = IntentEngine.parse(
        'ስፖርቲፋይ ክፈት',
        availableApps: testApps,
        availableContacts: testContacts,
      );
      expect(res.action, ActionType.openApp);
      expect(res.targetAppName, 'Spotify');
    });

    test('Telebirr launch without Telegram conflict', () {
      final res = IntentEngine.parse(
        'ቴሌብር ክፈት',
        availableApps: testApps,
        availableContacts: testContacts,
      );
      expect(res.action, ActionType.openApp);
      expect(res.targetAppName, 'telebirr');
    });

    test('Glued X command with particle (ኤክስክፈትስቲ)', () {
      final res = IntentEngine.parse(
        'ኤክስክፈትስቲ',
        availableApps: testApps,
        availableContacts: testContacts,
      );
      expect(res.action, ActionType.openApp);
      expect(res.targetAppName, 'X');
    });

    test('Claude AI launch command', () {
      final res = IntentEngine.parse(
        'ክላውድ ኤአይ ክፈት',
        availableApps: testApps,
        availableContacts: testContacts,
      );
      expect(res.action, ActionType.openApp);
      expect(res.targetAppName, 'Claude');
    });

    test('LinkedIn launch with acoustic concatenation (ሊንክ ዲንክፈት)', () {
      final res = IntentEngine.parse(
        'ሊንክ ዲንክፈት',
        availableApps: testApps,
        availableContacts: testContacts,
      );
      expect(res.action, ActionType.openApp);
      expect(res.targetAppName, 'LinkedIn');
    });

    test('Email launch with phonetic variation (ኢማይል ክፈት)', () {
      final res = IntentEngine.parse(
        'ኢማይል ክፈት',
        availableApps: testApps,
        availableContacts: testContacts,
      );
      expect(res.action, ActionType.openApp);
      expect(res.targetAppName, 'Gmail');
    });

    test('Ge\'ez homophone contact calling (ህጽናት vs ሕጻናት)', () {
      final res = IntentEngine.parse(
        'ሰላም ራስ ለህጽናት ደውል እስቴ',
        availableApps: testApps,
        availableContacts: testContacts,
      );
      expect(res.action, ActionType.call);
      expect(res.targetContact, 'ሕጻናት');
    });

    test('Orphan letter prefix does not falsely trigger single-letter contact A', () {
      final res = IntentEngine.parse(
        'ለጸና አደውል',
        availableApps: testApps,
        availableContacts: testContacts,
      );
      // 'ጸና' is not in testContacts, so it must NOT falsely resolve to contact 'A'
      expect(res.targetContact, isNot('A'));
    });

    test('Amharic PDF search query', () {
      final res = IntentEngine.parse(
        'የወረዱ ፒዲኤፍ ፋይሎችን ፈልግልኝ',
        availableApps: testApps,
        availableContacts: testContacts,
      );
      expect(res.action, ActionType.searchFiles);
      expect(res.targetFileCategory, 'pdf');
    });

    test('English PDF search query', () {
      final res = IntentEngine.parse(
        'Find my downloaded receipt PDF',
        availableApps: testApps,
        availableContacts: testContacts,
      );
      expect(res.action, ActionType.searchFiles);
      expect(res.targetFileCategory, 'pdf');
    });

    test('Amharic photo / image search query', () {
      final res = IntentEngine.parse(
        'ፎቶዎችን አሳየኝ',
        availableApps: testApps,
        availableContacts: testContacts,
      );
      expect(res.action, ActionType.searchFiles);
      expect(res.targetFileCategory, 'image');
    });

    test('Amharic storage status inquiry', () {
      final res = IntentEngine.parse(
        'የስልኬ ማከማቻ ስንት ነው',
        availableApps: testApps,
        availableContacts: testContacts,
      );
      expect(res.action, ActionType.getStorage);
    });

    test('Amharic joke request', () {
      final res = IntentEngine.parse(
        'እስቲ አንድ ቀልድ ንገረኝ',
        availableApps: testApps,
        availableContacts: testContacts,
      );
      expect(res.action, ActionType.joke);
      expect(res.conversationalResponse, isNotNull);
    });

    test('Amharic assistant identity query', () {
      final res = IntentEngine.parse(
        'ማነህ አንተ',
        availableApps: testApps,
        availableContacts: testContacts,
      );
      expect(res.action, ActionType.identity);
      expect(res.conversationalResponse, contains('ራስ'));
    });

    test('Amharic gratitude banter', () {
      final res = IntentEngine.parse(
        'በጣም አመሰግናለሁ',
        availableApps: testApps,
        availableContacts: testContacts,
      );
      expect(res.action, ActionType.banter);
      expect(res.conversationalResponse, isNotNull);
    });

    test('Query "how many pdf files in my phone" must NEVER trigger call to contact Phone1', () {
      final contactsWithPhone = [...testContacts, 'Phone1', 'Miniphone', 'Phone'];
      final res = IntentEngine.parse(
        'how many pdf files in my phone',
        availableApps: testApps,
        availableContacts: contactsWithPhone,
      );
      expect(res.action, ActionType.searchFiles);
      expect(res.targetFileCategory, 'pdf');
      expect(res.action, isNot(ActionType.call));
    });

    test('Amharic query "በስልኬ ውስጥ ስንት pdf አለ" routes to searchFiles and not call', () {
      final contactsWithPhone = [...testContacts, 'Phone1', 'ስልክ'];
      final res = IntentEngine.parse(
        'በስልኬ ውስጥ ስንት pdf አለ',
        availableApps: testApps,
        availableContacts: contactsWithPhone,
      );
      expect(res.action, ActionType.searchFiles);
      expect(res.targetFileCategory, 'pdf');
      expect(res.action, isNot(ActionType.call));
    });

    test('Casual mention of contact name without call verb does NOT call', () {
      final res = IntentEngine.parse(
        'John is arriving today',
        availableApps: testApps,
        availableContacts: testContacts,
      );
      expect(res.action, isNot(ActionType.call));
    });
  });
}
