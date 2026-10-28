import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'mcp_tool_service.dart';

class ChatTurnResult {
  final String textResponse;
  final bool usedTool;
  final String? toolName;
  final List<Map<String, dynamic>>? rawData;

  ChatTurnResult({
    required this.textResponse,
    this.usedTool = false,
    this.toolName,
    this.rawData,
  });
}

class ModelInferenceService {
  final String endpoint;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 30);

  ModelInferenceService({
    this.endpoint = 'http://127.0.0.1:8080/v1/chat/completions',
  });

  static const String _systemPrompt = '''
You are a mobile device controller. Output JSON tool calls for device actions:
- android_open_app(app_name): Launch installed apps ONLY (e.g. camera, settings, telegram, spotify). NEVER use for songs, music, artists, albums or playlists.
- android_close_app(app_name): Close a running app process.
- android_get_app_info(app_name): Retrieve app disk size in MB.
- android_media_control(action): Control audio playback (play, pause, play_pause, next, previous, stop).
- android_play_music(query, app): Play any song, artist, album, or playlist on Spotify. Captures "play [song]", "open [artist] music", "open [artist] [song]" (e.g. "open teddy afro music merkeb" -> android_play_music).
- android_search_youtube(query): Search for any video, tutorial, song, or topic on YouTube (e.g. "search on youtube for flutter tutorial", "search yt for cat videos").
- android_set_alarm(hour, minutes, am_pm, minutes_from_now, message): Set a clock alarm. For specific times use hour, minutes, am_pm (e.g. "set alarm for 5am", "set alarm for 5:30pm"). For relative alarms from now (e.g. "set alarm 5 minutes from now", "set alarm in 10 minutes"), use minutes_from_now: N (e.g. minutes_from_now: 5).
- android_set_timer(minutes, seconds, message): Set a countdown timer (e.g. "set timer for 5 minutes", "start a 3 minute timer").
- android_send_keyevent(key): Hardware key (back, home, enter, volume_up, volume_down, power).
- android_press_home() / android_press_back(): Navigate home or back.
- android_lock_screen(): Lock device screen.
- android_list_files(query, location): Search documents and files by query or extension (pdf, png, downloads).
- android_read_file(path) / android_write_file(path, content) / android_delete_file(path): File I/O.
- android_list_storage_locations(): List storage paths.
- android_list_apps(sort_by): List or rank apps by size.
- android_toggle_flashlight(state): Turn flashlight/torch on or off (true/false).
- android_get_memory_usage(): Retrieve physical RAM usage and active processes.
- android_set_volume(stream, level, direction): Adjust volume level.
- android_get_volume(): Check current volume levels.
- android_get_device_status(): Battery percentage and hardware status.
- android_get_device_info(): Phone model and Android OS info.
- android_search_contacts(query): Look up contacts in address book.
- android_make_call(phone_number) / android_open_dialer(phone_number): Calls and dialer.
- android_send_sms(phone_number, message): Send an SMS text message.
- android_open_camera(): Open camera.
- android_open_uri(uri): Open web link or map URL.
- android_share_text(text): Share text via system dialog.
- android_get_location(): Current GPS location.
- android_get_clipboard() / android_set_clipboard(text): Clipboard text.
- android_tap(x, y) / android_swipe(start_x, start_y, end_x, end_y) / android_scroll(direction): Touch and gestures.
- android_type_text(text) / android_clear_text(): Focused field input.
- android_take_screenshot() / android_get_ui_tree(): Screen inspection and UI elements.
- android_notification_list() / android_notification_dismiss(key): Notifications.
- android_list_cameras(): Camera enumeration.
- android_open_wifi_settings() / android_open_bluetooth_settings() / android_open_sound_settings() / android_open_quick_settings(): Settings panels.

MUSIC COMMAND RULES:
- ALL music, songs, tracks, and artists (e.g. "play bohemian rhapsody", "play yirdaw tenaw music serachilgn", "play teddy afro", "open teddy afro music merkeb", "open the weeknd reminder", "open yirdaw tenaw serachilgn") ALWAYS play on Spotify by calling android_play_music(query, app: "spotify")
- NEVER interpret "open [artist] music [song]" as conversational - it ALWAYS means play music
- Music commands include: play, open, listen, play music, open music, play [song], open [song], play [artist] music, open [artist] music
- ONLY if the user explicitly says "on youtube" or "on yt" (e.g. "play bohemian rhapsody on youtube", "search on youtube for flutter tutorial"), call android_search_youtube(query)

CONVERSATIONAL RULES:
- For casual conversation, greetings, jokes, or if the user asks permission to tell a joke ("can i tell u a joke", "can i ask you something"), answer directly in concise plain text (e.g. "Sure! Go ahead, I'm listening.") with ZERO tool calls.
- Never invent placeholder URLs like "example". If no device tool fits, output direct text.
- NEVER output conversational text when user clearly wants to open/play music
''';

  static final List<Map<String, String>> _fewShotTurns = [
    {'role': 'user', 'content': 'can i tell u a joke'},
    {'role': 'assistant', 'content': 'Sure! Go ahead, I would love to hear it.'},
    {'role': 'user', 'content': 'open spotify and play music'},
    {'role': 'assistant', 'content': '{"tool": "android_open_app", "arguments": {"app_name": "spotify"}}'},
    {'role': 'user', 'content': 'open teddy afro music merkeb'},
    {'role': 'assistant', 'content': '{"tool": "android_play_music", "arguments": {"query": "teddy afro merkeb", "app": "spotify"}}'},
    {'role': 'user', 'content': 'open the weeknd reminder'},
    {'role': 'assistant', 'content': '{"tool": "android_play_music", "arguments": {"query": "the weeknd reminder", "app": "spotify"}}'},
    {'role': 'user', 'content': 'open yirdaw tenaw serachilgn'},
    {'role': 'assistant', 'content': '{"tool": "android_play_music", "arguments": {"query": "yirdaw tenaw serachilgn", "app": "spotify"}}'},
    {'role': 'user', 'content': 'play bohemian rhapsody on spotify'},
    {'role': 'assistant', 'content': '{"tool": "android_play_music", "arguments": {"query": "bohemian rhapsody", "app": "spotify"}}'},
    {'role': 'user', 'content': 'play yirdaw tenaw music serachilgn'},
    {'role': 'assistant', 'content': '{"tool": "android_play_music", "arguments": {"query": "yirdaw tenaw serachilgn", "app": "spotify"}}'},
    {'role': 'user', 'content': 'search on youtube for flutter tutorial'},
    {'role': 'assistant', 'content': '{"tool": "android_search_youtube", "arguments": {"query": "flutter tutorial"}}'},
    {'role': 'user', 'content': 'open on youtube curtis shaw tv'},
    {'role': 'assistant', 'content': '{"tool": "android_search_youtube", "arguments": {"query": "curtis shaw tv"}}'},
    {'role': 'user', 'content': 'set an alarm for 5am'},
    {'role': 'assistant', 'content': '{"tool": "android_set_alarm", "arguments": {"hour": 5, "minutes": 0, "am_pm": "am"}}'},
    {'role': 'user', 'content': 'set alarm 5 minutes from now'},
    {'role': 'assistant', 'content': '{"tool": "android_set_alarm", "arguments": {"minutes_from_now": 5}}'},
    {'role': 'user', 'content': 'set an alarm in 10 minutes'},
    {'role': 'assistant', 'content': '{"tool": "android_set_alarm", "arguments": {"minutes_from_now": 10}}'},
    {'role': 'user', 'content': 'set timer for 5 minutes'},
    {'role': 'assistant', 'content': '{"tool": "android_set_timer", "arguments": {"minutes": 5}}'},
    {'role': 'user', 'content': 'click play on the song media'},
    {'role': 'assistant', 'content': '{"tool": "android_media_control", "arguments": {"action": "play"}}'},
    {'role': 'user', 'content': 'can u turn my flashlight on'},
    {'role': 'assistant', 'content': '{"tool": "android_toggle_flashlight", "arguments": {"state": true}}'},
    {'role': 'user', 'content': 'which apllication is using memory ram biggest'},
    {'role': 'assistant', 'content': '{"tool": "android_get_memory_usage", "arguments": {}}'},
    {'role': 'user', 'content': 'how about the ras app how much is its size'},
    {'role': 'assistant', 'content': '{"tool": "android_get_app_info", "arguments": {"app_name": "amharic_assistant"}}'},
    {'role': 'user', 'content': 'how many pdf files do i have in my phone'},
    {'role': 'assistant', 'content': '{"tool": "android_list_files", "arguments": {"query": "pdf"}}'},
    {'role': 'user', 'content': 'check battery'},
    {'role': 'assistant', 'content': '{"tool": "android_get_device_status", "arguments": {}}'},
  ];

  /// Executes a full chat turn using the 2-phase tool cycle
  Future<ChatTurnResult> executeChatTurn({
    required String userPrompt,
    required List<Map<String, String>> previousTurns,
    required McpToolService mcpService,
  }) async {
    try {
      // YOUTUBE FAST PATH: If user prompt explicitly requests YouTube, route immediately to YouTube!
      if (_isYouTubeIntent(userPrompt)) {
        final ytQuery = _extractYouTubeQuery(userPrompt);
        debugPrint('[FastPathYouTube] Instantly dispatching YouTube for: "$ytQuery"');
        if (ytQuery.isEmpty) {
          final execResult = await mcpService.executeTool('android_open_app', {'app_name': 'youtube'});
          return ChatTurnResult(
            textResponse: 'Opening YouTube.',
            usedTool: true,
            toolName: 'android_open_app',
            rawData: execResult.rawData,
          );
        } else {
          final execResult = await mcpService.executeTool('android_search_youtube', {'query': ytQuery});
          return ChatTurnResult(
            textResponse: execResult.displayText.isNotEmpty ? execResult.displayText : 'Searching "$ytQuery" on YouTube.',
            usedTool: true,
            toolName: 'android_search_youtube',
            rawData: execResult.rawData,
          );
        }
      }

      // MUSIC FAST PATH: If user prompt is clearly a music playback request, execute immediately!
      // This eliminates 50-90s on-device CPU model evaluation, runner timeouts, and intent misclassification.
      final musicVerdict = _classifyMusicIntent(userPrompt);
      if (musicVerdict == _MusicVerdict.forcedMusic) {
        final forcedQuery = _extractMusicQuery(userPrompt);
        debugPrint('[FastPathMusic] Instantly dispatching music playback for: "$forcedQuery"');
        final args = <String, dynamic>{'query': forcedQuery, 'app': 'spotify'};
        final execResult = await mcpService.executeTool('android_play_music', args);
        return ChatTurnResult(
          textResponse: execResult.displayText.isNotEmpty ? execResult.displayText : 'Playing "$forcedQuery" on Spotify.',
          usedTool: true,
          toolName: 'android_play_music',
          rawData: execResult.rawData,
        );
      }

      // AMHARIC MUSIC FALLBACK: If primary fast-path did not trigger, check if prompt contains Amharic music intent cues
      final amharicMusicQuery = _extractAmharicMusicFallback(userPrompt);
      if (amharicMusicQuery != null && amharicMusicQuery.isNotEmpty) {
        debugPrint('[AmharicMusicFallback] Extracted music query: "$amharicMusicQuery"');
        final args = <String, dynamic>{'query': amharicMusicQuery, 'app': 'spotify'};
        final execResult = await mcpService.executeTool('android_play_music', args);
        return ChatTurnResult(
          textResponse: execResult.displayText.isNotEmpty ? execResult.displayText : 'Playing "$amharicMusicQuery" on Spotify.',
          usedTool: true,
          toolName: 'android_play_music',
          rawData: execResult.rawData,
        );
      }

      // ALARM FAST PATH: If user prompt is an alarm scheduling request, execute immediately!
      // This eliminates 50-90s on-device CPU model evaluation, runner timeouts, and argument misallocation.
      final alarmArgs = _extractAlarmParameters(userPrompt);
      if (alarmArgs != null) {
        debugPrint('[FastPathAlarm] Instantly scheduling alarm with arguments: $alarmArgs');
        final execResult = await mcpService.executeTool('android_set_alarm', alarmArgs);
        return ChatTurnResult(
          textResponse: execResult.displayText,
          usedTool: true,
          toolName: 'android_set_alarm',
          rawData: execResult.rawData,
        );
      }

      // GREETING FAST PATH: If user prompt is a greeting or pleasantry, answer immediately!
      // This eliminates 40-90s model runner latency and prevents raw JSON outputs.
      final greetingReply = _checkGreetingFastPath(userPrompt);
      if (greetingReply != null) {
        debugPrint('[FastPathGreeting] Instantly responding to greeting: "$userPrompt" -> "$greetingReply"');
        return ChatTurnResult(textResponse: greetingReply);
      }

      final now = DateTime.now();
      final time24 = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      final period = now.hour >= 12 ? 'PM' : 'AM';
      final hour12 = now.hour % 12 == 0 ? 12 : now.hour % 12;
      final time12 = '$hour12:${now.minute.toString().padLeft(2, '0')} $period';
      final timeZone = now.timeZoneName;
      final timeZoneOffset = '${now.timeZoneOffset.isNegative ? '-' : '+'}${now.timeZoneOffset.inHours.abs()}';

      final dynamicSystemPrompt = '''
$_systemPrompt
[CURRENT DEVICE TIME & TIMEZONE]
- Current Local Time: $time24 ($time12)
- Timezone: $timeZone (UTC$timeZoneOffset)
'''.trim();

      // 1. Build message history (system prompt + few-shot anchors + recent turns + current query)
      final safeHistory = previousTurns.length > 6 ? previousTurns.sublist(previousTurns.length - 6) : previousTurns;
      final messages = <Map<String, dynamic>>[
        {'role': 'system', 'content': dynamicSystemPrompt},
        ..._fewShotTurns,
        ...safeHistory,
        {'role': 'user', 'content': userPrompt.trim()},
      ];

      // 2. Query model for initial thought / tool call with deterministic zero temperature
      final firstRaw = await _queryModel(messages, temperature: 0.0);
      debugPrint('[ModelInference] Query: "$userPrompt" -> Model output: "$firstRaw"');
      if (firstRaw == null || firstRaw.isEmpty) {
        return ChatTurnResult(textResponse: 'Unable to generate response from model runner.');
      }

      McpToolExecutionResult? toolCall = _parseToolCall(firstRaw);

      if (toolCall == null || toolCall.toolName == null) {
        // Direct conversational answer
        if (toolCall != null && toolCall.displayText.isNotEmpty && !toolCall.displayText.startsWith('{')) {
          return ChatTurnResult(textResponse: toolCall.displayText);
        }
        final clean = _cleanModelOutput(firstRaw);
        return ChatTurnResult(textResponse: clean);
      }

      // 3. Model requested a tool call!
      final toolName = toolCall.toolName!;
      final toolArgs = toolCall.arguments;
      debugPrint('[ModelInference] Model emitted tool call: $toolName with arguments: $toolArgs');

      // 4. Execute tool natively on device
      final execResult = await mcpService.executeTool(toolName, toolArgs);

      // 5. Query model for final conversational synthesis using clean summary prompt
      final synthesisMessages = <Map<String, dynamic>>[
        {
          'role': 'system',
          'content': 'You are a friendly mobile assistant. Summarize the real device data below to answer the user question directly and concisely in natural language. Do NOT output JSON or call any tools.'
        },
        ...previousTurns,
        {'role': 'user', 'content': userPrompt.trim()},
        {
          'role': 'assistant',
          'content': 'Device action executed ($toolName).\nDevice result:\n${execResult.displayText}'
        },
        {
          'role': 'user',
          'content': 'Based on this device result, give me a clean, natural conversational answer to: "$userPrompt".'
        }
      ];

      final finalRaw = await _queryModel(synthesisMessages, temperature: 0.3);
      String finalClean = _cleanModelOutput(finalRaw ?? '');

      // CRITICAL GUARD: Never display raw JSON in the user chat bubble
      if (finalClean.isEmpty ||
          finalClean.startsWith('{') ||
          finalClean.startsWith('[') ||
          finalClean.contains('"tool":') ||
          finalClean.contains('"arguments":')) {
        finalClean = execResult.displayText;
      }

      return ChatTurnResult(
        textResponse: finalClean.isNotEmpty ? finalClean : execResult.displayText,
        usedTool: true,
        toolName: toolName,
        rawData: execResult.rawData,
      );
    } catch (e, stack) {
      debugPrint('[ModelInference] Error in chat turn execution: $e\n$stack');
      return ChatTurnResult(
        textResponse: 'Connection error while communicating with model runner: $e',
      );
    }
  }

  /// Low-level HTTP completion query to model runner
  Future<String?> _queryModel(List<Map<String, dynamic>> messages, {double temperature = 0.3}) async {
    try {
      final uri = Uri.parse(endpoint);
      final request = await _client.postUrl(uri);
      request.headers.contentType = ContentType.json;

      final payload = {
        'messages': messages,
        'temperature': temperature,
        'max_tokens': 160,
        'stop': [
          '<|im_end|>',
          '<|endoftext|>',
          '<|im_start|>',
          '\nUser:',
          '\nuser:',
          'User:',
          'user:',
        ],
      };

      final bodyBytes = utf8.encode(jsonEncode(payload));
      request.contentLength = bodyBytes.length;
      request.add(bodyBytes);

      final response = await request.close().timeout(const Duration(seconds: 90));
      if (response.statusCode != 200) {
        debugPrint('[ModelInference] Runner status: ${response.statusCode}');
        return null;
      }

      final responseBody = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
      final choices = decoded['choices'] as List?;
      if (choices == null || choices.isEmpty) return null;

      final firstChoice = choices[0] as Map<String, dynamic>;
      final message = firstChoice['message'] as Map<String, dynamic>?;
      return (message?['content'] ?? '').toString().trim();
    } catch (e) {
      debugPrint('[ModelInference] HTTP request failure: $e');
      return null;
    }
  }

  /// Lenient tool call parser supporting JSON, XML tags, and function syntax
  McpToolExecutionResult? _parseToolCall(String raw) {
    if (raw.isEmpty) return null;

    try {
      String cleanedRaw = raw.trim();
      if (cleanedRaw.endsWith(')')) {
        cleanedRaw = '${cleanedRaw.substring(0, cleanedRaw.length - 1)}}';
      }

      // 1. Look for JSON block in output
      final jsonRegex = RegExp(r'\{[\s\S]*\}');
      final match = jsonRegex.firstMatch(cleanedRaw);
      if (match != null) {
        try {
          final jsonStr = match.group(0)!;
          final parsed = jsonDecode(jsonStr);
          if (parsed is Map<String, dynamic>) {
            if (parsed.containsKey('tool')) {
              final tool = parsed['tool'].toString();
              final args = parsed['arguments'] is Map<String, dynamic>
                  ? Map<String, dynamic>.from(parsed['arguments'] as Map)
                  : <String, dynamic>{};

              if (tool == 'android_talk' || tool == 'talk' || tool == 'chat') {
                final talkText = (args['query'] ?? args['message'] ?? args['text'] ?? '').toString();
                return McpToolExecutionResult(
                  isToolCall: false,
                  displayText: talkText.isNotEmpty ? talkText : 'I am listening!',
                );
              }

              return McpToolExecutionResult(
                isToolCall: true,
                toolName: tool,
                arguments: args,
                displayText: 'Executing $tool...',
              );
            }

            if (parsed.containsKey('name') && (parsed.containsKey('arguments') || parsed.containsKey('parameters'))) {
              final name = parsed['name'].toString();
              final rawArgs = parsed['arguments'] ?? parsed['parameters'];
              final args = rawArgs is Map<String, dynamic>
                  ? Map<String, dynamic>.from(rawArgs)
                  : <String, dynamic>{};
              return McpToolExecutionResult(
                isToolCall: true,
                toolName: name,
                arguments: args,
                displayText: 'Executing $name...',
              );
            }
          }
        } catch (_) {}
      }

      // 2. Fallback regex extraction if JSON syntax was slightly malformed
      final toolRegex = RegExp(r'"tool"\s*:\s*"([^"]+)"');
      final toolMatch = toolRegex.firstMatch(cleanedRaw);
      if (toolMatch != null) {
        final toolName = toolMatch.group(1)!;
        final args = <String, dynamic>{};
        final appMatch = RegExp(r'"(?:app_name|package_name)"\s*:\s*"([^"]+)"').firstMatch(cleanedRaw);
        if (appMatch != null) args['app_name'] = appMatch.group(1)!;
        final queryMatch = RegExp(r'"query"\s*:\s*"([^"]+)"').firstMatch(cleanedRaw);
        if (queryMatch != null) args['query'] = queryMatch.group(1)!;
        final sortMatch = RegExp(r'"(?:sort_by|filter)"\s*:\s*"([^"]+)"').firstMatch(cleanedRaw);
        if (sortMatch != null) args['sort_by'] = sortMatch.group(1)!;

        return McpToolExecutionResult(
          isToolCall: true,
          toolName: toolName,
          arguments: args,
          displayText: 'Executing $toolName...',
        );
      }

      // 3. Look for XML style <tool_call> blocks
      final xmlRegex = RegExp(r'<tool_call>([\s\S]*?)<\/tool_call>');
      final xmlMatch = xmlRegex.firstMatch(raw);
      if (xmlMatch != null) {
        return _parseToolCall(xmlMatch.group(1)!);
      }
    } catch (_) {}

    return null;
  }

  /// Strips formatting tags, special tokens, and unwraps JSON objects to plain text
  String _cleanModelOutput(String raw) {
    String clean = raw
        .replaceAll(RegExp(r'<tool_call>[\s\S]*?<\/tool_call>'), '')
        .replaceAll('<|im_end|>', '')
        .replaceAll('<|im_start|>', '')
        .replaceAll('<|endoftext|>', '');

    final userIdx = clean.indexOf(RegExp(r'(\n|^)User:', caseSensitive: false));
    if (userIdx != -1) {
      clean = clean.substring(0, userIdx);
    }
    clean = clean.trim();

    // JSON CLEANUP: If the model emitted a JSON payload instead of plain text, extract the human text
    if (clean.startsWith('{') && clean.endsWith('}')) {
      try {
        final decoded = jsonDecode(clean);
        if (decoded is Map<String, dynamic>) {
          if (decoded.containsKey('arguments') && decoded['arguments'] is Map) {
            final args = decoded['arguments'] as Map;
            final text = args['text'] ?? args['query'] ?? args['message'];
            if (text != null && text.toString().trim().isNotEmpty) {
              return text.toString().trim();
            }
          }
          final text = decoded['text'] ?? decoded['message'] ?? decoded['response'] ?? decoded['content'];
          if (text != null && text.toString().trim().isNotEmpty) {
            return text.toString().trim();
          }
        }
      } catch (_) {}
    }

    // Regex fallback if JSON was malformed or partial
    if (clean.startsWith('{')) {
      final textMatch = RegExp(r'"(?:text|message|response|content|query)"\s*:\s*"([^"]+)"').firstMatch(clean);
      if (textMatch != null) {
        return textMatch.group(1)!.trim();
      }
      // If it's a raw tool call dump like {"tool": ...} that couldn't be parsed
      if (clean.contains('"tool"')) {
        return 'ሰላም! እንዴት ልርዳዎት?';
      }
    }

    return clean;
  }

  /// Returns a clean instant greeting if user prompt is a greeting or pleasantry
  String? _checkGreetingFastPath(String prompt) {
    final p = prompt.trim().toLowerCase();

    // English greetings
    final englishGreeting = RegExp(r'^(hi|hello|hey|hey\s+there|hello\s+there|good\s+(morning|afternoon|evening|day)|greetings|howdy|sup|yo)[\s!.,?]*$').hasMatch(p);
    if (englishGreeting) {
      return 'Hello! How can I help you today?';
    }

    final englishAssistance = RegExp(r'^(how\s+are\s+you|who\s+are\s+you|what\s+can\s+you\s+do)[\s!.,?]*$').hasMatch(p);
    if (englishAssistance) {
      return 'I am your on-device personal assistant. I can open apps, search files, set alarms, play music, and answer questions.';
    }

    // Amharic greetings & pleasantries
    final amharicGreeting = RegExp(r'^(ሰላም|ሰላምታ|ሰላም\s*ነው|እንዴት\s*(ነህ|ነሽ|ኖት|ናችሁ)|እንደምን\s*(አለህ|አለሽ|አሉ|አደሩ|አደርክ|አደርሽ|ዋሉ|ዋልክ|ዋልሽ)|ታዲያስ|ጤና\s*ይስጥልኝ)[\s!.,?፣፤]*$').hasMatch(p);
    if (amharicGreeting) {
      return 'ሰላም! እንዴት ልርዳዎት? ምን ማድረግ እችላለሁ?';
    }

    return null;
  }

  /// Classifies whether the raw user prompt is a music playback request.
  /// YouTube is honoured only when explicitly mentioned ("on youtube" / "yt").
  _MusicVerdict _classifyMusicIntent(String prompt) {
    final p = prompt.trim().toLowerCase();

    // Explicit YouTube requests are never force-routed to Spotify
    final explicitYt = RegExp(r'\b(on\s+)?(you\s*tube|yt)\b').hasMatch(p);
    if (explicitYt) return _MusicVerdict.none;

    // Music cues: playback verbs plus media nouns, or a bare "play X" pattern
    final hasPlayVerb = RegExp(r'^\s*(play|put on|listen to)\b').hasMatch(p) ||
        RegExp(r'\b(plays?|listening)\b').hasMatch(p);
    final hasMusicNoun = RegExp(r'\b(music|song|songs|track|tracks|album|playlist|artist)\b').hasMatch(p);
    final hasOpenMusic = RegExp(r'\bopen\b').hasMatch(p) && hasMusicNoun;
    final hasBarePlay = RegExp(r'^\s*play\b').hasMatch(p) && p.trim().split(RegExp(r'\s+')).length >= 2;

    if (hasBarePlay || (hasPlayVerb && hasMusicNoun) || hasOpenMusic) {
      return _MusicVerdict.forcedMusic;
    }
    return _MusicVerdict.none;
  }

  /// Builds a clean music search query from the RAW user prompt.
  /// Model-sliced queries are trusted only when they retain most of the
  /// prompt's meaningful words; otherwise the prompt itself is sliced.
  String _extractMusicQuery(String prompt, {String? modelQuery}) {
    final model = (modelQuery ?? '').trim();
    final meaningful = RegExp(r'[a-zA-Z0-9\u1200-\u137F]').allMatches(prompt.toLowerCase()).length;
    if (model.isNotEmpty && meaningful > 0) {
      final modelWords = RegExp(r'[a-zA-Z0-9\u1200-\u137F]').allMatches(model.toLowerCase()).length;
      final modelRatio = modelWords / meaningful;
      final modelHasMusicVerb = RegExp(r'\b(play|open|music|song|called)\b').hasMatch(model.toLowerCase());
      // Trust model query only if it kept >=60% of content AND has no leftover verbs
      if (modelRatio >= 0.6 && !modelHasMusicVerb) {
        return model;
      }
    }

    // Deterministic slicing from raw prompt
    var q = prompt.trim().toLowerCase();
    q = q.replaceFirst(RegExp(r'^(please\s+)?(play|open|ope|put on|listen to)\s+'), '');
    q = q.replaceAll(RegExp(r'\b(music|song|songs|track|tracks|called|named|on spotify|in spotify|please|thanks|thank you)\b'), ' ');
    q = q.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (q.isEmpty) q = prompt.trim();
    return q;
  }

  /// Checks if the prompt explicitly requests YouTube
  bool _isYouTubeIntent(String prompt) {
    final p = prompt.trim().toLowerCase();
    return RegExp(r'\b(you\s*tube|yt)\b|\u12e9\u1272\u12e9\u1265|\u12e9\u1275\u12e9\u1265').hasMatch(p);
  }

  /// Extracts the clean search query for YouTube by stripping verbs and YouTube keywords
  String _extractYouTubeQuery(String prompt) {
    var q = prompt.trim().toLowerCase();
    // Strip leading verbs / filler
    q = q.replaceFirst(RegExp(r'^(please\s+)?(open|search|find|play|look for|show me)\s+'), '');
    // Strip "on youtube", "in youtube", "from youtube", "for youtube", "youtube", "yt"
    q = q.replaceAll(RegExp(r'\b(on\s+|in\s+|from\s+|for\s+)?(you\s*tube|yt)\b|\u12e9\u1272\u12e9\u1265|\u12e9\u1275\u12e9\u1265'), ' ');
    // Strip trailing or leading "for", "called", "please", "thanks"
    q = q.replaceAll(RegExp(r'\b(for|called|named|video|videos|channel|please|thanks|thank you)\b'), ' ');
    q = q.replaceAll(RegExp(r'\s+'), ' ').trim();
    return q;
  }

  /// Amharic Music Fallback: extracts artist / song from Amharic phrasing (e.g. "የቴዲ አፍሮን ሙዚቃ ክፍት")
  String? _extractAmharicMusicFallback(String prompt) {
    final p = prompt.trim();
    // Check for Amharic music markers (ሙዚቃ, ዘፈን, አጫውት, ክፈት, ክፍት, ክፈትልኝ)
    final hasAmharicMusic = RegExp(r'(\u1219\u12da\u1243|\u12d8\u1348\u1295|\u12a0\u132b\u12cd\u1275|\u12ad\u1348\u1275|\u12ad\u134d\u1275|\u12ad\u1348\u1275\u120d\u129d)').hasMatch(p);
    if (!hasAmharicMusic) return null;

    // Mapping known Ethiopian artist names in Ge'ez to Spotify Latin search queries
    const artistMap = {
      'ቴዲ አፍሮ': 'Teddy Afro',
      'ቴዲ': 'Teddy Afro',
      'ይርዳው ጠናው': 'Yirdaw Tenaw',
      'ይርዳው': 'Yirdaw Tenaw',
      'አስቴር አወቀ': 'Aster Aweke',
      'አስቴር': 'Aster Aweke',
      'ኤፍሬም ታምሩ': 'Ephrem Tamiru',
      'ኤፍሬም': 'Ephrem Tamiru',
      'ሮፍናን': 'Rophnan',
      'መሀሙድ አህመድ': 'Mahmoud Ahmed',
      'መሐሙድ': 'Mahmoud Ahmed',
      'ጥላሁን ገሰሰ': 'Tilahun Gessesse',
      'ጥላሁን': 'Tilahun Gessesse',
      'አሊ ቢራ': 'Ali Birra',
      'ጎሳዬ ተስፋዬ': 'Gosaye Tesfaye',
      'ጎሳዬ': 'Gosaye Tesfaye',
      'ታምራት ደስታ': 'Tamrat Desta',
      'ጃምቦ ጆቴ': 'Jambo Jote',
      'ሃጫሉ ሁንዴሳ': 'Hachalu Hundessa',
      'ሃጫሉ': 'Hachalu Hundessa',
      'አቢነት አጎናፍር': 'Abinet Agonafir',
      'አቢነት': 'Abinet Agonafir',
    };

    // Check if any known artist matches
    for (final entry in artistMap.entries) {
      if (p.contains(entry.key)) {
        var songPart = p
            .replaceAll(RegExp(r'(\u12e8|\u1208)?' + RegExp.escape(entry.key) + r'(\u1295)?'), ' ')
            .replaceAll(RegExp(r'(\u1219\u12da\u1243|\u12d8\u1348\u1295|\u12a0\u132b\u12cd\u1275|\u12ad\u1348\u1275|\u12ad\u134d\u1275|\u12ad\u1348\u1275\u120d\u129d|\u12a5\u1263\u12ad\u1205|\u12a5\u1235\u1272|\u12a5\u1235\u12ad)'), ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        if (songPart == 'መርከብ') songPart = 'Merkeb';
        if (songPart.isNotEmpty && songPart.length > 2) {
          return '${entry.value} $songPart';
        }
        return entry.value;
      }
    }

    // Generic Amharic cleaner if artist is not in the map
    var clean = p
        .replaceAll(RegExp(r'(\u1219\u12da\u1243|\u12d8\u1348\u1295|\u12a0\u132b\u12cd\u1275|\u12ad\u1348\u1275|\u12ad\u134d\u1275|\u12ad\u1348\u1275\u120d\u129d|\u12a5\u1263\u12ad\u1205|\u12a5\u1235\u1272|\u12a5\u1235\u12ad)'), ' ')
        .replaceAll(RegExp(r'^\s*(\u12e8|\u1208)'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return clean.isNotEmpty ? clean : null;
  }

  /// Deterministic Alarm Fast-Path Extractor
  Map<String, dynamic>? _extractAlarmParameters(String prompt) {
    final p = prompt.trim();
    final lower = p.toLowerCase();

    // Check if the prompt contains alarm intent cues in English or Amharic
    final hasEnglishAlarm = lower.contains('alarm') || lower.contains('wake me up');
    final hasAmharicAlarm = p.contains('ማንቂያ') || p.contains('ቀስቅሰኝ') || p.contains('ቀስቅሺኝ');
    if (!hasEnglishAlarm && !hasAmharicAlarm) return null;

    // 1. Relative alarm: "in 5 minutes", "5 minutes from now", "ከ 10 ደቂቃ በኋላ"
    final relEn = RegExp(r'(?:in|after|from\s+now)\s+(\d+)\s*(?:min|minute|minutes)', caseSensitive: false).firstMatch(lower) ??
                  RegExp(r'(\d+)\s*(?:min|minute|minutes)\s+(?:from\s+now|later)', caseSensitive: false).firstMatch(lower);
    if (relEn != null) {
      final mins = int.tryParse(relEn.group(1) ?? '') ?? 5;
      final target = DateTime.now().add(Duration(minutes: mins));
      return {
        'hour': target.hour,
        'minutes': target.minute,
        'message': 'Alarm',
      };
    }
    final relAm = RegExp(r'(\d+)\s*ደቂቃ', caseSensitive: false).firstMatch(p);
    if (relAm != null) {
      final mins = int.tryParse(relAm.group(1) ?? '') ?? 5;
      final target = DateTime.now().add(Duration(minutes: mins));
      return {
        'hour': target.hour,
        'minutes': target.minute,
        'message': 'ማንቂያ',
      };
    }

    // Determine period: AM vs PM, morning vs evening/night
    final isMorning = lower.contains('morning') || lower.contains('am') || p.contains('ጠዋት') || p.contains('ጧት');
    final isAfternoon = lower.contains('afternoon') || p.contains('ከሰዓት');
    final isNight = lower.contains('night') || lower.contains('evening') || lower.contains('pm') || p.contains('ማታ') || p.contains('ምሽት');

    // 2. Explicit time with colon: "9:00 am", "7:30pm", "9:00"
    final timeColonMatch = RegExp(r'(\d{1,2}):(\d{2})\s*(am|pm)?', caseSensitive: false).firstMatch(lower);
    if (timeColonMatch != null) {
      var h = int.tryParse(timeColonMatch.group(1) ?? '') ?? 9;
      final m = int.tryParse(timeColonMatch.group(2) ?? '') ?? 0;
      final periodGroup = (timeColonMatch.group(3) ?? '').toLowerCase();
      if (periodGroup == 'pm' || (!isMorning && (isNight || isAfternoon))) {
        if (h < 12) h += 12;
      } else if (periodGroup == 'am' || isMorning) {
        if (h == 12) h = 0;
      }
      return {
        'hour': h,
        'minutes': m,
        'message': 'Alarm',
      };
    }

    // 3. Explicit time with AM/PM: "9am", "9 am", "5pm"
    final amPmMatch = RegExp(r'(\d{1,2})\s*(am|pm)', caseSensitive: false).firstMatch(lower);
    if (amPmMatch != null) {
      var h = int.tryParse(amPmMatch.group(1) ?? '') ?? 9;
      final period = amPmMatch.group(2)!.toLowerCase();
      if (period == 'pm') {
        if (h < 12) h += 12;
      } else if (period == 'am') {
        if (h == 12) h = 0;
      }
      return {
        'hour': h,
        'minutes': 0,
        'message': 'Alarm',
      };
    }

    // 4. Time with word markers: "for 9 in morning", "for 9 in the morning", "at 9 tonight", "for 9"
    final wordMatch = RegExp(r'(?:for|at)\s+(\d{1,2})\b', caseSensitive: false).firstMatch(lower);
    if (wordMatch != null) {
      var h = int.tryParse(wordMatch.group(1) ?? '') ?? 9;
      if (isNight || isAfternoon) {
        if (h < 12) h += 12;
      } else if (isMorning) {
        if (h == 12) h = 0;
      }
      return {
        'hour': h,
        'minutes': 0,
        'message': 'Alarm',
      };
    }

    // 5. Amharic time with "ሰዓት": "3 ሰዓት", "9 ሰዓት"
    final amharicTimeMatch = RegExp(r'(\d{1,2})\s*ሰዓት').firstMatch(p);
    if (amharicTimeMatch != null) {
      var h = int.tryParse(amharicTimeMatch.group(1) ?? '') ?? 3;
      // Ethiopian time mapping: "ጠዋት 3 ሰዓት" is 9:00 AM standard!
      // But if user said 9 directly (e.g. "ጠዋት 9 ሰዓት"), preserve 9 AM standard.
      if (isMorning) {
        if (h == 3) h = 9;
        else if (h == 1) h = 7;
        else if (h == 2) h = 8;
        else if (h == 4) h = 10;
        else if (h == 5) h = 11;
        else if (h == 6) h = 12;
        else if (h == 12) h = 6;
      } else if (isNight || isAfternoon) {
        if (h == 1) h = 19;
        else if (h == 2) h = 20;
        else if (h == 3) h = 21;
        else if (h == 4) h = 22;
        else if (h == 5) h = 23;
        else if (h < 12) h += 12;
      }
      return {
        'hour': h,
        'minutes': 0,
        'message': 'ማንቂያ',
      };
    }

    return null;
  }
}

enum _MusicVerdict { none, forcedMusic }
