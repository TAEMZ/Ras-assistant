import 'mcp_tool_service.dart';

enum ActionType {
  greeting,
  call,
  openDialer,
  flashlightOn,
  flashlightOff,
  openContacts,
  openCamera,
  openWifi,
  openBluetooth,
  openSoundSettings,
  getBattery,
  getStorage,
  searchFiles,
  openFile,
  openApp,
  listApps,
  mcpTool,
  joke,
  banter,
  identity,
  none,
}

class IntentResult {
  final ActionType action;
  final String? targetContact;
  final String? targetAppName;
  final String? targetAppPackage;
  final String? targetFileQuery;
  final String? targetFileCategory; // 'pdf', 'image', 'audio', 'video', 'document', 'all'
  final String? targetFilePath;
  final String? conversationalResponse;
  final McpToolExecutionResult? mcpResult;
  final String rawQuery;
  final String description;

  const IntentResult({
    required this.action,
    this.targetContact,
    this.targetAppName,
    this.targetAppPackage,
    this.targetFileQuery,
    this.targetFileCategory,
    this.targetFilePath,
    this.conversationalResponse,
    this.mcpResult,
    required this.rawQuery,
    required this.description,
  });
}

class IntentEngine {
  static final List<String> _amharicJokes = [
    "አንድ ሰውዬ ዶክተር ጋር ሄዶ 'ዶክተር ሆዴን ሲነኩት ያመኛል፣ እግሬንም ሲነኩት ያመኛል፣ ጭንቅላቴንም ሲነኩት ያመኛል ምን ሆኜ ነው?' ቢለው... ዶክተሩ መርምሮ 'ጣቶችህ ተሰብረዋል!' አለው ይባላል! 😄",
    "አንድ ተማሪ ፈተና ላይ 'የአባይ ወንዝ የየት ይገኛል?' ተብሎ ሲጠየቅ... 'ቴሌቪዥን ላይ ዜና ሲነበብ' ብሎ ጻፈ! 😂",
    "አባት ልጁን 'ለምንድነው ሁልጊዜ ከመጨረሻ አንደኛ የምትወጣው?' ቢለው... ልጁም 'አባዬ አንድ ሰው እኮ መጨረሻ መሆን አለበት፣ እኔ ደግሞ ለጓደኞቼ መስዋዕት እየሆንኩ ነው!' አለው! 🤣",
    "አንድ ሰውዬ ሱቅ ገብቶ 'ስኳር አለ?' አለ። ሱቅ ነጋሪው 'አዎ አለ' አለው። 'እንግዲያው ሻይ ስራና ጠጣ' ብሎት እርፍ! 😆",
  ];

  static final List<String> _englishJokes = [
    "Why don't scientists trust atoms? Because they make up everything! 😄",
    "Why did the smartphone go to school? Because it wanted to be a smart device! 😂",
    "I told my computer I needed a break... now it won't stop sending me Kit-Kats! 🤣",
    "Parallel lines have so much in common. It's a shame they'll never meet! 😆",
  ];

  static const Map<String, List<String>> _relationshipAliases = {
    'እማዬ': ['mom', 'mother', 'mama', 'እማ', 'እማዬ', 'እናት'],
    'እናት': ['mother', 'mom', 'እናት', 'እማዬ'],
    'እማ': ['mom', 'mother', 'እማ', 'እማዬ'],
    'ማሚ': ['mom', 'mother', 'mama'],
    'ማም': ['mom', 'mother', 'mama', 'እማ', 'እናት'],
    'አባዬ': ['dad', 'father', 'papa', 'አባ', 'አባዬ', 'አባት'],
    'አባት': ['father', 'dad', 'አባት', 'አባዬ'],
    'አባ': ['dad', 'father', 'አባ', 'አባዬ'],
    'ባባ': ['dad', 'father', 'papa'],
    'ወንድሜ': ['brother', 'bro', 'ወንድም', 'ወንድሜ'],
    'ወንድም': ['brother', 'bro', 'ወንድም'],
    'እህቴ': ['sister', 'sis', 'እህት', 'እህቴ'],
    'እህት': ['sister', 'sis', 'እህት'],
    'ሚስቴ': ['wife', 'ሚስት', 'ሚስቴ'],
    'ባሌ': ['husband', 'ባል', 'ባሌ'],
    'ጓደኛዬ': ['friend', 'ጓደኛ'],
  };

  static const Map<String, List<String>> _appAliases = {
    // Telecom & Banking
    'ቴሌብር': ['telebirr', 'cn.tydic.ethiopay', 'ethiopay'],
    'ቴሌ ብር': ['telebirr', 'cn.tydic.ethiopay', 'ethiopay'],
    // Messaging & Social
    'ቴሌግራም': ['telegram', 'org.telegram.messenger'],
    'ዋትስፕ': ['whatsapp', 'com.whatsapp'],
    'ዋትሳፕ': ['whatsapp', 'com.whatsapp'],
    'ዋትስአፕ': ['whatsapp', 'com.whatsapp'],
    'ዋትስ አፕ': ['whatsapp', 'com.whatsapp'],
    'ዋት ሳፕ': ['whatsapp', 'com.whatsapp'],
    'ዩቲዩብ': ['youtube', 'com.google.android.youtube'],
    'ዩትዩብ': ['youtube', 'com.google.android.youtube'],
    'ቲክቶክ': ['tiktok', 'com.zhiliaoapp.musically'],
    'ፌስቡክ': ['facebook', 'com.facebook.katana'],
    'ኢንስታግራም': ['instagram', 'com.instagram.android'],
    'ኤክስ': ['x', 'twitter', 'com.twitter.android'],
    'ትዊተር': ['x', 'twitter', 'com.twitter.android'],
    'ቲውተር': ['x', 'twitter', 'com.twitter.android'],
    'ቲዊተር': ['x', 'twitter', 'com.twitter.android'],
    'ሊንክዲን': ['linkedin', 'com.linkedin.android'],
    'ሊንክድኢን': ['linkedin', 'com.linkedin.android'],
    'ሊንክድ ኢን': ['linkedin', 'com.linkedin.android'],
    'ሊንክ ዲን': ['linkedin', 'com.linkedin.android'],
    // AI & Web
    'ክላውድ': ['claude', 'com.anthropic.claude'],
    'ክላውድ ኤአይ': ['claude', 'com.anthropic.claude'],
    'ቻትጂፒቲ': ['chatgpt', 'openai', 'com.openai.chatgpt'],
    'ክሮም': ['chrome', 'browser', 'com.android.chrome'],
    // Media & System
    'ስፖርቲፋይ': ['spotify', 'com.spotify.music'],
    'ሙዚቃ': ['music', 'spotify', 'audio'],
    'ጂሜይል': ['gmail', 'mail', 'com.google.android.gm'],
    'ኢሜይል': ['email', 'gmail', 'mail'],
    'ኢማይል': ['email', 'gmail', 'mail'],
    'ሜል': ['email', 'gmail', 'mail'],
    'ጋለሪ': ['gallery', 'photos', 'com.sec.android.gallery3d'],
    'ፎቶዎች': ['gallery', 'photos', 'com.google.android.apps.photos'],
    'ቅንብር': ['settings', 'com.android.settings'],
    'ሴቲንግ': ['settings', 'com.android.settings'],
    'መልእክት': ['message', 'messages', 'com.google.android.apps.messaging'],
    'ሜሴጅ': ['message', 'messages'],
    'ፋይል': ['files', 'my files', 'com.sec.android.app.myfiles'],
    'ካሌንደር': ['calendar', 'com.google.android.calendar'],
    'ቀን መቁጠሪያ': ['calendar'],
    'ካልኩሌተር': ['calculator', 'calc'],
    'ሒሳብ': ['calculator', 'calc'],
    'ካርታ': ['maps', 'map', 'com.google.android.apps.maps'],
    'ሰዓት': ['clock', 'alarm', 'com.sec.android.app.clockpackage', 'com.google.android.deskclock'],
    'ማስታወሻ': ['notes', 'keep', 'memo', 'com.google.android.keep'],
  };

  /// Amharic homophone canonicalization (ሀ/ሐ/ኀ -> ሀ, ሠ -> ሰ, ዐ -> አ, ፀ -> ጸ)
  static String normalizeGeez(String input) {
    final buffer = StringBuffer();
    for (int i = 0; i < input.length; i++) {
      final ch = input[i];
      // ሐ/ኀ series to ሀ
      if (ch == 'ሐ' || ch == 'ኀ') {
        buffer.write('ሀ');
      } else if (ch == 'ሑ' || ch == 'ኁ') {
        buffer.write('ሁ');
      } else if (ch == 'ሒ' || ch == 'ኂ') {
        buffer.write('ሂ');
      } else if (ch == 'ሓ' || ch == 'ኃ') {
        buffer.write('ሃ');
      } else if (ch == 'ሔ' || ch == 'ኄ') {
        buffer.write('ሄ');
      } else if (ch == 'ሕ' || ch == 'ኅ') {
        buffer.write('ህ');
      } else if (ch == 'ሖ' || ch == 'ኆ') {
        buffer.write('ሆ');
      }
      // ሠ series to ሰ
      else if (ch == 'ሠ') {
        buffer.write('ሰ');
      } else if (ch == 'ሡ') {
        buffer.write('ሱ');
      } else if (ch == 'ሢ') {
        buffer.write('ሲ');
      } else if (ch == 'ሣ') {
        buffer.write('ሳ');
      } else if (ch == 'ሤ') {
        buffer.write('ሴ');
      } else if (ch == 'ሥ') {
        buffer.write('ስ');
      } else if (ch == 'ሦ') {
        buffer.write('ሶ');
      }
      // ዐ series to አ
      else if (ch == 'ዐ') {
        buffer.write('አ');
      } else if (ch == 'ዑ') {
        buffer.write('ኡ');
      } else if (ch == 'ዒ') {
        buffer.write('ኢ');
      } else if (ch == 'ዓ') {
        buffer.write('ኣ');
      } else if (ch == 'ዔ') {
        buffer.write('ኤ');
      } else if (ch == 'ዕ') {
        buffer.write('እ');
      } else if (ch == 'ዖ') {
        buffer.write('ኦ');
      }
      // ፀ series to ጸ
      else if (ch == 'ፀ') {
        buffer.write('ጸ');
      } else if (ch == 'ፁ') {
        buffer.write('ጹ');
      } else if (ch == 'ፂ') {
        buffer.write('ጺ');
      } else if (ch == 'ፃ') {
        buffer.write('ጻ');
      } else if (ch == 'ፄ') {
        buffer.write('ጼ');
      } else if (ch == 'ፅ') {
        buffer.write('ጽ');
      } else if (ch == 'ፆ') {
        buffer.write('ጾ');
      } else {
        buffer.write(ch);
      }
    }
    return buffer.toString();
  }

  /// Inserts spaces around glued action verbs and conversational particles
  /// produced when the speaker talks quickly without pause.
  static String segmentAcousticConcatenations(String input) {
    String text = input;
    final gluedVerbs = [
      'ክፈተው', 'ክፈቺ', 'ክፈት', 'አብራው', 'አብሪው', 'አብራ', 'አጥፋው', 'አጥፈው', 'አጥፊው', 'አጥፋ',
      'ደውልልኝ', 'ደውይልኝ', 'ደውልላት', 'ደውልለት', 'ደውሉልኝ', 'ደውል', 'ደውይ', 'ደዉል',
      'አደውል', 'አደውይ', 'ጥራልኝ', 'ጥሪልኝ', 'ጥራው', 'ጥራ', 'ጥሪ',
    ];
    for (final v in gluedVerbs) {
      if (text.contains(v)) {
        text = text.replaceAll(v, ' $v ');
      }
    }

    final gluedParticles = [
      'እስቲ', 'ስቲ', 'እስኪ', 'ስኪ', 'አንዴ', 'በናትህ', 'በናትሽ', 'እባክህ', 'እባክሽ',
    ];
    for (final p in gluedParticles) {
      if (text.contains(p)) {
        text = text.replaceAll(p, ' $p ');
      }
    }
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static const Map<String, String> _fidelPhoneticMap = {
    // ሀ series
    'ሀ': 'ha', 'ሁ': 'hu', 'ሂ': 'hi', 'ሃ': 'ha', 'ሄ': 'he', 'ህ': 'h', 'ሆ': 'ho',
    'ለ': 'le', 'ሉ': 'lu', 'ሊ': 'li', 'ላ': 'la', 'ሌ': 'le', 'ል': 'l', 'ሎ': 'lo',
    'ሐ': 'ha', 'ሑ': 'hu', 'ሒ': 'hi', 'ሓ': 'ha', 'ሔ': 'he', 'ሕ': 'h', 'ሖ': 'ho',
    'መ': 'me', 'ሙ': 'mu', 'ሚ': 'mi', 'ማ': 'ma', 'ሜ': 'me', 'ም': 'm', 'ሞ': 'mo',
    'ሠ': 'se', 'ሡ': 'su', 'ሢ': 'si', 'ሣ': 'sa', 'ሤ': 'se', 'ሥ': 's', 'ሦ': 'so',
    'ረ': 're', 'ሩ': 'ru', 'ሪ': 'ri', 'ራ': 'ra', 'ሬ': 're', 'ር': 'r', 'ሮ': 'ro',
    'ሰ': 'se', 'ሱ': 'su', 'ሲ': 'si', 'ሳ': 'sa', 'ሴ': 'se', 'ስ': 's', 'ሶ': 'so',
    'ሸ': 'she', 'ሹ': 'shu', 'ሺ': 'shi', 'ሻ': 'sha', 'ሼ': 'she', 'ሽ': 'sh', 'ሾ': 'sho',
    'ቀ': 'ke', 'ቁ': 'ku', 'ቂ': 'ki', 'ቃ': 'ka', 'ቄ': 'ke', 'ቅ': 'k', 'ቆ': 'ko',
    'በ': 'be', 'ቡ': 'bu', 'ቢ': 'bi', 'ባ': 'ba', 'ቤ': 'be', 'ብ': 'b', 'ቦ': 'bo',
    'ተ': 'te', 'ቱ': 'tu', 'ቲ': 'ti', 'ታ': 'ta', 'ቴ': 'te', 'ት': 't', 'ቶ': 'to',
    'ቸ': 'che', 'ቹ': 'chu', 'ቺ': 'chi', 'ቻ': 'cha', 'ቼ': 'che', 'ች': 'ch', 'ቾ': 'cho',
    'ነ': 'ne', 'ኑ': 'nu', 'ኒ': 'ni', 'ና': 'na', 'ኔ': 'ne', 'ን': 'n', 'ኖ': 'no',
    'ኘ': 'nye', 'ኙ': 'nyu', 'ኚ': 'nyi', 'ኛ': 'nya', 'ኜ': 'nye', 'ኝ': 'ny', 'ኞ': 'nyo',
    'አ': 'a', 'ኡ': 'u', 'ኢ': 'i', 'ኣ': 'a', 'ኤ': 'e', 'እ': 'e', 'ኦ': 'o',
    'ከ': 'ke', 'ኩ': 'ku', 'ኪ': 'ki', 'ካ': 'ka', 'ኬ': 'ke', 'ክ': 'k', 'ኮ': 'ko',
    'ኸ': 'he', 'ኹ': 'hu', 'ኺ': 'hi', 'ኻ': 'ha', 'ኼ': 'he', 'ኽ': 'h', 'ኾ': 'ho',
    'ወ': 'we', 'ዉ': 'wu', 'ዊ': 'wi', 'ዋ': 'wa', 'ዌ': 'we', 'ው': 'w', 'ዎ': 'wo',
    'ዐ': 'a', 'ዑ': 'u', 'ዒ': 'i', 'ዓ': 'a', 'ዔ': 'e', 'ዕ': 'e', 'ዖ': 'o',
    'ዘ': 'ze', 'ዙ': 'zu', 'ዚ': 'zi', 'ዛ': 'za', 'ዜ': 'ze', 'ዝ': 'z', 'ዞ': 'zo',
    'ዠ': 'zhe', 'ዡ': 'zhu', 'ዢ': 'zhi', 'ዣ': 'zha', 'ዤ': 'zhe', 'ዥ': 'zh', 'ዦ': 'zho',
    'የ': 'ye', 'ዩ': 'yu', 'ዪ': 'yi', 'ያ': 'ya', 'ዬ': 'ye', 'ይ': 'y', 'ዮ': 'yo',
    'ደ': 'de', 'ዱ': 'du', 'ዲ': 'di', 'ዳ': 'da', 'ዴ': 'de', 'ድ': 'd', 'ዶ': 'do',
    'ጀ': 'je', 'ጁ': 'ju', 'ጂ': 'ji', 'ጃ': 'ja', 'ጄ': 'je', 'ጅ': 'j', 'ጆ': 'jo',
    'ገ': 'ge', 'ጉ': 'gu', 'ጊ': 'gi', 'ጋ': 'ga', 'ጌ': 'ge', 'ግ': 'g', 'ጎ': 'go',
    'ጠ': 'te', 'ጡ': 'tu', 'ጢ': 'ti', 'ጣ': 'ta', 'ጤ': 'te', 'ጥ': 't', 'ጦ': 'to',
    'ጨ': 'che', 'ጩ': 'chu', 'ጪ': 'chi', 'ጫ': 'cha', 'ጬ': 'che', 'ጭ': 'ch', 'ጮ': 'cho',
    'ጰ': 'pe', 'ጱ': 'pu', 'ጲ': 'pi', 'ጳ': 'pa', 'ጴ': 'pe', 'ጵ': 'p', 'ጶ': 'po',
    'ጸ': 'tse', 'ጹ': 'tsu', 'ጺ': 'tsi', 'ጻ': 'tsa', 'ጼ': 'tse', 'ጽ': 'ts', 'ጾ': 'tso',
    'ፈ': 'fe', 'ፉ': 'fu', 'ፊ': 'fi', 'ፋ': 'fa', 'ፌ': 'fe', 'ፍ': 'f', 'ፎ': 'fo',
    'ፐ': 'pe', 'ፑ': 'pu', 'ፒ': 'pi', 'ፓ': 'pa', 'ፔ': 'pe', 'ፕ': 'p', 'ፖ': 'po',
    // Labiovelars
    'ቋ': 'kwa', 'ሗ': 'hwa', 'ጓ': 'gwa', 'ኋ': 'hwa', 'ጧ': 'twa', 'ሟ': 'mwa',
    'ሷ': 'swa', 'ሯ': 'rwa', 'ቧ': 'bwa', 'ቷ': 'twa', 'ቿ': 'chwa', 'ኗ': 'nwa',
    'ኟ': 'nywa', 'ዟ': 'zwa', 'ዧ': 'zhwa', 'ዷ': 'dwa', 'ጇ': 'jwa', 'ጷ': 'pwa',
    'ጿ': 'tswa', 'ፏ': 'fwa',
  };

  static String transliterateFidelToLatin(String input) {
    final buffer = StringBuffer();
    for (int i = 0; i < input.length; i++) {
      final char = input[i];
      if (_fidelPhoneticMap.containsKey(char)) {
        buffer.write(_fidelPhoneticMap[char]);
      } else {
        buffer.write(char.toLowerCase());
      }
    }
    return buffer.toString().trim();
  }

  static IntentResult parse(
    String query, {
    List<String> availableContacts = const [],
    List<Map<String, String>> availableApps = const [],
  }) {
    final segmented = segmentAcousticConcatenations(query.trim().toLowerCase());
    final clean = normalizeGeez(segmented);
    if (clean.isEmpty) {
      return IntentResult(
        action: ActionType.none,
        rawQuery: query,
        description: 'No input detected',
      );
    }

    // 0. Conversational Greeting & Assistant Wake Phrases
    if (_isGreeting(clean)) {
      return IntentResult(
        action: ActionType.greeting,
        rawQuery: query,
        description: 'ሰላም! ምን ልርዳዎት?',
      );
    }

    // 1. Flashlight Off
    final hasLightTarget = clean.contains('መብራት') ||
        clean.contains('መብራቱን') ||
        clean.contains('ፍላሽ') ||
        clean.contains('ላይት') ||
        clean.contains('ቶርች') ||
        clean.contains('flash') ||
        clean.contains('torch');

    final hasOffVerb = clean.contains('አጥፋ') ||
        clean.contains('አጥፋው') ||
        clean.contains('አጥፈው') ||
        clean.contains('አጥፊ') ||
        clean.contains('አጥፊው') ||
        clean.contains('አጥፉ') ||
        clean.contains('አጥፉት') ||
        clean.contains('ዝጋ') ||
        clean.contains('ዝጋው') ||
        clean.contains('off');

    if (hasLightTarget && hasOffVerb) {
      return IntentResult(
        action: ActionType.flashlightOff,
        rawQuery: query,
        description: 'Flashlight deactivated',
      );
    }

    // 2. Flashlight On
    final hasOnVerb = clean.contains('አብራ') ||
        clean.contains('አብራው') ||
        clean.contains('አብረው') ||
        clean.contains('አብሪ') ||
        clean.contains('አብሪው') ||
        clean.contains('አብሩ') ||
        clean.contains('አብሩት') ||
        clean.contains('ክፈት') ||
        clean.contains('ክፈተው') ||
        clean.contains('on');

    if (hasLightTarget && hasOnVerb) {
      return IntentResult(
        action: ActionType.flashlightOn,
        rawQuery: query,
        description: 'Flashlight activated',
      );
    }

    // 3. Wi-Fi Control
    if (clean.contains('ዋይፋይ') ||
        clean.contains('ዋይ ፋይ') ||
        clean.contains('wifi') ||
        clean.contains('wi-fi')) {
      return IntentResult(
        action: ActionType.openWifi,
        rawQuery: query,
        description: 'Opening Wi-Fi settings',
      );
    }

    // 4. Bluetooth Control
    if (clean.contains('ብሉቱዝ') || clean.contains('bluetooth')) {
      return IntentResult(
        action: ActionType.openBluetooth,
        rawQuery: query,
        description: 'Opening Bluetooth settings',
      );
    }

    // 5. Camera Control
    if (clean.contains('ካሜራ') ||
        clean.contains('camera') ||
        clean.contains('ፎቶ አንሳ') ||
        clean.contains('ፎቶ ማንሻ') ||
        clean.contains('ፎቶ ላንሳ') ||
        clean.contains('ፎቶ ልነሳ') ||
        clean.contains('take photo') ||
        clean.contains('take picture')) {
      return IntentResult(
        action: ActionType.openCamera,
        rawQuery: query,
        description: 'Launching Camera',
      );
    }

    // 6. Battery Information
    if (clean.contains('ባትሪ') ||
        clean.contains('ባትሪው') ||
        clean.contains('ቻርጅ') ||
        clean.contains('ቻርጁ') ||
        clean.contains('battery')) {
      return IntentResult(
        action: ActionType.getBattery,
        rawQuery: query,
        description: 'Checking battery level',
      );
    }

    // 6b. Storage Diagnostics
    if (clean.contains('ስቶሬጅ') ||
        clean.contains('ማከማቻ') ||
        clean.contains('ሜሞሪ') ||
        clean.contains('ቦታ') ||
        clean.contains('storage') ||
        clean.contains('free space') ||
        clean.contains('memory') ||
        clean.contains('disk space')) {
      return IntentResult(
        action: ActionType.getStorage,
        rawQuery: query,
        description: 'Checking device storage diagnostics',
      );
    }

    // 6c. Jokes & Humor
    if (clean.contains('ቀልድ') ||
        clean.contains('ቀልዶች') ||
        clean.contains('አስቀኝ') ||
        clean.contains('አስቂኝ') ||
        clean.contains('joke') ||
        clean.contains('jokes') ||
        clean.contains('make me laugh') ||
        clean.contains('funny')) {
      final isEnglish = !RegExp(r'[\u1200-\u137F]').hasMatch(query);
      final jokes = isEnglish ? _englishJokes : _amharicJokes;
      final selectedJoke = (List.from(jokes)..shuffle()).first;
      return IntentResult(
        action: ActionType.joke,
        rawQuery: query,
        conversationalResponse: selectedJoke,
        description: selectedJoke,
      );
    }

    // 6d. Identity & Capabilities
    if (clean.contains('ማነህ') ||
        clean.contains('ማነሽ') ||
        clean.contains('ስምህ ማን') ||
        clean.contains('ስምሽ ማን') ||
        clean.contains('ምን ትችላለህ') ||
        clean.contains('ምን መስራት') ||
        clean.contains('who are you') ||
        clean.contains('what can you do') ||
        clean.contains('what are you')) {
      final isEnglish = !RegExp(r'[\u1200-\u137F]').hasMatch(query);
      final resp = isEnglish
          ? 'I am Ras, your intelligent offline phone assistant. I can search files, launch apps, call contacts, and check storage.'
          : 'እኔ ራስ ነኝ፤ በስልክዎ ውስጥ ያሉ ፋይሎችን፣ አፖችን እና እውቂያዎችን ከመስመር ውጭ በፈጣን ሁኔታ የሚያከናውን ብልህ ረዳትዎ!';
      return IntentResult(
        action: ActionType.identity,
        rawQuery: query,
        conversationalResponse: resp,
        description: resp,
      );
    }

    // 6e. Gratitude & Banter
    if (clean.contains('አመሰግናለሁ') ||
        clean.contains('ቴንክስ') ||
        clean.contains('እናመሰግናለን') ||
        clean.contains('ጎበዝ') ||
        clean.contains('አሪፍ') ||
        clean.contains('ደስ ይላል') ||
        clean.contains('thank you') ||
        clean.contains('thanks') ||
        clean.contains('great job') ||
        clean.contains('awesome')) {
      final isEnglish = !RegExp(r'[\u1200-\u137F]').hasMatch(query);
      final resp = isEnglish
          ? 'You are very welcome! Always here to assist you.'
          : 'ምንም አይደል! በደስታ ነው፤ ሌላ የምረዳዎት ነገር አለ?';
      return IntentResult(
        action: ActionType.banter,
        rawQuery: query,
        conversationalResponse: resp,
        description: resp,
      );
    }

    // 6f. Deep Phone File & Media Search
    final hasFileKeyword = clean.contains('ፋይል') ||
        clean.contains('ፋይሎች') ||
        clean.contains('የወረዱ') ||
        clean.contains('ወረዱ') ||
        clean.contains('ዳውንሎድ') ||
        clean.contains('ፒዲኤፍ') ||
        clean.contains('ሰነድ') ||
        clean.contains('ሰነዶች') ||
        clean.contains('ዶክመንት') ||
        clean.contains('ፎቶ') ||
        clean.contains('ምስል') ||
        clean.contains('ምስሎች') ||
        clean.contains('ሙዚቃ') ||
        clean.contains('ድምጽ') ||
        clean.contains('ቪዲዮ') ||
        clean.contains('ቪድዮ') ||
        clean.contains('file') ||
        clean.contains('files') ||
        clean.contains('download') ||
        clean.contains('downloads') ||
        clean.contains('pdf') ||
        clean.contains('document') ||
        clean.contains('documents') ||
        clean.contains('photo') ||
        clean.contains('photos') ||
        clean.contains('image') ||
        clean.contains('images') ||
        clean.contains('video') ||
        clean.contains('audio');

    final hasSearchVerb = clean.contains('ፈልግ') ||
        clean.contains('ፈልጊ') ||
        clean.contains('ፈልግልኝ') ||
        clean.contains('ፈልጊልኝ') ||
        clean.contains('አሳየኝ') ||
        clean.contains('አውጣ') ||
        clean.contains('አውጣልኝ') ||
        clean.contains('የት አለ') ||
        clean.contains('የት አሉ') ||
        clean.contains('ስንት') ||
        clean.contains('ያሉ') ||
        clean.contains('ያሉትን') ||
        clean.contains('አለ') ||
        clean.contains('አሉ') ||
        clean.contains('find') ||
        clean.contains('search') ||
        clean.contains('show') ||
        clean.contains('look for') ||
        clean.contains('where') ||
        clean.contains('how many') ||
        clean.contains('count') ||
        clean.contains('list') ||
        clean.contains('check');

    if (hasFileKeyword && (hasSearchVerb || clean.contains('የወረዱ') || clean.contains('downloads') || clean.contains('pdf') || clean.contains('ፒዲኤፍ') || clean.contains('ፋይል'))) {
      String category = 'all';
      if (clean.contains('ፒዲኤፍ') || clean.contains('pdf')) {
        category = 'pdf';
      } else if (clean.contains('ፎቶ') || clean.contains('ምስል') || clean.contains('photo') || clean.contains('image')) {
        category = 'image';
      } else if (clean.contains('ሙዚቃ') || clean.contains('ድምጽ') || clean.contains('music') || clean.contains('audio')) {
        category = 'audio';
      } else if (clean.contains('ቪዲዮ') || clean.contains('ቪድዮ') || clean.contains('video')) {
        category = 'video';
      } else if (clean.contains('ዶክመንት') || clean.contains('ሰነድ') || clean.contains('document')) {
        category = 'document';
      }

      String fileQuery = clean;

      // 1. Strip multi-word container phrases (longest first to avoid fragmentation)
      final multiWordPhrases = [
        'in my device', 'on my device', 'in my phone', 'on my phone',
        'in device', 'on device', 'my device', 'my phone',
        'are in device', 'are in', 'are on', 'is in', 'is on',
        'show me', 'where is', 'where are', 'how many', 'look for',
      ];
      multiWordPhrases.sort((a, b) => b.length.compareTo(a.length));
      for (final phrase in multiWordPhrases) {
        fileQuery = fileQuery.replaceAll(phrase, ' ');
      }

      // 2. Strip Amharic stop words, keywords, and orphaned genitive prefixes
      final amharicStopWords = [
        'የወረዱ', 'የተቀመጡ', 'የተላኩ', 'ፋይሎች', 'ፋይል', 'ዶክመንት', 'ሰነድ', 'ሰነዶች',
        'ፈልግልኝ', 'ፈልጊልኝ', 'ፈልግ', 'ፈልጊ', 'አሳየኝ', 'አውጣልኝ', 'አውጣ', 'የት አሉ', 'የት አለ',
        'ስንት', 'አለ', 'አሉ', 'ያሉትን', 'ያሉ', 'ያለ', 'የሚገኙ', 'በስልኬ', 'በስልኩ', 'ስልኬ', 'ውስጥ',
        'በመሳሪያው', 'መሳሪያው', 'ፎቶዎች', 'ፎቶ', 'ምስሎች', 'ምስል', 'ፒዲኤፍ', 'ሙዚቃ', 'ቪዲዮ', 'ቪድዮ',
        'የ' // remove orphaned genitive prefix (e.g. from የፒዲኤፍ)
      ];
      amharicStopWords.sort((a, b) => b.length.compareTo(a.length));
      for (final sw in amharicStopWords) {
        fileQuery = fileQuery.replaceAll(sw, ' ');
      }

      // 3. Filter standalone single words via exact token matching (avoids fragmenting words like "phone")
      final singleEnglishStopWords = {
        'find', 'search', 'show', 'where', 'count', 'list', 'check',
        'are', 'is', 'in', 'on', 'at', 'to', 'for', 'from', 'with',
        'device', 'phone', 'storage', 'saved', 'stored',
        'my', 'the', 'a', 'an', 'downloaded', 'files', 'file',
        'pdf', 'photos', 'photo', 'images', 'image', 'videos', 'video', 'music', 'audio', 'all'
      };
      final tokens = fileQuery
          .split(RegExp(r'\s+'))
          .where((t) => t.isNotEmpty && !singleEnglishStopWords.contains(t.toLowerCase()))
          .toList();
      fileQuery = tokens.join(' ').trim();

      return IntentResult(
        action: ActionType.searchFiles,
        rawQuery: query,
        targetFileQuery: fileQuery.isNotEmpty ? fileQuery : null,
        targetFileCategory: category,
        description: 'Searching phone files ($category)',
      );
    }

    // 7. Sound / Silent / Volume Settings
    if (clean.contains('ድምፅ') ||
        clean.contains('ድምጽ') ||
        clean.contains('ዝም በል') ||
        clean.contains('ሳይለንት') ||
        clean.contains('volume') ||
        clean.contains('sound')) {
      return IntentResult(
        action: ActionType.openSoundSettings,
        rawQuery: query,
        description: 'Accessing sound & volume settings',
      );
    }

    // 8. Open Contacts Directory
    if (clean.contains('ኮንታክት ክፈት') ||
        clean.contains('ኮንታክት አሳየኝ') ||
        clean.contains('ስልክ ማውጫ') ||
        clean.contains('እውቂያዎች') ||
        clean.contains('open contacts')) {
      return IntentResult(
        action: ActionType.openContacts,
        rawQuery: query,
        description: 'Accessing contact directory',
      );
    }

    // 9. Call / Direct Dialing (Strict Call Verb Gating)
    final callKeywords = [
      'ደውልልኝ', 'ደውይልኝ', 'ደውልላት', 'ደውልለት', 'ደውሉልኝ', 'ደውሉ',
      'ደውል', 'ደውይ', 'ደዉል', 'መደወል', 'ልደውል', 'ልትደውል', 'ልትደውዪ',
      'አደውል', 'አደውይ', 'እንዲደውል', 'እንድትደውል',
      'ስልክ ምታ', 'ስልክ ደውል', 'ስልክ ደውይ', 'ስልክ አገናኘኝ',
      'አገናኘኝ', 'አገናኚኝ', 'አገናኘው', 'አገናኝ',
      'ጥራልኝ', 'ጥሪልኝ', 'ጥራው', 'ጥራ', 'ጥሪ',
      'call', 'dial', 'ring',
    ];

    bool hasCallIntent = false;
    for (final verb in callKeywords) {
      if (clean.contains(verb)) {
        hasCallIntent = true;
        break;
      }
    }

    String? identifiedContact;
    if (hasCallIntent && availableContacts.isNotEmpty) {
      identifiedContact = _findBestContactInQuery(clean, availableContacts);
    }

    if (hasCallIntent) {
      if (identifiedContact != null && identifiedContact.isNotEmpty) {
        return IntentResult(
          action: ActionType.call,
          targetContact: identifiedContact,
          rawQuery: query,
          description: 'Initiating direct call to $identifiedContact',
        );
      } else {
        return IntentResult(
          action: ActionType.openDialer,
          rawQuery: query,
          description: 'Opening dialer',
        );
      }
    }

    // 10. Open Installed Application (Safe Gated Matcher)
    if (availableApps.isNotEmpty) {
      final appMatch = _matchInstalledApp(clean, availableApps);
      if (appMatch != null) {
        return IntentResult(
          action: ActionType.openApp,
          targetAppName: appMatch['name'],
          targetAppPackage: appMatch['packageName'],
          rawQuery: query,
          description: 'Launching ${appMatch['name']}',
        );
      }
    }

    return IntentResult(
      action: ActionType.none,
      rawQuery: query,
      description: 'Command unrecognized',
    );
  }

  /// Searches the entire query for any contact name, alias, or inflected form
  static String? _findBestContactInQuery(
    String cleanQuery,
    List<String> availableContacts,
  ) {
    if (availableContacts.isEmpty) return null;

    final queryLatin = transliterateFidelToLatin(cleanQuery).toLowerCase();
    String? bestContact;
    int longestMatchLength = 0;

    // 1. Direct Entity Grounding across all contacts
    for (final contact in availableContacts) {
      final contactClean = contact.trim();
      final contactLower = normalizeGeez(contactClean.toLowerCase());
      if (contactLower.isEmpty) continue;

      // Check relationship aliases (e.g. query has "እማዬ" and contact is "Mom")
      for (final entry in _relationshipAliases.entries) {
        final keyNorm = normalizeGeez(entry.key);
        if (cleanQuery.contains(keyNorm)) {
          for (final alias in entry.value) {
            if (contactLower.contains(normalizeGeez(alias.toLowerCase()))) {
              if (alias.length + 10 > longestMatchLength) {
                longestMatchLength = alias.length + 10;
                bestContact = contactClean;
              }
            }
          }
        }
      }

      // Check if contact's normalized Ge'ez name is directly inside cleanQuery
      if (contactLower.length >= 2 && cleanQuery.contains(contactLower)) {
        if (contactLower.length > longestMatchLength) {
          longestMatchLength = contactLower.length;
          bestContact = contactClean;
        }
      }

      // Check if contact's Latin tokens exist in queryLatin
      final contactLatin = transliterateFidelToLatin(contactClean).toLowerCase();
      final contactPhonetic = _phoneticNormalize(contactLatin);
      final queryPhonetic = _phoneticNormalize(queryLatin);

      // Check phonetic match (e.g. "jon" vs "john")
      if (contactPhonetic.length >= 3 && queryPhonetic.contains(contactPhonetic)) {
        if (contactPhonetic.length > longestMatchLength) {
          longestMatchLength = contactPhonetic.length;
          bestContact = contactClean;
        }
      }

      final tokens = contactLatin.split(RegExp(r'\s+'));
      for (final token in tokens) {
        final tokenPhonetic = _phoneticNormalize(token);
        if (tokenPhonetic.length >= 3 && queryPhonetic.contains(tokenPhonetic)) {
          if (tokenPhonetic.length > longestMatchLength) {
            longestMatchLength = tokenPhonetic.length;
            bestContact = contactClean;
          }
        }

        if (token.length >= 3 && queryLatin.contains(token)) {
          if (token.length > longestMatchLength) {
            longestMatchLength = token.length;
            bestContact = contactClean;
          }
        }
      }
    }

    if (bestContact != null) {
      return bestContact;
    }

    // 2. Fallback: Strip conversational fillers & call verbs, then test candidate tokens
    String candidate = cleanQuery;
    final allCallWords = [
      'ደውልልኝ', 'ደውይልኝ', 'ደውልላት', 'ደውልለት', 'ደውሉልኝ', 'ደውሉ',
      'ደውል', 'ደውይ', 'ደዉል', 'መደወል', 'ልደውል', 'ልትደውል', 'ልትደውዪ',
      'አደውል', 'አደውይ', 'እንዲደውል', 'እንድትደውል',
      'ስልክ ምታ', 'ስልክ ደውል', 'ስልክ ደውይ', 'ስልክ አገናኘኝ',
      'አገናኘኝ', 'አገናኚኝ', 'አገናኘው', 'አገናኝ',
      'ጥራልኝ', 'ጥሪልኝ', 'ጥራው', 'ጥራ', 'ጥሪ',
      'call', 'dial', 'phone', 'ring',
    ];
    for (final verb in allCallWords) {
      candidate = candidate.replaceAll(verb, ' ');
    }

    final conversationalFillers = [
      'እባክህ', 'እባክሽ', 'እባካችሁ', 'እባኮትን', 'ፕሊስ', 'please',
      'እስቲ', 'እስኪ', 'እስከ', 'ስቲ', 'ስኪ', 'በናትህ', 'በናትሽ',
      'አሁን', 'ቶሎ', 'በፍጥነት', 'ወዲያው', 'አንዴ',
      'ትችላለህ', 'ትችያለሽ', 'ትችላላችሁ', 'ይቻላል',
      'እፈልጋለሁ', 'እፈልግ ነበር', 'ፈልጌ ነው', 'ፈልጌ',
      'ሰውዬ', 'ሰውየው', 'ብለህ', 'ብለሽ', 'የሚባለው', 'የሚባለውን',
      'ስልክ', 'ቁጥር', 'ቁጥሩን', 'ስልኩን', 'ላይ', 'ጋር', 'ወደ',
      'ሰላም', 'ነው', 'ራስ', 'እንዴት', 'ነህ', 'ነሽ', 'ደህና', 'ነኝ',
    ];
    for (final filler in conversationalFillers) {
      candidate = candidate.replaceAll(filler, ' ');
    }

    final candidateTokens = candidate.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    for (final token in candidateTokens) {
      String stripped = token;
      if (stripped.startsWith('ለ') && stripped.length > 2) {
        stripped = stripped.substring(1);
      }
      if (stripped.endsWith('ን') && stripped.length > 2) {
        stripped = stripped.substring(0, stripped.length - 1);
      }
      if (stripped.length >= 2) {
        final matched = matchContact(stripped, availableContacts);
        if (matched != null) return matched;
      }
    }

    return null;
  }

  static Map<String, String>? _matchInstalledApp(
    String cleanQuery,
    List<Map<String, String>> availableApps,
  ) {
    if (availableApps.isEmpty) return null;

    final openWords = ['ክፈተው', 'ክፈቺ', 'ክፈት', 'አብራ', 'አሳየኝ', 'open', 'launch', 'app', 'መተግበሪያ'];
    bool hasOpenKeyword = false;
    for (final w in openWords) {
      if (cleanQuery.contains(w)) {
        hasOpenKeyword = true;
        break;
      }
    }

    // 1. Check known application aliases with priority on longer matching keys
    final sortedAliases = _appAliases.entries.toList()
      ..sort((a, b) => b.key.length.compareTo(a.key.length));

    for (final entry in sortedAliases) {
      final keyNorm = normalizeGeez(entry.key);
      if (cleanQuery.contains(keyNorm)) {
        for (final alias in entry.value) {
          final aliasLower = alias.toLowerCase();
          for (final app in availableApps) {
            final nameLower = (app['name'] ?? '').toLowerCase();
            final pkgLower = (app['packageName'] ?? '').toLowerCase();
            if (nameLower == aliasLower ||
                nameLower.contains(aliasLower) ||
                pkgLower.contains(aliasLower)) {
              return app;
            }
          }
        }
      }
    }

    if (!hasOpenKeyword) return null;

    // 2. Sliding Window / Token Filtering for Dynamic App Matching
    String candidate = cleanQuery;
    for (final w in openWords) {
      candidate = candidate.replaceAll(w, ' ');
    }

    final conversationalFillers = [
      'እባክህ', 'እባክሽ', 'እባካችሁ', 'እባኮትን', 'ፕሊስ', 'please',
      'እስቲ', 'እስኪ', 'ስቲ', 'ስኪ', 'አንዴ', 'በናትህ', 'በናትሽ',
      'ሰላም', 'ነው', 'ራስ', 'እንዴት', 'ነህ', 'ነሽ', 'ደህና', 'ደህናነኝ', 'ነኝ',
      'አሁን', 'ቶሎ', 'በፍጥነት', 'ትችላለህ', 'ትችያለሽ', 'ይቻላል',
      'እፈልጋለሁ', 'ፈልጌ', 'የሚባለው', 'የሚባለውን',
    ];
    for (final f in conversationalFillers) {
      candidate = candidate.replaceAll(f, ' ');
    }

    final tokens = candidate
        .split(RegExp(r'\s+'))
        .where((t) => t.trim().length >= 2)
        .toList();

    // Check individual tokens and bi-grams
    final searchPhrases = <String>[];
    for (int i = 0; i < tokens.length; i++) {
      searchPhrases.add(tokens[i]);
      if (i + 1 < tokens.length) {
        searchPhrases.add('${tokens[i]} ${tokens[i + 1]}');
      }
    }

    for (final phrase in searchPhrases) {
      final phraseNorm = normalizeGeez(phrase);
      final phraseLatin = transliterateFidelToLatin(phraseNorm).toLowerCase();
      if (phraseLatin.length < 3) continue;

      for (final app in availableApps) {
        final nameLower = (app['name'] ?? '').toLowerCase();
        final nameLatin = transliterateFidelToLatin(nameLower).toLowerCase();

        if (nameLower == phraseNorm || nameLower.contains(phraseNorm)) {
          return app;
        }
        if (nameLower == phraseLatin || nameLower.startsWith(phraseLatin)) {
          return app;
        }
        if (nameLatin.contains(phraseLatin) || phraseLatin.contains(nameLatin)) {
          return app;
        }

        final appTokens = nameLower.split(RegExp(r'\s+'));
        for (final appToken in appTokens) {
          if (appToken.length >= 3) {
            if (appToken == phraseLatin || appToken.startsWith(phraseLatin)) {
              return app;
            }
            if (_similarityScore(phraseLatin, appToken) >= 0.70) {
              return app;
            }
          }
        }
      }
    }

    return null;
  }

  static String? matchContact(String queryFidel, List<String> contactNames) {
    final cleanQuery = normalizeGeez(queryFidel.trim().toLowerCase());
    if (cleanQuery.isEmpty || contactNames.isEmpty) return null;

    // 1. Direct Ge'ez match
    for (final contact in contactNames) {
      final contactNorm = normalizeGeez(contact.toLowerCase());
      if (contactNorm == cleanQuery || contactNorm.contains(cleanQuery)) {
        return contact;
      }
    }

    // 2. Relationship alias resolution
    for (final entry in _relationshipAliases.entries) {
      final keyNorm = normalizeGeez(entry.key);
      if (cleanQuery.contains(keyNorm)) {
        for (final alias in entry.value) {
          for (final contact in contactNames) {
            final contactNorm = normalizeGeez(contact.toLowerCase());
            if (contactNorm.contains(normalizeGeez(alias.toLowerCase()))) {
              return contact;
            }
          }
        }
      }
    }

    // 3. Phonetic Latin transliteration match
    final queryLatin = transliterateFidelToLatin(cleanQuery).toLowerCase();
    String? bestMatch;
    double highestScore = 0.0;

    for (final contact in contactNames) {
      final contactClean = contact.trim();
      final contactLower = normalizeGeez(contactClean.toLowerCase());
      final contactLatin = transliterateFidelToLatin(contactClean).toLowerCase();

      // Guard: do not match 1 or 2 letter contact names against longer queries
      if (contactClean.length < 3 && contactClean.toLowerCase() != queryFidel.toLowerCase()) {
        continue;
      }

      final tokens = contactLatin.split(RegExp(r'\s+'));
      for (final token in tokens) {
        if (token.length >= 3 && token == queryLatin) {
          return contact;
        }

        // 1. English Phonetic Normalization (e.g. "jon" vs "john", "sara" vs "sarah")
        final tokenPhonetic = _phoneticNormalize(token);
        final queryPhonetic = _phoneticNormalize(queryLatin);
        if (tokenPhonetic.length >= 3 && (tokenPhonetic == queryPhonetic || tokenPhonetic == queryLatin)) {
          return contact;
        }

        // 2. Levenshtein edit distance check
        if (queryLatin.length >= 3 && token.length >= 3) {
          final dist = _levenshteinDistance(queryLatin, token);
          final maxLen = queryLatin.length > token.length ? queryLatin.length : token.length;
          if ((maxLen <= 5 && dist <= 1) || (maxLen > 5 && dist <= 2)) {
            final levScore = 1.0 - (dist / maxLen);
            if (levScore > highestScore && levScore >= 0.70) {
              highestScore = levScore;
              bestMatch = contact;
            }
          }
        }

        // Substring / prefix matches with strict minimum length guardrails
        if (queryLatin.length >= 3 && token.length >= 3) {
          if (token.startsWith(queryLatin) || (token.length >= 4 && queryLatin.startsWith(token))) {
            return contact;
          }
        }

        final score = _similarityScore(queryLatin, token);
        if (score > highestScore && score >= 0.70) {
          highestScore = score;
          bestMatch = contact;
        }
      }

      // Full contact phonetic similarity (comparing Latin with Latin)
      final score = _similarityScore(queryLatin, contactLatin);
      if (score > highestScore && score >= 0.68) {
        highestScore = score;
        bestMatch = contact;
      }

      // Ge'ez normalized similarity
      final geezScore = _similarityScore(cleanQuery, contactLower);
      if (geezScore > highestScore && geezScore >= 0.70) {
        highestScore = contactLower.length.toDouble();
        bestMatch = contact;
      }
    }

    return bestMatch;
  }

  static int _levenshteinDistance(String s1, String s2) {
    if (s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    List<int> v0 = List<int>.generate(s2.length + 1, (i) => i);
    List<int> v1 = List<int>.filled(s2.length + 1, 0);

    for (int i = 0; i < s1.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < s2.length; j++) {
        final cost = (s1[i] == s2[j]) ? 0 : 1;
        final minVal = (v0[j + 1] + 1 < v1[j] + 1) ? v0[j + 1] + 1 : v1[j] + 1;
        v1[j + 1] = (minVal < v0[j] + cost) ? minVal : v0[j] + cost;
      }
      for (int j = 0; j <= s2.length; j++) {
        v0[j] = v1[j];
      }
    }
    return v1[s2.length];
  }

  static String _phoneticNormalize(String input) {
    String s = input.toLowerCase();
    s = s.replaceAll('ph', 'f');
    s = s.replaceAll('th', 't');
    s = s.replaceAll('ch', 'c');
    s = s.replaceAll('sh', 's');
    s = s.replaceAll(RegExp(r'(?<=[aeiou])h(?=[a-z]|$)'), '');
    s = s.replaceAll(RegExp(r'h(?=[nrt])'), '');
    s = s.replaceAll(RegExp(r'(.)\1+'), r'$1');
    return s;
  }

  static double _similarityScore(String s1, String s2) {
    if (s1 == s2) return 1.0;
    if (s1.isEmpty || s2.isEmpty) return 0.0;

    final pairs1 = _wordPairs(s1);
    final pairs2 = _wordPairs(s2);
    final union = pairs1.length + pairs2.length;
    if (union == 0) return 0.0;

    int intersection = 0;
    for (final p in pairs1) {
      if (pairs2.contains(p)) {
        intersection++;
      }
    }

    return (2.0 * intersection) / union;
  }

  static List<String> _wordPairs(String str) {
    final pairs = <String>[];
    for (int i = 0; i < str.length - 1; i++) {
      pairs.add(str.substring(i, i + 2));
    }
    return pairs;
  }

  static bool _isGreeting(String text) {
    final t = text.trim();
    // Only exact compound phrases — single words like 'ሰላም' or 'ራስ' must NOT trigger
    final patterns = [
      'ሰላም ራስ',
      'ሰላም ራሰ',
      'ሄይ ራስ',
      'ሄይ ራሰ',
      'ሰላምራስ',
      'hey ras',
      'selam ras',
      'hello ras',
      'hi ras',
      'እንደምን አለህ',
      'እንደምን አለሽ',
      'እንደምን ዋልክ',
      'እንደምን ዋልሽ',
    ];

    for (final p in patterns) {
      if (t == p || t.startsWith('$p ') || t.endsWith(' $p') || t.contains(p)) {
        // Exclude action commands like "ለራስ ደውል"
        if (!t.contains('ደውል') &&
            !t.contains('ክፈት') &&
            !t.contains('አብራ') &&
            !t.contains('አጥፋ') &&
            !t.contains('ስንት')) {
          return true;
        }
      }
    }
    return false;
  }
}
